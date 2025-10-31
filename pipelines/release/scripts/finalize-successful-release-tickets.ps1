Import-Module ([System.IO.Path]::GetFullPath("$PSScriptRoot/../../../utilities/throw-error-helper.psm1"))
$ErrorActionPreference = 'Stop'

$accessToken = $env:SYSTEM_ACCESSTOKEN
$ticketIdsString = $env:TICKET_IDS
$tag = $env:TAG
$userName = $env:BUILD_REQUESTEDFOR
$userEmail = $env:BUILD_REQUESTEDFOREMAIL
$buildId = $env:BUILD_BUILDID
$devopsBaseUrl = $env:SYSTEM_COLLECTIONURI
$projectName = $env:SYSTEM_TEAMPROJECT

if ([string]::IsNullOrWhiteSpace($accessToken)) {
    ThrowError("Access Token is not provided.")
}
if ([string]::IsNullOrWhiteSpace($ticketIdsString)) {
    Write-Host "No tickets to initialize."
    exit 0
}
if ([string]::IsNullOrWhiteSpace($tag)) {
    ThrowError("Tag is not provided.")
}
if ([string]::IsNullOrWhiteSpace($userName)) {
    ThrowError("User Name is not provided.")
}
if ([string]::IsNullOrWhiteSpace($userEmail)) {
    ThrowError("User Email is not provided.")
}
if ([string]::IsNullOrWhiteSpace($buildId)) {
    ThrowError("Build ID is not provided.")
}
if ([string]::IsNullOrWhiteSpace($devopsBaseUrl)) {
    ThrowError("DevOps Base URL is not provided.")
}
if ([string]::IsNullOrWhiteSpace($projectName)) {
    ThrowError("Project Name is not provided.")
}

$authenticationHeader = @{
    Authorization = "Bearer $accessToken"
}
$authenticationHeader = $authenticationHeader
$patchAuthenticationHeader = ($authenticationHeader + @{ "Content-Type" = "application/json-patch+json" })
$baseUrl = "$devopsBaseUrl$projectName/_apis"
$releasePipelinesBaseUrl = "$devopsBaseUrl$projectName/_build?view=runs&tagFilter="
$apiVersion = "api-version=7.1"

$pipelineRunUrl = "$baseUrl/build/builds/$($buildId)?$apiVersion"
$pipelineRun = Invoke-RestMethod -Uri $pipelineRunUrl -Headers $authenticationHeader -Method Get
$pipelineRunStartTime = [DateTime]::Parse($pipelineRun.startTime).ToString("o")
$finishedTime = [DateTime]::UtcNow.ToString("o")
$releaseIdentity = "$userName <$userEmail>"

$ticketIds = [int[]]($ticketIdsString -split ';')

$workItemsBatchUri = "$baseUrl/wit/workitemsbatch?$apiVersion"
$body = @{
    ids    = $ticketIds
    fields = @(
        "Custom.ReleasePipelines",
        "Custom.ReleaseStarted",
        "System.AssignedTo"
    )
} | ConvertTo-Json -Depth 10
$workItemsBatchResponse = Invoke-RestMethod `
    -Method POST `
    -Uri $workItemsBatchUri `
    -Headers $authenticationHeader `
    -ContentType "application/json" `
    -Body $body
$workItems = $workItemsBatchResponse.value | Select-Object `
@{ Name = "id"; Expression = { $_.id } },
@{ Name = "releasePipelinesField"; Expression = { $_.fields."Custom.ReleasePipelines" } },
@{ Name = "releaseStarted"; Expression = { $_.fields."Custom.ReleaseStarted" } },
@{ Name = "assignedTo"; Expression = { $_.fields."System.AssignedTo" } }

foreach ($workItem in $workItems) {
    $ticketUrl = "$baseUrl/wit/workitems/$($workItem.id)?$apiVersion"
    $releasePipelinesUrl = "$releasePipelinesBaseUrl$tag"
    $startedTime = $pipelineRunStartTime

    if (-not [string]::IsNullOrWhiteSpace($workItem.releaseStarted)) {
        $startedTime = $workItem.releaseStarted
    }

    if ($workItem.releasePipelinesField.Length -gt 0 -and $workItem.releasePipelinesField -like "$releasePipelinesBaseUrl*") {
        $tags = $workItem.releasePipelinesField.Substring($releasePipelinesBaseUrl.Length) -split ','
        if ($tags -contains $tag) {
            $releasePipelinesUrl = $workItem.releasePipelinesField
        }
        else {
            $releasePipelinesUrl = "$($workItem.releasePipelinesField),$tag"
        }
    }

    if ($null -eq $workItem.assignedTo -or $workItem.assignedTo.uniqueName -notlike '*@umea.se') {
        $assignedTo = $releaseIdentity
    }
    else {
        $assignedTo = "$($workItem.assignedTo.displayName) <$($workItem.assignedTo.uniqueName)>"
    }

    $fieldsToUpdate = @(
        @{
            op    = "replace"
            path  = "/fields/Custom.Released"
            value = 1
        }
        @{
            op    = "add"
            path  = "/fields/Custom.ReleasedBy"
            value = "$releaseIdentity"
        }
        @{
            op    = "add"
            path  = "/fields/Custom.ReleaseStarted"
            value = "$startedTime"
        }
        @{
            op    = "add"
            path  = "/fields/Custom.ReleaseFinished"
            value = "$finishedTime"
        }
        @{
            op    = "add"
            path  = "/fields/Custom.ReleasePipelines"
            value = "$releasePipelinesUrl"
        }
        @{
            op    = "add"
            path  = "/fields/System.AssignedTo"
            value = "$assignedTo"
        }
    )

    $body = $fieldsToUpdate | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Headers $patchAuthenticationHeader -Method PATCH -Uri $ticketUrl -Body $body > $null

    Write-Host "Updated ticket fields for ticket #$($workItem.id)"
    $fieldsToUpdate | ForEach-Object {
        Write-Host "    - $($_.path): $($_.value)"
    }
}

Write-Host "All successful release tickets finalized successfully."
