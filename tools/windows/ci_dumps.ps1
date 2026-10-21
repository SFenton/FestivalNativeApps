<#
.SYNOPSIS
    Keeps a full crash dump of the app on a hosted CI runner and logs Windows Error Reporting's state.

.DESCRIPTION
    A WinUI fail-fast (0xC000027B, a stowed exception raised inside Microsoft.UI.Xaml.dll) ends the app without
    reaching App.UnhandledException, so diagnostics.log stays empty and the window simply disappears (#680). WER
    LocalDumps writes FestivalScoreTracker.exe's dump into -Folder, which the workflow uploads with the run's results;
    WER's UI stays off so a crash never waits on a dialog. Run before launching the app (windows-ui.yml).

.PARAMETER Folder
    Dump folder inside the uploaded results folder.
#>
param([Parameter(Mandatory)][string]$Folder)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $Folder | Out-Null
$wer = 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting'
$policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting'
foreach ($path in $wer, $policy) {
    $values = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
    Write-Host "$path Disabled=$($values.Disabled) DontShowUI=$($values.DontShowUI)"
}
New-Item -Path $wer -Force | Out-Null
Set-ItemProperty -Path $wer -Name Disabled -Value 0 -Type DWord
Set-ItemProperty -Path $wer -Name DontShowUI -Value 1 -Type DWord
if (Test-Path $policy) { Remove-ItemProperty -Path $policy -Name Disabled -ErrorAction SilentlyContinue }
$dumps = "$wer\LocalDumps\FestivalScoreTracker.exe"
New-Item -Path $dumps -Force | Out-Null
Set-ItemProperty -Path $dumps -Name DumpFolder -Value $Folder -Type ExpandString
Set-ItemProperty -Path $dumps -Name DumpType -Value 2 -Type DWord
Set-ItemProperty -Path $dumps -Name DumpCount -Value 3 -Type DWord
$service = Get-Service -Name WerSvc
if ($service.StartType -eq 'Disabled') { Set-Service -Name WerSvc -StartupType Manual }
Write-Host "WerSvc: $($service.Status) ($((Get-Service -Name WerSvc).StartType)); app dumps: $Folder"
