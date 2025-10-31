function ThrowError ($message) {
    # Write to DevOps log
    Write-Host "##vso[task.logissue type=error;]$message"

    # Capture call stack information
    $callSite = (Get-PSCallStack)[1]  # index 1 = caller of this function
    $callerInfo = "Thrown at $($callSite.ScriptName):$($callSite.ScriptLineNumber)"

    throw "$message`n$callerInfo"
}