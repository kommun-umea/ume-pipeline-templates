Import-Module ([System.IO.Path]::GetFullPath("$PSScriptRoot/../../../utilities/throw-error-helper.psm1"))
$ErrorActionPreference = 'Stop'

$accessToken = $env:SYSTEM_ACCESSTOKEN
$repositoryName = $env:BUILD_REPOSITORY_NAME
$commitId = $env:BUILD_SOURCEVERSION
$devopsBaseUrl = $env:SYSTEM_COLLECTIONURI
$projectName = $env:SYSTEM_TEAMPROJECT

if ([string]::IsNullOrWhiteSpace($accessToken)) {
    ThrowError("Access Token is not provided.")
}
if ([string]::IsNullOrWhiteSpace($repositoryName)) {
    ThrowError("Repository Name is not provided.")
}
if ([string]::IsNullOrWhiteSpace($commitId)) {
    ThrowError("Commit ID is not provided.")
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

$pullRequestsUrl = "$baseUrl/git/repositories/$repositoryName/pullrequestquery?$apiVersion"
$body = @{
    queries = @(
        @{
            items = @($commitId)
            type  = "lastMergeCommit"
        }
    )
} | ConvertTo-Json -Depth 10
$pullRequests = Invoke-RestMethod -Method POST -Uri $pullRequestsUrl -Headers $authenticationHeader -Body $body -ContentType "application/json"
$pullRequestId = $pullRequests.results.$commitId.pullRequestId

if ($null -eq $pullRequestId) {
    ThrowError("No pull request found for commit ID $commitId.")
}

Write-Host "##vso[task.setvariable variable=PULLREQUEST_ID;isOutput=true]$pullRequestId"
Write-Host "Set output variable: PULLREQUEST_ID = '$pullRequestId'"