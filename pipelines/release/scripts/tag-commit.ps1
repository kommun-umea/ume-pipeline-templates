Import-Module ([System.IO.Path]::GetFullPath("$PSScriptRoot/../../../utilities/throw-error-helper.psm1"))
$ErrorActionPreference = 'Stop'

$accessToken = $env:SYSTEM_ACCESSTOKEN
$userName = $env:USER_NAME
$userEmail = $env:USER_EMAIL
$commitId = $env:COMMIT_ID
$tag = $env:TAG
$tagMessage = $env:TAG_MESSAGE

if ([string]::IsNullOrWhiteSpace($accessToken)) {
    ThrowError("Access Token is not provided.")
}
if ([string]::IsNullOrWhiteSpace($userName)) {
    ThrowError("User Name is not provided.")
}
if ([string]::IsNullOrWhiteSpace($userEmail)) {
    ThrowError("User Email is not provided.")
}
if ([string]::IsNullOrWhiteSpace($commitId)) {
    ThrowError("Commit ID is not provided.")
}
if ([string]::IsNullOrWhiteSpace($tag)) {
    ThrowError("Tag is not provided.")
}
if ([string]::IsNullOrWhiteSpace($tagMessage)) {
    ThrowError("Tag message is not provided.")
}

function Get-RemoteTagCommit {
    param([string]$tagName)

    $output = git ls-remote origin "refs/tags/$tagName" "refs/tags/$tagName^{}" 2>$null
    if ($LASTEXITCODE -ne 0) {
        ThrowError("Failed to query remote for tag '$tagName'.")
    }
    if ([string]::IsNullOrWhiteSpace($output)) {
        return $null
    }

    $lines = $output -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $derefLine = $lines | Where-Object { $_ -match '\^\{\}$' } | Select-Object -First 1
    if ($derefLine) {
        return ($derefLine -split "\s+")[0].Trim()
    }
    return ($lines[0] -split "\s+")[0].Trim()
}

# Main

$existingCommit = Get-RemoteTagCommit $tag
if ($null -ne $existingCommit) {
    if ($existingCommit -eq $commitId) {
        Write-Host "Tag '$tag' already exists on remote at commit '$commitId'. Skipping tag creation."
        exit 0
    }
    ThrowError("Tag '$tag' already exists on remote at commit '$existingCommit' but expected '$commitId'.")
}

git config user.name $userName
if ($LASTEXITCODE -ne 0) {
    ThrowError("Failed to set git user name.")
}

git config user.email $userEmail
if ($LASTEXITCODE -ne 0) {
    ThrowError("Failed to set git user email.")
}

git tag -af $tag -m $tagMessage $commitId
if ($LASTEXITCODE -ne 0) {
    ThrowError("Failed to create git tag.")
}

git push origin $tag
if ($LASTEXITCODE -ne 0) {
    Write-Host "Push of tag '$tag' failed. Re-checking remote for a concurrent tag creation."
    $existingCommit = Get-RemoteTagCommit $tag
    if ($null -eq $existingCommit) {
        ThrowError("Failed to push git tag '$tag' and no matching tag found on remote.")
    }
    if ($existingCommit -ne $commitId) {
        ThrowError("Tag '$tag' now exists on remote at commit '$existingCommit' but expected '$commitId'.")
    }
    Write-Host "Tag '$tag' was concurrently created on remote at commit '$commitId'. Treating as success."
    exit 0
}

Write-Host "Tagged commit '$commitId' with tag '$tag' and message '$tagMessage'."