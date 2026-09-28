<#
.SYNOPSIS
    Measures startup, CPU, memory, GPU and frame delivery for one app scenario.
.DESCRIPTION
    Launches the app in the desktop session with --perf-log, reads its startup markers (ms since the OS
    recorded process start), waits for warm-up, then samples for -Seconds:
      * app CPU % of the whole machine (TotalProcessorTime delta / wall / logical cores) and dwm.exe CPU;
      * private and total working set (average and peak);
      * app GPU 3D engine utilization (\GPU Engine(pid_*_engtype_3D)\Utilization Percentage);
      * with -PresentMon: frames presented, FPS and frame-interval p50/p95/p99 (PresentMon 2.x CSV).
    Writes windows\.artifacts\perf\<label>.json and prints one summary line. Uses only this app's process.
.PARAMETER Scenario animated (Songs + carousel), scroll (animated + list auto-scroll), static (reduced motion),
    noart (save data), minimized (animated, then minimized), detail (Song Detail cover), idle-settings.
.PARAMETER Aot Measure the NativeAOT publish instead of the trimmed ReadyToRun publish.
.PARAMETER Configuration Release (default) or Debug.
.PARAMETER Seconds Sampling window.
.PARAMETER Warmup Seconds after first render before sampling.
.PARAMETER PresentMon Capture frame delivery (downloads PresentMon 2.6.0 console to %LOCALAPPDATA%\FestivalTools once).
.PARAMETER Label Output name (defaults to scenario + variant).
.PARAMETER ExtraArgs Additional app flags, e.g. --drift-fps 30.
.EXAMPLE
    pwsh tools/windows/perf.ps1 -Scenario scroll -Aot -PresentMon
#>
param(
    [ValidateSet('animated', 'scroll', 'static', 'noart', 'minimized', 'detail', 'idle-settings')][string]$Scenario = 'animated',
    [switch]$Aot,
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Release',
    [int]$Seconds = 30,
    [int]$Warmup = 10,
    [switch]$PresentMon,
    [string]$Label,
    [string]$DetailRoute = '/songs/004c0e25-dc54-4a4a-a2c8-8a17135c5a76',
    [string[]]$ExtraArgs = @()
)
. (Join-Path $PSScriptRoot '_common.ps1')

$variant = if ($Configuration -eq 'Debug') { 'debug' } elseif ($Aot) { 'aot' } else { 'jit' }
if (-not $Label) { $Label = "$Scenario-$variant" }
$outDir = Join-Path $Artifacts 'perf'
New-Item -ItemType Directory -Force $outDir | Out-Null
$log = Join-Path $outDir "$Label.log"
Remove-Item $log -ErrorAction SilentlyContinue

$extra = @('--perf-log', $log) + $ExtraArgs
$tab = 'songs'
$route = $null
switch ($Scenario) {
    'scroll' { $extra += '--auto-scroll' }
    'static' { $extra += '--reduce-motion' }
    'noart' { $extra += '--no-art' }
    'detail' { $route = $DetailRoute }
    'idle-settings' { $tab = 'settings' }
}
& (Join-Path $PSScriptRoot 'launch.ps1') -Configuration $Configuration -Aot:$Aot -Tab $tab -Route $route -ExtraArgs $extra | Out-Host

function Read-Markers {
    $markers = @{}
    if (Test-Path $log) {
        foreach ($line in Get-Content $log) {
            $name, $value = $line -split '=', 2
            $markers[$name] = [double]::Parse($value, [Globalization.CultureInfo]::InvariantCulture)
        }
    }
    return $markers
}
$ready = if ($Scenario -eq 'detail') { 'song-detail-rendered' } elseif ($Scenario -eq 'idle-settings') { 'shell-loaded' } else { 'songs-rendered' }
$deadline = (Get-Date).AddSeconds(60)
while (-not (Read-Markers).ContainsKey($ready) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 250 }
$markers = Read-Markers

