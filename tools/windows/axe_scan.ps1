<#
.SYNOPSIS
    Runs an Axe.Windows rule scan of a running app process in the signed-in desktop session (under the desktop lock).
.PARAMETER ProcessId App process to scan (e.g. the pid printed by uiwin.py launch).
.PARAMETER OutputDirectory Where AxeWindowsCLI writes its .a11ytest results.
.PARAMETER ScanId Name for the scan's result file.
.EXAMPLE
    pwsh tools/windows/axe_scan.ps1 -ProcessId 1234 -OutputDirectory $env:TEMP\axe -ScanId search-page
.NOTES
    Prints the CLI summary; exit code 0 = no errors, otherwise the CLI's code (see Axe.Windows docs).
#>
param([Parameter(Mandatory)][int]$ProcessId, [Parameter(Mandatory)][string]$OutputDirectory, [string]$ScanId = 'scan')
. (Join-Path $PSScriptRoot '_common.ps1')
$cli = Join-Path $HOME '.fst-tools\axe-windows\2.4.2\AxeWindowsCLI.exe'
if (-not (Test-Path $cli)) { throw "AxeWindowsCLI not found: $cli" }
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$script = "& '$cli' --processid $ProcessId --outputdirectory '$OutputDirectory' --scanid '$ScanId' --alwayssavetestfile; 'exit=' + `$LASTEXITCODE"
$output = Invoke-InDesktopSession -Script $script -TimeoutSeconds 120 -Purpose 'axe scan'
$output
if ($output -notmatch 'exit=0') { exit 1 }
