<#
.SYNOPSIS
    Turns on Windows animation and transparency effects on a hosted CI runner and logs the result.

.DESCRIPTION
    Hosted windows-latest runners start with client-area animations off, so UISettings.AnimationsEnabled is
    false: marquee titles never scroll, the first-run demo swaps instantly and fade journeys see no fades.
    Journeys that test Reduce Motion turn it off themselves (a11y_matrix modes) and restore it afterwards.
    Run before launching the app (windows-ui.yml).
#>
$ErrorActionPreference = 'Stop'
Add-Type -Namespace Fst -Name Spi -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true)]
public static extern bool SystemParametersInfo(uint action, uint param, System.IntPtr vparam, uint winIni);
[DllImport("user32.dll", SetLastError = true)]
public static extern bool SystemParametersInfo(uint action, uint param, ref bool vparam, uint winIni);
'@
$SPI_GETCLIENTAREAANIMATION = 0x1042
$SPI_SETCLIENTAREAANIMATION = 0x1043
$SPIF_UPDATE_AND_SEND = 0x3
if (-not [Fst.Spi]::SystemParametersInfo($SPI_SETCLIENTAREAANIMATION, 0, [System.IntPtr]1, $SPIF_UPDATE_AND_SEND)) {
    throw "SPI_SETCLIENTAREAANIMATION failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
}
$personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
New-Item -Path $personalize -Force | Out-Null
Set-ItemProperty -Path $personalize -Name EnableTransparency -Value 1 -Type DWord
$on = $false
[void][Fst.Spi]::SystemParametersInfo($SPI_GETCLIENTAREAANIMATION, 0, [ref]$on, 0)
$transparency = (Get-ItemProperty -Path $personalize -Name EnableTransparency).EnableTransparency
Write-Host "client-area animations: $on; transparency: $transparency"
if (-not $on) { throw 'client-area animations are still off' }
