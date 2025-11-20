Import-Module ([System.IO.Path]::GetFullPath("$PSScriptRoot/../../../utilities/throw-error-helper.psm1"))
$ErrorActionPreference = 'Stop'

$accessToken = $env:ACCESS_TOKEN
$organization = $env:ORGANIZATION
$repository = $env:REPOSITORY
$branch = $env:BRANCH
$userName = $env:USER_NAME
$userEmail = $env:USER_EMAIL

if ([string]::IsNullOrWhiteSpace($accessToken)) {
    ThrowError("Access Token is not provided.")
}
if ([string]::IsNullOrWhiteSpace($organization)) {
    ThrowError("Organization is not provided.")
}
if ([string]::IsNullOrWhiteSpace($repository)) {
    ThrowError("Repository is not provided.")
}
if ([string]::IsNullOrWhiteSpace($branch)) {
    ThrowError("Branch is not provided.")
}
if ([string]::IsNullOrWhiteSpace($userName)) {
    ThrowError("User Name is not provided.")
}
if ([string]::IsNullOrWhiteSpace($userEmail)) {
    ThrowError("User Email is not provided.")
}

$repositoryUrl = "github.com/$organization/$repository.git"
$remoteUrl = "https://$accessToken@$repositoryUrl"

Write-Host "Configuring git identity..."
git config user.name "$userName"
git config user.email "$userEmail"

Write-Host "Fetching latest '$branch' from origin..."
git fetch origin $branch

Write-Host "Checking out '$branch'..."
git checkout $branch

Write-Host "Current HEAD:"
git log -1 --oneline

Write-Host "Existing remotes:"
git remote -v

$remotes = git remote
if ($remotes -match '^github$') {
    Write-Host "Resetting 'github' remote..."
    git remote remove github
}

Write-Host "Adding GitHub remote..."
git remote add github $remoteUrl

Write-Host "Pushing branch '$branch' to GitHub..."
git push github "refs/heads/$($branch):refs/heads/$branch" --force

Write-Host "Finished!"