if ($Scenario -eq 'minimized') {
    Invoke-InDesktopSession -Script @"
Add-Type -Name W -Namespace U -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int c);'
$FindWindowSnippet
[U.W]::ShowWindow([IntPtr]`$hwnd, 6) | Out-Null
"@ | Out-Null
}
Start-Sleep -Seconds $Warmup

$process = Get-AppProcess
if (-not $process) { throw 'App exited before sampling.' }
$appId = $process.Id
$dwm = Get-Process -Name dwm | Where-Object { $_.SessionId -eq $process.SessionId } | Select-Object -First 1
$cores = [Environment]::ProcessorCount

$pmJob = $null
$pmCsv = Join-Path $outDir "$Label.presentmon.csv"
if ($PresentMon) {
    $pmExe = Join-Path $ToolsCache 'PresentMon-2.6.0-x64.exe'
    if (-not (Test-Path $pmExe)) {
        New-Item -ItemType Directory -Force $ToolsCache | Out-Null
        Invoke-WebRequest 'https://github.com/GameTechDev/PresentMon/releases/download/v2.6.0/PresentMon-2.6.0-x64.exe' -OutFile $pmExe
    }
    Remove-Item $pmCsv -ErrorAction SilentlyContinue
    $pmJob = Start-Process $pmExe -ArgumentList '--process_id', $appId, '--output_file', $pmCsv, '--timed', $Seconds,
        '--terminate_after_timed', '--no_console_stats', '--stop_existing_session', '--session_name', 'FSTPerf' -PassThru -WindowStyle Hidden
}

$gpuPath = "\GPU Engine(pid_$($appId)_*engtype_3D)\Utilization Percentage"
$cpu0 = $process.TotalProcessorTime; $dwm0 = $dwm.TotalProcessorTime; $t0 = Get-Date
$private = @(); $working = @(); $gpu = @()
for ($i = 0; $i -lt $Seconds; $i++) {
    $sample = Get-Counter -Counter $gpuPath -ErrorAction SilentlyContinue
    $gpu += if ($sample) { ($sample.CounterSamples | Measure-Object CookedValue -Sum).Sum } else { 0 }
    $process.Refresh()
    $private += $process.PrivateMemorySize64; $working += $process.WorkingSet64
    Start-Sleep -Milliseconds 1000
}
$process.Refresh(); $dwm.Refresh()
$wall = ((Get-Date) - $t0).TotalSeconds
$cpu = ($process.TotalProcessorTime - $cpu0).TotalSeconds / $wall / $cores * 100
$cpuOneCore = ($process.TotalProcessorTime - $cpu0).TotalSeconds / $wall * 100
$dwmCpu = ($dwm.TotalProcessorTime - $dwm0).TotalSeconds / $wall / $cores * 100

$frames = $null
if ($pmJob) {
    $pmJob.WaitForExit(($Seconds + 20) * 1000) | Out-Null
    if (Test-Path $pmCsv) {
        $rows = Import-Csv $pmCsv
        $column = @('MsBetweenPresents', 'FrameTime', 'msBetweenPresents') | Where-Object { $rows.Count -gt 0 -and $rows[0].PSObject.Properties.Name -contains $_ } | Select-Object -First 1
        if ($column) {
            $intervals = @($rows | ForEach-Object { [double]::Parse($_.$column, [Globalization.CultureInfo]::InvariantCulture) } | Where-Object { $_ -gt 0 } | Sort-Object)
            $pct = { param($p) if ($intervals.Count) { $intervals[[math]::Min($intervals.Count - 1, [int]($intervals.Count * $p))] } else { $null } }
            $frames = [ordered]@{
                presents = $rows.Count
                fps = [math]::Round($rows.Count / $Seconds, 1)
                intervalP50Ms = [math]::Round((& $pct 0.50), 2)
                intervalP95Ms = [math]::Round((& $pct 0.95), 2)
                intervalP99Ms = [math]::Round((& $pct 0.99), 2)
                over33Ms = @($intervals | Where-Object { $_ -gt 33.4 }).Count
                column = $column
            }
        }
    }
}

$summary = [ordered]@{
    label = $Label; scenario = $Scenario; variant = $variant; seconds = $Seconds; cores = $cores
    startup = [ordered]@{ windowActivatedMs = $markers['window-activated']; shellLoadedMs = $markers['shell-loaded']; readyMs = $markers[$ready] }
    cpuPercentOfMachine = [math]::Round($cpu, 2); cpuPercentOfOneCore = [math]::Round($cpuOneCore, 1)
    dwmCpuPercentOfMachine = [math]::Round($dwmCpu, 2)
    privateMBAvg = [math]::Round(($private | Measure-Object -Average).Average / 1MB, 1)
    privateMBPeak = [math]::Round(($private | Measure-Object -Maximum).Maximum / 1MB, 1)
    workingSetMBAvg = [math]::Round(($working | Measure-Object -Average).Average / 1MB, 1)
    gpu3DPercentAvg = [math]::Round(($gpu | Measure-Object -Average).Average, 2)
    frames = $frames
    capturedAt = (Get-Date).ToString('o')
}
$summary | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $outDir "$Label.json")
Stop-App
'{0,-22} ready {1,6:N0} ms | CPU {2,5:N2}% machine ({3,5:N1}% core) | DWM {4,5:N2}% | private {5,6:N1} MB | WS {6,6:N1} MB | GPU3D {7,5:N2}% {8}' -f `
    $Label, $markers[$ready], $cpu, $cpuOneCore, $dwmCpu, $summary.privateMBAvg, $summary.workingSetMBAvg, $summary.gpu3DPercentAvg,
    $(if ($frames) { "| {0} fps p50 {1} p95 {2} p99 {3} >33ms {4}" -f $frames.fps, $frames.intervalP50Ms, $frames.intervalP95Ms, $frames.intervalP99Ms, $frames.over33Ms } else { '' })
