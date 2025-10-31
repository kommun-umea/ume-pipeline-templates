param(
    [string]$automationAccountName,
    [string]$resourceGroupName,
    [string]$runbookPath,
    [string]$runbookName,
    [string]$environment
)

$runbookResourceName = "$runbookName-$environment"

Write-Host "[Ume]: Reading runbook content from [$runbookPath]"
$runbookContent = Get-Content -Path $runbookPath -Raw
Write-Host "[Ume]: Adjusting environment to [$environment] in the runbook content"
$runbookContent = $runbookContent -replace '{environment}', $environment

Write-Host "[Ume]: Creating temporary runbook file"
$tempRunbookPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$runbookName.ps1")
Set-Content -Path $tempRunbookPath -Value $runbookContent

Write-Host "[Ume]: Updating runbook"
az automation runbook replace-content `
    --automation-account-name $automationAccountName `
    --name $runbookResourceName `
    --resource-group $resourceGroupName `
    --content @$tempRunbookPath

Write-Host "[Ume]: Removing temporary runbook file"
Remove-Item -Path $tempRunbookPath -Force

Write-Host "[Ume]: Publishing runbook"
az automation runbook publish `
    --automation-account-name $automationAccountName `
    --name $runbookResourceName `
    --resource-group $resourceGroupName

Write-Host "[Ume]: Finished!"
