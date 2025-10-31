# ------------ Parameters ------------
[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [ValidateSet("dev", "test", "prod")]
    [String] $environment,

    [Parameter(Mandatory = $true)]
    [String] $variableGroupName,

    [Parameter(Mandatory = $true)]
    [String] $keyVaultName,

    [Parameter(Mandatory = $true)]
    [String]$personalAccessToken,

    [Parameter(Mandatory = $false)]
    [String]$organizationName = 'umeakommun',

    [Parameter(Mandatory = $false)]
    [String]$projectName = 'Turkos'
)

# ------------ Variables ------------
$variableGroupsBaseUri = "https://dev.azure.com/${organizationName}/${projectName}/_apis/distributedtask/variablegroups"
$variableGroupsApiVersion = '7.1'
$personalAccessTokenBase64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(('{0}:{1}' -f '', $personalAccessToken)))

# ------------ Functions ------------
Function Get-VariableGroupId($variableGroupName) {
    Write-Host "[Ume]: Fetching variable group..."
    $variableGroupsUri = "${variableGroupsBaseUri}?api-version=${variableGroupsApiVersion}"
    $variableGroups = Invoke-RestMethod -Uri $variableGroupsUri -Method Get -Headers @{Authorization = ('Basic {0}' -f $personalAccessTokenBase64) }
    $variableGroup = $variableGroups.value | Where-Object { $_.name -eq $variableGroupName }

    if ($null -eq $variableGroup) {
        throw "[Ume]: Variable group [$variableGroupName] was not found!"
    }

    Write-Host "[Ume]: Found variable group with id [$($variableGroup.id)]"

    return $variableGroup.id
}

Function Get-Secrets-In-KeyVault($keyVaultName) {
    Write-Host "[Ume]: Fetching secrets from key vault..."

    $secrets = @()
    $secretIds = az keyvault secret list --vault-name $keyVaultName --query "[].id" | ConvertFrom-Json

    foreach ($secretId in $secretIds) {
        $secret = az keyvault secret show --id $secretId --query "{name:name, value:value}" | ConvertFrom-Json
        $secrets += $secret
    }

    if ($secrets.Count -ne 0) {
        Write-Host "[Ume]: Found secret(s) in key vault ($($secrets.Count))"
    }
    else {
        Write-Host "[Ume]: Found no secrets in key vault"
    }

    return $secrets
}

Function Get-Secrets-In-VariableGroup($variableGroupId) {
    Write-Host "[Ume]: Fetching secrets from variable group..."

    $variableGroupsUri = "${variableGroupsBaseUri}/${variableGroupId}?api-version=${variableGroupsApiVersion}"
    $response = Invoke-RestMethod -Uri $variableGroupsUri -Method Get -Headers @{Authorization = ('Basic {0}' -f $personalAccessTokenBase64) }
    $secrets = @($response.variables.PSObject.Properties | ForEach-Object {
            [PSCustomObject]@{
                name  = $_.Name
                value = $_.Value.value
            }
        })

    if ($secrets.Count -ne 0) {
        Write-Host "[Ume]: Found secret(s) in variable group ($($secrets.Count))"
    }
    else {
        Write-Host "[Ume]: Found no secrets in variable group"
    }

    return $secrets
}

Function Get-Secret-Actions($variableGroupSecrets, $keyVaultSecrets) {
    $secretActions = @{
        add    = @()
        update = @()
        remove = @()
    }

    foreach ($variableGroupSecret in $variableGroupSecrets) {
        $matchingSecret = $keyVaultSecrets | Where-Object { $_.name -eq $variableGroupSecret.name }
        if ($matchingSecret) {
            if ($matchingSecret.value -ne $variableGroupSecret.value) {
                $secretActions.update += $variableGroupSecret
            }
        }
        else {
            $secretActions.add += $variableGroupSecret
        }
    }

    foreach ($keyVaultSecret in $keyVaultSecrets) {
        $matchingSecret = $variableGroupSecrets | Where-Object { $_.name -eq $keyVaultSecret.name }
        if (-not $matchingSecret) {
            $secretActions.remove += $keyVaultSecret
        }
    }

    return $secretActions
}

