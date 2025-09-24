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

# Main
git config user.name $userName
if ($LASTEXITCODE -ne 0) {
    ThrowError("Failed to set git user name.")
}

git config user.email $userEmail
if ($LASTEXITCODE -ne 0) {
    ThrowError("Failed to set git user email.")
}

git tag -a $tag -m $tagMessage $commitId
if ($LASTEXITCODE -ne 0) {
    ThrowError("Failed to create git tag.")
}

git push origin $tag
if ($LASTEXITCODE -ne 0) {
    ThrowError("Failed to push git tag.")
}

Write-Host "Tagged commit '$commitId' with tag '$tag' and message '$tagMessage'."