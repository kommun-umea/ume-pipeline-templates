param (
    [string]$variableGroup,
    [string]$zipFilePath,
    [string]$personalAccessToken,
    [string]$organizationName = 'umeakommun',
    [string]$projectName = 'turkos'
)
$ErrorActionPreference = 'Stop'

# Function to fetch variables from Azure DevOps
function Get-VariableGroupValues {
    param (
        [string]$variableGroup,
        [string]$organizationName,
        [string]$projectName,
        [string]$personalAccessToken
    )

    $url = "https://dev.azure.com/$organizationName/$projectName/_apis/distributedtask/variablegroups?groupName=$variableGroup&api-version=7.1"

    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$personalAccessToken"))
    $headers = @{
        Authorization = "Basic $base64AuthInfo"
    }

    $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    $variableObjects = $response.value.variables

    # Convert PSCustomObject to Hashtable
    $variableHashtable = @{}
    foreach ($key in $variableObjects.PSObject.Properties.Name) {
        $variableHashtable[$key] = $variableObjects.$key.value
    }

    return $variableHashtable
}

# Function to check if an object has a specific property or key (works for both Hashtable and PSCustomObject)
function Get-HasProperty {
    param (
        [Object]$obj,
        [string]$property
    )

    if ($obj -is [System.Collections.Hashtable]) {
        return $obj.ContainsKey($property)
    }
    elseif ($obj -is [PSCustomObject]) {
        return $null -ne $obj.PSObject.Properties[$property]
    }
    else {
        return $false
    }
}

# Function to update a nested property in a JSON object
function Set-JsonProperty {
    param (
        [ref]$jsonObject,
        [string]$propertyPath,
        [string]$newValue
    )

    # Split the key path into its components using the dot separator
    $pathParts = $propertyPath -split '\.'

    $target = $jsonObject.Value
    for ($i = 0; $i -lt $pathParts.Length; $i++) {
        if (-not (Get-HasProperty -obj $target -property $pathParts[$i])) {
            Write-Error "Property '$($propertyPath)' does not exist in appsettings.json"
        }

        if ($i -lt $pathParts.Length - 1) {
            $target = $target.$($pathParts[$i])
            continue
        }

        $target.$($pathParts[$i]) = $newValue
    }
}

# Function to extract and update appsettings.json from ZIP without using a temp directory
function Update-AppSettingsInZip {
    param (
        [string]$zipFilePath,
        [hashtable]$variables
    )

    # Load the System.IO.Compression assembly
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    # Create a System.IO.Compression.ZipArchive object for the zip file
    $zipArchive = [System.IO.Compression.ZipFile]::Open($zipFilePath, [System.IO.Compression.ZipArchiveMode]::Update)

    try {
        # Find the appsettings.json entry in the ZIP
        $appSettingsEntry = $zipArchive.Entries | Where-Object { $_.FullName -eq "appsettings.json" }
        if (-not $appSettingsEntry) {
            Write-Error "appsettings.json not found in the ZIP file."
            return
        }

        # Read the appsettings.json content
        $reader = [System.IO.StreamReader]::new($appSettingsEntry.Open())
        $jsonContent = $reader.ReadToEnd()
        $reader.Close()

        # Convert JSON to object
        $jsonObject = $jsonContent | ConvertFrom-Json

        # Update JSON with the variables from the variable group
        foreach ($key in $variables.Keys) {
            $value = $variables[$key]
            Set-JsonProperty -jsonObject ([ref]$jsonObject) -propertyPath $key -newValue $value
        }

        # Convert updated JSON back to string
        $updatedJson = $jsonObject | ConvertTo-Json -Depth 100

        # Overwrite the appsettings.json entry with the updated content
        $writer = [System.IO.StreamWriter]::new($appSettingsEntry.Open())
        $writer.BaseStream.SetLength(0)  # Clear the previous content
        $writer.Write($updatedJson)
        $writer.Close()

    }
    finally {
        # Ensure the archive is properly disposed
        $zipArchive.Dispose()
    }
}

# Main script logic
$variables = Get-VariableGroupValues -variableGroup $variableGroup -organizationName $organizationName -projectName $projectName -personalAccessToken $personalAccessToken

# Update appsettings.json inside the ZIP file
Update-AppSettingsInZip -zipFilePath $zipFilePath -variables $variables