Function Remove-Secrets-In-KeyVault($keyVaultName, $secrets) {
    if ($secrets.Count -ne 0) {
        Write-Host "[Ume]: Found secret(s) to remove ($($secrets.Count))"
    }
    else {
        Write-Host "[Ume]: Found no secrets to remove"
        return
    }

    foreach ($secret in $secrets) {
        Write-Host "[Ume]: --- Secret [$($secret.name)] ---"
        Write-Host "[Ume]: Removing secret..."
        az keyvault secret delete --vault-name $keyVaultName --name=$($secret.name) --output none
        if ($LASTEXITCODE -ne 0) {
            throw "[Ume]: Failed to remove secret [$($secret.name)]!"
        }
    }
}

Function Update-Secrets-In-KeyVault($keyVaultName, $secrets) {
    if ($secrets.Count -ne 0) {
        Write-Host "[Ume]: Found secret(s) to update ($($secrets.Count))"
    }
    else {
        Write-Host "[Ume]: Found no secrets to update"
        return
    }

    foreach ($secret in $secrets) {
        Write-Host "[Ume]: --- Secret [$($secret.name)] ---"
        Write-Host "[Ume]: Disabling existing secret..."
        az keyvault secret set-attributes --vault-name $keyVaultName --name=$($secret.name) --enabled false --output none
        if ($LASTEXITCODE -ne 0) {
            throw "[Ume]: Failed to disable existing secret [$($secret.name)]!"
        }

        Write-Host "[Ume]: Updating secret..."
        az keyvault secret set --vault-name $keyVaultName --name=$($secret.name) --value=$($secret.value) --output none
        if ($LASTEXITCODE -ne 0) {
            throw "[Ume]: Failed to update secret [$($secret.name)]!"
        }
    }
}

Function Add-Secrets-To-KeyVault($keyVaultName, $secrets) {
    if ($secrets.Count -ne 0) {
        Write-Host "[Ume]: Found secret(s) to add ($($secrets.Count))"
    }
    else {
        Write-Host "[Ume]: Found no secrets to add"
        return
    }

    Write-Host "[Ume]: Fetching soft deleted secrets..."
    $softDeletedSecrets = az keyvault secret list-deleted --vault-name $keyVaultName --query "[].name" | ConvertFrom-Json
    if ($softDeletedSecrets.Count -ne 0) {
        Write-Host "[Ume]: Found soft deleted secret(s) ($($softDeletedSecrets.Count))"
    }
    else {
        Write-Host "[Ume]: Found no soft deleted secrets"
    }

    foreach ($secret in $secrets) {
        Write-Host "[Ume]: --- Secret [$($secret.name)] ---"
        Write-Host "[Ume]: Validating secret availability..."
        if ($softDeletedSecrets -contains $secret.name) {
            throw "[Ume]: Secret [$($secret.name)] is soft deleted and cannot be added!"
        }

        Write-Host "[Ume]: Adding secret..."
        az keyvault secret set --vault-name $keyVaultName --name=$($secret.name) --value=$($secret.value) --output none
        if ($LASTEXITCODE -ne 0) {
            throw "[Ume]: Failed to add secret [$($secret.name)]!"
        }
    }
}

# ------------ Main ------------
try {
    $ErrorActionPreference = "Stop"

    Write-Host "[Ume]: Environment = [$environment]"
    Write-Host "[Ume]: Variable Group = [$variableGroupName]"
    Write-Host "[Ume]: Key Vault = [$keyVaultName]"
    Write-Host "[Ume]: Organization = [$organizationName]"
    Write-Host "[Ume]: Project = [$projectName]"
    Write-Host

    $variableGroupId = Get-VariableGroupId -variableGroupName $variableGroupName
    $variableGroupSecrets = Get-Secrets-In-VariableGroup -variableGroupId $variableGroupId
    $keyVaultSecrets = Get-Secrets-In-KeyVault -keyVaultName $keyVaultName
    $secretActions = Get-Secret-Actions -variableGroupSecrets $variableGroupSecrets -keyVaultSecrets $keyVaultSecrets

    Remove-Secrets-In-KeyVault -keyVaultName $keyVaultName -secrets $secretActions.remove
    Update-Secrets-In-KeyVault -keyVaultName $keyVaultName -secrets $secretActions.update
    Add-Secrets-To-KeyVault -keyVaultName $keyVaultName -secrets $secretActions.add

    Write-Host "[Ume]: Done!"
}
catch {
    Write-Error $_
    exit 1
}
