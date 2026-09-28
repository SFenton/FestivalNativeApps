<#
.SYNOPSIS
    Runs a prepared script in the signed-in desktop session (called by Invoke-InDesktopSession under the desktop lock).
.PARAMETER Body PowerShell script file to run (Windows PowerShell 5.1).
.PARAMETER Done Marker file the body writes when finished.
.PARAMETER TimeoutSeconds How long to wait for the marker.
.PARAMETER NoWait Start and return without waiting.
#>
param([Parameter(Mandatory)][string]$Body, [Parameter(Mandatory)][string]$Done, [int]$TimeoutSeconds = 120, [switch]$NoWait)
$ErrorActionPreference = 'Stop'
if ((Get-Process -Id $PID).SessionId -ne 0) {
    if ($NoWait) { Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Body -WindowStyle Hidden; exit 0 }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Body
    exit 0
}
$task = 'FST-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$action = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Body`""
schtasks.exe /Create /TN $task /TR $action /SC ONCE /ST 23:59 /IT /F | Out-Null
schtasks.exe /Run /TN $task | Out-Null
try {
    if ($NoWait) { Start-Sleep -Seconds 2; exit 0 }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while (-not (Test-Path $Done) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 250 }
    if (-not (Test-Path $Done)) { Write-Error "Desktop-session script timed out after $TimeoutSeconds s ($Body)."; exit 1 }
} finally {
    schtasks.exe /Delete /TN $task /F | Out-Null
}
