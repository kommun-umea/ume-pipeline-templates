Import-Module ([System.IO.Path]::GetFullPath("$PSScriptRoot/../../../utilities/throw-error-helper.psm1"))
$ErrorActionPreference = 'Stop'

$accessToken = $env:SYSTEM_ACCESSTOKEN
$repositoryName = $env:BUILD_REPOSITORY_NAME
$releaseTags = $env:RELEASE_TAGS
$devopsBaseUrl = $env:SYSTEM_COLLECTIONURI
$projectName = $env:SYSTEM_TEAMPROJECT

if ([string]::IsNullOrWhiteSpace($accessToken)) {
    ThrowError("Access Token is not provided.")
}
if ([string]::IsNullOrWhiteSpace($repositoryName)) {
    ThrowError("Repository Name is not provided.")
}
if ([string]::IsNullOrWhiteSpace($releaseTags)) {
    ThrowError("Release Tags are not provided.")
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

Write-Host "releaseTags = '$releaseTags'"

$releaseTags = $releaseTags -split ';' | Where-Object { $_ -match '^release\/v\d{6}' }

if ($releaseTags.Count -eq 0) {
    ThrowError("No valid release tag found. Expected format: release/vYYMMDD")
}
if ($releaseTags.Count -gt 1) {
    ThrowError("Multiple release tags found. Only one release tag is allowed.")
}

$releaseTag = $releaseTags | Select-Object -First 1

$repositoryTagUrl = "$baseUrl/git/repositories/$repositoryName/refs?filter=tags/$($releaseTag)&$apiVersion"
$repositoryTagResponse = Invoke-RestMethod -Uri $repositoryTagUrl -Headers $authenticationHeader -Method GET

if ($repositoryTagResponse.count -gt 0) {
    ThrowError("Tag $releaseTag already exists in the repository.")
}

Write-Host "##vso[task.setvariable variable=RELEASE_TAG;isOutput=true]$releaseTag"
Write-Host "Set output variable: RELEASE_TAG = '$releaseTag'"