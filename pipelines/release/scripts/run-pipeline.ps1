Import-Module ([System.IO.Path]::GetFullPath("$PSScriptRoot/../../../utilities/throw-error-helper.psm1"))
$ErrorActionPreference = 'Stop'

$accessToken = $env:SYSTEM_ACCESSTOKEN
$environment = $env:ENVIRONMENT
$pipelineFilePath = $env:PIPELINE_FILE_PATH
$agentTempDirectory = $env:AGENT_TEMPDIRECTORY
$repositoryId = $env:BUILD_REPOSITORY_ID
$repositoryType = $env:BUILD_REPOSITORY_PROVIDER
$branch = $env:BUILD_SOURCEBRANCH
$commitId = $env:BUILD_SOURCEVERSION
$tag = $env:BUILD_SOURCETAG
$devopsBaseUrl = $env:SYSTEM_COLLECTIONURI
$projectName = $env:SYSTEM_TEAMPROJECT

if ([string]::IsNullOrWhiteSpace($accessToken)) {
    ThrowError("Personal Access Token is not provided.")
}
if ([string]::IsNullOrWhiteSpace($environment)) {
    ThrowError("Environment is not provided.")
}
if ([string]::IsNullOrWhiteSpace($pipelineFilePath)) {
    ThrowError("Pipeline File Path is not provided.")
}
if ([string]::IsNullOrWhiteSpace($agentTempDirectory)) {
    ThrowError("Agent Temp Directory is not provided.")
}
if ([string]::IsNullOrWhiteSpace($repositoryId)) {
    ThrowError("Repository ID is not provided.")
}
if ([string]::IsNullOrWhiteSpace($repositoryType)) {
    ThrowError("Repository Type is not provided.")
}
if (([string]::IsNullOrWhiteSpace($branch) -or [string]::IsNullOrWhiteSpace($commitId)) -and [string]::IsNullOrWhiteSpace($tag)) {
    ThrowError("Source is not provided.")
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


Write-Host "Finding pipeline with YAML file path: $pipelineFilePath"
$getPipelinesUrl = "$baseUrl/build/definitions?repositoryId=$repositoryId&repositoryType=$repositoryType&includeAllProperties=true&$apiVersion"
$pipelinesResponse = Invoke-RestMethod -Uri $getPipelinesUrl -Headers $authenticationHeader -Method Get
$pipeline = $pipelinesResponse.value | Where-Object { $_.process.yamlFilename -eq $pipelineFilePath }

Write-Host "Running pipeline '$($pipeline.name)' on commit $commitId with environment $environment"
$runPipelineUrl = "$baseUrl/pipelines/$($pipeline.id)/runs?$apiVersion"
$body = @{
    resources          = @{
        repositories = @{
            self = @{
                refName = $branch
                version = $commitId
            }
        }
    }
    templateParameters = @{ environment = $environment }
}
$isSourceTag = -not [string]::IsNullOrWhiteSpace($tag)
if ($isSourceTag) {
    $body.resources.repositories.self = @{
        refName = "refs/tags/$tag"
    }
}
$bodyJson = $body | ConvertTo-Json -Depth 10
$pipelineRun = Invoke-RestMethod -Method Post -Uri $runPipelineUrl -Headers $authenticationHeader -Body $bodyJson -ContentType 'application/json'

$buildId = $pipelineRun.id
Write-Host "##vso[task.setvariable variable=PIPELINE_BUILD_ID;isOutput=true]$buildId"
Write-Host "Set output variable: PIPELINE_BUILD_ID = '$buildId'"

$pipelineRunUrl = "$baseUrl/pipelines/$($pipeline.id)/runs/$($buildId)?$apiVersion"
$pendingApprovalsUrl = "$baseUrl/pipelines/approvals?state=pending&$apiVersion"
$isApprovalNotified = $false
do {
    Write-Host "Pipeline is not finished yet. Waiting 10 seconds..."
    Start-Sleep -Seconds 10

    if (-not $isApprovalNotified) {
        $pendingApprovals = Invoke-RestMethod -Uri $pendingApprovalsUrl -Headers $authenticationHeader
        $pipelineRunPendingApproval = $pendingApprovals.value | Where-Object { $_.pipeline.owner.id -eq $buildId }

        if ($pipelineRunPendingApproval) {
            $message = "Pipeline is waiting for approval. Approve it here: $($pipelineRun._links.web.href)"
            Write-Host "##vso[task.logissue type=warning;]$message" # Information log doesn't exist in DevOps
            Write-Host "Pending approval notification sent."

            $isApprovalNotified = $true
        }
    }

    $pipelineRun = Invoke-RestMethod -Uri $pipelineRunUrl -Headers $authenticationHeader
} while ($pipelineRun.state -ne 'completed')

$result = $pipelineRun.result
$url = $pipelineRun._links.web.href
$finishedDate = $pipelineRun.finishedDate

Write-Host "##vso[task.setvariable variable=PIPELINE_BUILD_RESULT;isOutput=true]$result"
Write-Host "Set output variable: PIPELINE_BUILD_RESULT = '$result'"

Write-Host "##vso[task.setvariable variable=PIPELINE_BUILD_URL;isOutput=true]$url"
Write-Host "Set output variable: PIPELINE_BUILD_URL = '$url'"

Write-Host "##vso[task.setvariable variable=PIPELINE_BUILD_FINISHED_DATE;isOutput=true]$finishedDate"
Write-Host "Set output variable: PIPELINE_BUILD_FINISHED_DATE = '$finishedDate'"

if ($pipelineRun.result -ne 'succeeded') {
    ThrowError("Pipeline run failed! See details at: $url")
}