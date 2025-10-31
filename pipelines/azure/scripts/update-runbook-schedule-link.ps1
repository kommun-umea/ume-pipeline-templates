param(
    [string]$automationAccountName,
    [string]$resourceGroupName,
    [string]$runbookResourceName,
    [string]$scheduleName,
    [string]$shouldLinkSchedule
)

$azAutomationModule = Get-Module Az.Automation
if (-Not $azAutomationModule) {
    Write-Host "[Ume]: Installing and importing Az.Automation module"
    Install-Module Az.Automation -Scope CurrentUser -Force
    Import-Module Az.Automation
}

Write-Host "[Ume]: Retreiving currently linked schedules"
$currentlyLinkedSchedules = Get-AzAutomationScheduledRunbook `
    -AutomationAccountName $automationAccountName `
    -ResourceGroupName $resourceGroupName `
    -RunbookName $runbookResourceName `

Write-Host "[Ume]: Found $($currentlyLinkedSchedules.Count) linked schedule(s)"

foreach ($schedule in $currentlyLinkedSchedules) {
    Write-Host "[Ume]: Unlinking schedule from runbook"
    UnRegister-AzAutomationScheduledRunbook `
        -AutomationAccountName $automationAccountName `
        -ResourceGroupName $resourceGroupName `
        -Name $runbookResourceName `
        -ScheduleName $schedule.ScheduleName `
        -Force `
    | Out-Null
}

if ($shouldLinkSchedule -eq 'true') {
    Write-Host "[Ume]: Linking runbook to schedule"
    Register-AzAutomationScheduledRunbook `
        -AutomationAccountName $automationAccountName `
        -ResourceGroupName $resourceGroupName `
        -Name $runbookResourceName `
        -ScheduleName $scheduleName `
    | Out-Null
}
else {
    Write-Host "[Ume]: Script was set to not link any schedule"
}

Write-Host "[Ume]: Finished!"
