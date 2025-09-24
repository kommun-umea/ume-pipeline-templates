Import-Module ([System.IO.Path]::GetFullPath("$PSScriptRoot/../../../utilities/throw-error-helper.psm1"))
$ErrorActionPreference = 'Stop'

$accessToken = $env:SYSTEM_ACCESSTOKEN
$repositoryName = $env:BUILD_REPOSITORY_NAME
$pullRequestId = $env:PULLREQUEST_ID
$devopsBaseUrl = $env:SYSTEM_COLLECTIONURI
$projectName = $env:SYSTEM_TEAMPROJECT

if ([string]::IsNullOrWhiteSpace($accessToken)) {
    ThrowError("Access Token is not provided.")
}
if ([string]::IsNullOrWhiteSpace($repositoryName)) {
    ThrowError("Repository Name is not provided.")
}
if ([string]::IsNullOrWhiteSpace($pullRequestId)) {
    ThrowError("Pull Request ID is not provided.")
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
$baseUrl = "$devopsBaseUrl/$projectName/_apis"
$apiVersion = "api-version=7.1"

$ticketsUrl = "$baseUrl/git/repositories/$repositoryName/pullRequests/$pullRequestId/workitems?$apiVersion"
$ticketsResponse = Invoke-RestMethod -Headers $authenticationHeader -Method GET -Uri $ticketsUrl
$ticketIds = $ticketsResponse.value.id
$ticketIdsString = $ticketIds -join ';'

Write-Host "##vso[task.setvariable variable=PULLREQUEST_TICKET_IDS;isOutput=true]$ticketIdsString"
Write-Host "Set output variable: PULLREQUEST_TICKET_IDS = '$ticketIdsString'"