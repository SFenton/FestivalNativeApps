<#
.SYNOPSIS
    Launches the app in the signed-in desktop session with debug arguments.
.DESCRIPTION
    Equivalent of Apple's FST_DEBUG_TAB/FST_DEBUG_ROUTE: -Tab selects a section and -Route pushes a
    typed web path (e.g. /songs/<id>). -Fixture starts tools/mock_service.py on loopback and points the app
    at it; otherwise the app uses keyless public HTTPS. Stops a previous instance first.
.PARAMETER Configuration Debug or Release.
.PARAMETER Aot Launch the NativeAOT Release publish.
.PARAMETER Tab songs | leaderboards | settings | suggestions | rivals | statistics.
.PARAMETER Route Web path such as /songs/<songId> or /songs/<songId>/Solo_Guitar.
.PARAMETER Fixture Use the loopback mock service (port 8765).
.PARAMETER Width Client width in DIPs.
.PARAMETER Height Client height in DIPs.
.PARAMETER ExtraArgs Additional app flags (--reduce-motion, --no-art, --auto-scroll, --perf-log <path>).
.EXAMPLE
    pwsh tools/windows/launch.ps1 -Tab songs -Route /songs/004c0e25-dc54-4a4a-a2c8-8a17135c5a76
#>
param(
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug',
    [switch]$Aot,
    [string]$Tab,
    [string]$Route,
    [switch]$Fixture,
    [int]$Width = 1280,
    [int]$Height = 820,
    [string[]]$ExtraArgs = @()
)
. (Join-Path $PSScriptRoot '_common.ps1')

$exe = Get-AppExe -Configuration $Configuration -Aot:$Aot
Stop-App
$appArgs = @('--width', $Width, '--height', $Height)
if ($Tab) { $appArgs += @('--tab', $Tab) }
if ($Route) { $appArgs += @('--route', $Route) }
if ($Fixture) {
    if (-not (Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue)) {
        Start-Process python -ArgumentList (Join-Path $RepoRoot 'tools\mock_service.py'), '--port', '8765' -WindowStyle Hidden
        Start-Sleep -Seconds 2
    }
    $appArgs += @('--base-url', 'http://127.0.0.1:8765/')
}
$appArgs += $ExtraArgs
$quoted = ($appArgs | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ','
$result = Invoke-InDesktopSession -TimeoutSeconds 90 -Script @"
Start-Process -FilePath '$exe' -WorkingDirectory '$(Split-Path $exe)' -ArgumentList @($quoted) | Out-Null
$FindWindowSnippet
"pid=`$(`$proc.Id) hwnd=`$hwnd"
"@
"Launched $exe ($($result.Trim())) $($appArgs -join ' ')"
