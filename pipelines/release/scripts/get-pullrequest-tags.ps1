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

if ($null -eq $pullRequestId -or $pullRequestId -eq '') {
    ThrowError("Pull request ID is not provided.")
}

$pullRequestTagsUrl = "$baseUrl/git/repositories/$repositoryName/pullrequests/$($pullRequestId)/labels?$apiVersion"
$pullRequestTagsResponse = Invoke-RestMethod -Uri $pullRequestTagsUrl -Headers $authenticationHeader -Method GET

if ($pullRequestTagsResponse.count -lt 1) {
    ThrowError("No tags found on pull request $pullRequestId.")
}

$pullRequestTags = $pullRequestTagsResponse.value | ForEach-Object { $_.name }
$pullRequestTagsString = $pullRequestTags -join ';'

Write-Host "##vso[task.setvariable variable=PULLREQUEST_TAGS;isOutput=true]$pullRequestTagsString"
Write-Host "Set output variable: PULLREQUEST_TAGS = '$pullRequestTagsString'"