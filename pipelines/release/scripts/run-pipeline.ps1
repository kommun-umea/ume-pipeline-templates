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
$user = $env:BUILD_REQUESTEDFOR
$releaseTitle = $env:BUILD_SOURCEVERSIONMESSAGE
$repositoryName = $env:PIPELINE_REPOSITORY_NAME
$templateParametersJson = $env:TEMPLATE_PARAMETERS
$logicAppPendingReleaseNotificationUrl = $env:LOGIC_APP_PENDING_RELEASE_NOTIFICATION_URL # ume-logic-releaseapprovalnotification from library

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
if ([string]::IsNullOrWhiteSpace($user)) {
    ThrowError("User is not provided.")
}
if ([string]::IsNullOrWhiteSpace($releaseTitle)) {
    ThrowError("Release Title is not provided.")
}
if ([string]::IsNullOrWhiteSpace($repositoryName)) {
    ThrowError("Repository Name is not provided.")
}

$templateParameters = @{}
if (-not [string]::IsNullOrWhiteSpace($templateParametersJson)) {
    $templateParameters = $templateParametersJson | ConvertFrom-Json -AsHashtable
}

$authenticationHeader = @{
    Authorization = "Bearer $accessToken"
}
$baseUrl = "$devopsBaseUrl$projectName/_apis"
$apiVersion = "api-version=7.1"

function Get-ApprovalNotificationKey {
    param (
        [Parameter(Mandatory = $true)]
        $Approval
    )

    if ($null -ne $Approval.id) {
        return [string]$Approval.id
    }

    if ($null -ne $Approval.url) {
        return [string]$Approval.url
    }

    return ($Approval | ConvertTo-Json -Compress -Depth 10)
}

function Get-TimelineRecordStageId {
    param (
        [Parameter(Mandatory = $true)]
        $Record,

        [Parameter(Mandatory = $true)]
        [hashtable]$RecordsById
    )

    $currentRecord = $Record
    while ($null -ne $currentRecord) {
        if ($currentRecord.type -eq 'Stage') {
            return [string]$currentRecord.id
        }

        if ($null -eq $currentRecord.parentId) {
            return $null
        }

        $parentId = [string]$currentRecord.parentId
        if (-not $RecordsById.ContainsKey($parentId)) {
            return $null
        }

        $currentRecord = $RecordsById[$parentId]
    }

    return $null
}

function Get-ApprovalBlockedStageIds {
    param (
        [Parameter(Mandatory = $true)]
        $TimelineRecords
    )

    $recordsById = @{}
    foreach ($record in $TimelineRecords) {
        if ($null -ne $record.id) {
            $recordsById[[string]$record.id] = $record
        }
    }

    $approvalBlockedStageIds = @{}
    $approvalTimelineRecords = @($TimelineRecords | Where-Object {
            $_.state -ne 'completed' -and
            ($_.type -like '*Approval*' -or $_.type -like '*Checkpoint*')
        })

    foreach ($approvalRecord in $approvalTimelineRecords) {
        $stageId = Get-TimelineRecordStageId -Record $approvalRecord -RecordsById $recordsById
        if ($null -ne $stageId) {
            $approvalBlockedStageIds[$stageId] = $true
        }
    }

    return $approvalBlockedStageIds
}


Write-Host "Finding pipeline with YAML file path: $pipelineFilePath"
$getPipelinesUrl = "$baseUrl/build/definitions?repositoryId=$repositoryId&repositoryType=$repositoryType&includeAllProperties=true&$apiVersion"
$pipelinesResponse = Invoke-RestMethod -Uri $getPipelinesUrl -Headers $authenticationHeader -Method Get
$pipeline = $pipelinesResponse.value | Where-Object { $_.process.yamlFilename -eq $pipelineFilePath }

Write-Host "Running pipeline '$($pipeline.name)' on commit $commitId with parameters: $templateParametersJson"
$runPipelineUrl = "$baseUrl/pipelines/$($pipeline.id)/runs?$apiVersion"
$body = @{
    resources = @{
        repositories = @{
            self = @{
                refName = $branch
                version = $commitId
            }
        }
    }
}
if ($templateParameters.Count -gt 0) {
    $body.templateParameters = $templateParameters
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
$buildTimelineUrl = "$baseUrl/build/builds/$buildId/Timeline?$apiVersion"
$notifiedApprovalIds = @{}
do {
    Write-Host "Pipeline is not finished yet. Waiting 10 seconds..."
    Start-Sleep -Seconds 10

    $pendingApprovals = Invoke-RestMethod -Uri $pendingApprovalsUrl -Headers $authenticationHeader
    $pipelineRunPendingApprovals = @($pendingApprovals.value | Where-Object { $_.pipeline.owner.id -eq $buildId })
    $newPendingApprovals = @($pipelineRunPendingApprovals | Where-Object {
            $approvalKey = Get-ApprovalNotificationKey -Approval $_
            -not $notifiedApprovalIds.ContainsKey($approvalKey)
        })

    if ($newPendingApprovals.Count -gt 0) {
        $timeline = Invoke-RestMethod -Uri $buildTimelineUrl -Headers $authenticationHeader
        $timelineRecords = @($timeline.records)
        $stages = @($timelineRecords | Where-Object { $_.type -eq 'Stage' })
        $approvalBlockedStageIds = Get-ApprovalBlockedStageIds -TimelineRecords $timelineRecords
        $activeWorkStages = @($stages | Where-Object {
                $stageId = [string]$_.id
                $_.state -eq 'inProgress' -and
                -not $approvalBlockedStageIds.ContainsKey($stageId)
            })

        if ($activeWorkStages.Count -gt 0) {
            $stageNames = ($activeWorkStages | ForEach-Object { $_.name }) -join ', '
            Write-Host "New pending approvals found ($($newPendingApprovals.Count)), but still waiting for: $stageNames. Deferring notification..."
        }
        else {
            $message = "Pipeline is waiting for approval ($($newPendingApprovals.Count) new, $($pipelineRunPendingApprovals.Count) pending total). Approve it here: $($pipelineRun._links.web.href)"
            Write-Host "##vso[task.logissue type=warning;]$message" # Information log doesn't exist in DevOps

            if (($environment -eq 'prod') -and ($null -ne $logicAppPendingReleaseNotificationUrl)) {
                $payloadObject = @{
                    approvalUrl    = $pipelineRun._links.web.href
                    user           = $user
                    repositoryName = $repositoryName
                    releaseTitle   = $releaseTitle
                    releaseTag     = $tag
                }
                $jsonBody = $payloadObject | ConvertTo-Json -Depth 10
                $response = Invoke-RestMethod -Method Post -Uri $logicAppPendingReleaseNotificationUrl -ContentType "application/json" -Body $jsonBody
            }

            foreach ($approval in $newPendingApprovals) {
                $approvalKey = Get-ApprovalNotificationKey -Approval $approval
                $notifiedApprovalIds[$approvalKey] = $true
            }

            Write-Host "Pending approval notification sent."
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
