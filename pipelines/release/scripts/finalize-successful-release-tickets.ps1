Import-Module ([System.IO.Path]::GetFullPath("$PSScriptRoot/../../../utilities/throw-error-helper.psm1"))
$ErrorActionPreference = 'Stop'

$accessToken = $env:SYSTEM_ACCESSTOKEN
$ticketIdsString = $env:TICKET_IDS
$tag = $env:TAG
$userName = $env:BUILD_REQUESTEDFOR
$userEmail = $env:BUILD_REQUESTEDFOREMAIL
$releaseBuildId = $env:BUILD_BUILDID
$deploymentBuildId = $env:DEPLOYMENT_BUILDID
$deploymentFinishedDate = $env:DEPLOYMENT_FINISHED_DATE
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
if ([string]::IsNullOrWhiteSpace($releaseBuildId)) {
    ThrowError("Release Build ID is not provided.")
}
if ([string]::IsNullOrWhiteSpace($deploymentBuildId)) {
    ThrowError("Deployment Build ID is not provided.")
}
if ([string]::IsNullOrWhiteSpace($deploymentFinishedDate)) {
    ThrowError("Deployment Finished Date is not provided.")
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
$patchAuthenticationHeader = ($authenticationHeader + @{ "Content-Type" = "application/json-patch+json" })
$baseUrl = "$devopsBaseUrl/$projectName/_apis"
$pipelineBuildBaseUrl = "$devopsBaseUrl/$projectName/_build/results?buildid="
$apiVersion = "api-version=7.1"

$fieldsToUpdate = @(
    @{
        op    = "replace"
        path  = "/fields/Custom.Released"
        value = 1
    }
    @{
        op    = "add"
        path  = "/fields/Custom.ReleasedBy"
        value = "$userName <$userEmail>"
    }
    @{
        op    = "add"
        path  = "/fields/Custom.ReleaseDate"
        value = "$deploymentFinishedDate"
    }
    @{
        op    = "add"
        path  = "/fields/Custom.ReleasePipeline"
        value = "$pipelineBuildBaseUrl$releaseBuildId"
    }
    @{
        op    = "add"
        path  = "/fields/Custom.DeploymentPipeline"
        value = "$pipelineBuildBaseUrl$deploymentBuildId"
    }
)

$ticketIds = $ticketIdsString -split ';'
foreach ($ticketId in $ticketIds) {
    $ticketUrl = "$baseUrl/wit/workitems/$($ticketId)?$apiVersion"

    $body = , $fieldsToUpdate | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Headers $patchAuthenticationHeader -Method PATCH -Uri $ticketUrl -Body $body > $null

    Write-Host "Updated ticket fields for ticket #$ticketId"
    $fieldsToUpdate | ForEach-Object {
        Write-Host "    - $($_.path): $($_.value)"
    }
}

Write-Host "All successful release tickets finalized successfully."
