Import-Module ([System.IO.Path]::GetFullPath("$PSScriptRoot/../../../utilities/throw-error-helper.psm1"))
$ErrorActionPreference = 'Stop'

$accessToken = $env:SYSTEM_ACCESSTOKEN
$pipelineBuildId = $env:PIPELINE_BUILD_ID
$devopsBaseUrl = $env:SYSTEM_COLLECTIONURI
$projectName = $env:SYSTEM_TEAMPROJECT

if ([string]::IsNullOrWhiteSpace($accessToken)) {
    ThrowError("Personal Access Token is not provided.")
}
if ([string]::IsNullOrWhiteSpace($pipelineBuildId)) {
    ThrowError("Pipeline Build ID is not provided.")
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

Write-Host "Cancelling pipeline run..."
$cancelPipelineBuildUrl = "$baseUrl/build/builds/$($pipelineBuildId)?$apiVersion"
$cancelPipelineBuildBody = @{
    status = 'cancelling'
} | ConvertTo-Json
Invoke-RestMethod -Method Patch -Uri $cancelPipelineBuildUrl -Headers $authenticationHeader -Body $cancelPipelineBuildBody -ContentType 'application/json' > $null
