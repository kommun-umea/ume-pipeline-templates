Import-Module ([System.IO.Path]::GetFullPath("$PSScriptRoot/../../../utilities/throw-error-helper.psm1"))
$ErrorActionPreference = 'Stop'

$accessToken = $env:SYSTEM_ACCESSTOKEN
$failedTag = $env:FAILED_TAG
$ticketIdsString = $env:TICKET_IDS
$devopsBaseUrl = $env:SYSTEM_COLLECTIONURI
$projectName = $env:SYSTEM_TEAMPROJECT

if ([string]::IsNullOrWhiteSpace($accessToken)) {
    ThrowError("Access Token is not provided.")
}
if ([string]::IsNullOrWhiteSpace($failedTag)) {
    ThrowError("Failed Tag is not provided.")
}
if ([string]::IsNullOrWhiteSpace($ticketIdsString)) {
    Write-Host "No tickets to initialize."
    exit 0
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
$baseUrl = "$devopsBaseUrl$projectName/_apis"
$apiVersion = "api-version=7.1"

$fieldsToUpdate = @(
    @{
        op    = "add"
        path  = "/fields/System.Tags"
        value = "$failedTag"
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

Write-Host "All failed release tickets finalized successfully."
