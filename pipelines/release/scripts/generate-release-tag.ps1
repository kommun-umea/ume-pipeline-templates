Import-Module ([System.IO.Path]::GetFullPath("$PSScriptRoot/../../../utilities/throw-error-helper.psm1"))
$ErrorActionPreference = 'Stop'

$accessToken = $env:SYSTEM_ACCESSTOKEN
$ticketIdsString = $env:TICKET_IDS
$buildId = $env:BUILD_BUILDID
$devopsBaseUrl = $env:SYSTEM_COLLECTIONURI
$projectName = $env:SYSTEM_TEAMPROJECT

if ([string]::IsNullOrWhiteSpace($accessToken)) {
    ThrowError("Access Token is not provided.")
}
if ([string]::IsNullOrWhiteSpace($ticketIdsString)) {
    ThrowError("Ticket IDs are not provided.")
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
$baseUrl = "$devopsBaseUrl$projectName/_apis"
$apiVersion = "api-version=7.1"
$workItemTypeOrderMap = @{
    "Epic"        = 1
    "Feature"     = 2
    "Bug"         = 3
    "Improvement" = 3
    "User Story"  = 3
    "Task"        = 4
}
$ticketIds = [int[]]($ticketIdsString -split ';')

$pipelineRunUrl = "$baseUrl/build/builds/$($buildId)?$apiVersion"
$pipelineRun = Invoke-RestMethod -Uri $pipelineRunUrl -Headers $authenticationHeader -Method Get
$pipelineRunStartTimeUtc = [DateTime]::Parse($pipelineRun.startTime)
$localTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById("Europe/Stockholm")
$pipelineRunStartTime = [System.TimeZoneInfo]::ConvertTime($pipelineRunStartTimeUtc, $localTimeZone)

$workItemsBatchUri = "$baseUrl/wit/workitemsbatch?$apiVersion"
$body = @{
    ids    = $ticketIds
    fields = @("System.WorkItemType")
} | ConvertTo-Json -Depth 10
$workItemsBatchResponse = Invoke-RestMethod `
    -Method POST `
    -Uri $workItemsBatchUri `
    -Headers $authenticationHeader `
    -ContentType "application/json" `
    -Body $body

$workItems = $workItemsBatchResponse.value | Select-Object `
    @{ Name = "id"; Expression = { $_.id } },
    @{ Name = "type"; Expression = { $_.fields."System.WorkItemType" } }
$sortedWorkItems = $workItems | Sort-Object -Property `
    @{ Expression = {
        $rank = $workItemTypeOrderMap[$_.type]
        if ($null -eq $rank) { [int]::MaxValue } else { $rank }
     } },
    @{ Expression = { $_.id } }

Write-Host "Sorted work items:"
$sortedWorkItems | ForEach-Object {
    Write-Host " - $($_.id) $($_.type)"
}

$releaseTagDate = $pipelineRunStartTime.ToString("yyMMdd'T'HHmm")
$releaseTagTicketId = $sortedWorkItems[0].id
$releaseTag = "release/v$releaseTagDate-$releaseTagTicketId"

if ([string]::IsNullOrWhiteSpace($releaseTagDate)) {
    ThrowError("Release tag date is empty.")
}
if ([string]::IsNullOrWhiteSpace($releaseTagTicketId)) {
    ThrowError("Release tag ticket ID is empty.")
}

Write-Host "##vso[task.setvariable variable=RELEASE_TAG;isOutput=true]$releaseTag"
Write-Host "Set output variable: RELEASE_TAG = '$releaseTag'"