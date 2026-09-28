<#
.SYNOPSIS
    Measures startup, CPU, memory, GPU and frame delivery for one app scenario.
.DESCRIPTION
    Launches the app in the desktop session with --perf-log, reads its startup markers (ms since the OS
    recorded process start), waits for warm-up, then samples for -Seconds:
      * app CPU % of the whole machine (TotalProcessorTime delta / wall / logical cores) and dwm.exe CPU;
      * private and total working set (average and peak);
      * app GPU 3D engine utilization (\GPU Engine(pid_*_engtype_3D)\Utilization Percentage);
      * scroll scenario: UI-thread frame intervals from the app's --frame-stats (first 5 s window skipped);
      * with -PresentMon: frames presented, FPS and frame-interval p50/p95/p99 (PresentMon 2.x CSV).
    Writes windows\.artifacts\perf\<label>.json and prints one summary line. Uses only this app's process.
.PARAMETER Scenario animated (Songs + carousel), scroll (animated + list auto-scroll), static (reduced motion),
    noart (save data), minimized (animated, then minimized), occluded (animated, then fully covered by an opaque
    non-topmost window for the whole sample), detail (Song Detail cover), idle-settings.
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
    [ValidateSet('animated', 'scroll', 'static', 'noart', 'minimized', 'occluded', 'detail', 'idle-settings')][string]$Scenario = 'animated',
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
    'scroll' { $extra += @('--auto-scroll', '--frame-stats') }
    'static' { $extra += '--reduce-motion' }
    'noart' { $extra += '--no-art' }
    'detail' { $route = $DetailRoute }
    'idle-settings' { $tab = 'settings' }
}
& (Join-Path $PSScriptRoot 'launch.ps1') -Configuration $Configuration -Aot:$Aot -Tab $tab -Route $route -ExtraArgs $extra | Out-Host

function Read-Markers {
    $markers = @{}
    if (Test-Path $log) {
        foreach ($line in Get-Content $log | Where-Object { $_ -notlike 'ui-frames *' }) {
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
if ($Scenario -eq 'occluded') {
    # An ordinary (not topmost) opaque window over the app's frame, closed by its own timer after the sample.
    $coverSeconds = $Warmup + $Seconds + 10
    Invoke-InDesktopSession -NoWait -Purpose 'perf cover' -Script @"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Name W -Namespace U -MemberDefinition '[DllImport("user32.dll")] public static extern bool GetWindowRect(System.IntPtr h, out RECT r); public struct RECT { public int L, T, R, B; }'
$FindWindowSnippet
`$r = New-Object U.W+RECT; [U.W]::GetWindowRect([IntPtr]`$hwnd, [ref]`$r) | Out-Null
`$form = New-Object Windows.Forms.Form
`$form.FormBorderStyle = 'None'; `$form.StartPosition = 'Manual'; `$form.BackColor = 'Black'; `$form.ShowInTaskbar = `$false
`$form.Text = 'FST perf cover'
`$form.Bounds = New-Object Drawing.Rectangle((`$r.L - 16), (`$r.T - 16), (`$r.R - `$r.L + 32), (`$r.B - `$r.T + 32))
`$timer = New-Object Windows.Forms.Timer; `$timer.Interval = $($coverSeconds * 1000); `$timer.Add_Tick({ `$form.Close() }); `$timer.Start()
[Windows.Forms.Application]::Run(`$form)
"@
    # The cover may queue behind other lanes on the desktop lock; sample only once the app reports it covered.
    $deadline = (Get-Date).AddSeconds(120)
    while (-not (Select-String -Path $log -Pattern '^occlusion-covered=' -Quiet) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 250 }
    if (-not (Select-String -Path $log -Pattern '^occlusion-covered=' -Quiet)) { Stop-App; throw 'The app never reported occlusion-covered.' }
}
Start-Sleep -Seconds $Warmup

$process = Get-AppProcess
if (-not $process) { throw 'App exited before sampling.' }
$appId = $process.Id
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
# dwm.exe's TotalProcessorTime needs elevation; the Process counter does not (all DWM instances, one per session).
$dwmPath = '\Process(dwm*)\% Processor Time'
$cpu0 = $process.TotalProcessorTime; $t0 = Get-Date
$private = @(); $working = @(); $gpu = @(); $dwmSamples = @()
for ($i = 0; $i -lt $Seconds; $i++) {
    $sample = Get-Counter -Counter $gpuPath, $dwmPath -ErrorAction SilentlyContinue
    $samples = if ($sample) { @($sample.CounterSamples) } else { @() }
    # Sum by hand: Measure-Object over no samples (e.g. no GPU engine instance while minimized) has no Sum under StrictMode.
    $gpuTotal = 0.0; $dwmTotal = 0.0
    foreach ($s in $samples) {
        if ($s.Path -like '*gpu engine*') { $gpuTotal += $s.CookedValue } elseif ($s.Path -like '*\process(dwm*') { $dwmTotal += $s.CookedValue }
    }
    $gpu += $gpuTotal; $dwmSamples += $dwmTotal
    $process.Refresh()
    $private += $process.PrivateMemorySize64; $working += $process.WorkingSet64
    Start-Sleep -Milliseconds 1000
}
$process.Refresh()
$wall = ((Get-Date) - $t0).TotalSeconds
$cpu = ($process.TotalProcessorTime - $cpu0).TotalSeconds / $wall / $cores * 100
$cpuOneCore = ($process.TotalProcessorTime - $cpu0).TotalSeconds / $wall * 100
$dwmCpu = ($dwmSamples | Measure-Object -Average).Average / $cores

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

$uiFrames = $null
$statLines = @(Get-Content $log -ErrorAction SilentlyContinue | Where-Object { $_ -like 'ui-frames *' } | Select-Object -Skip 1)
if ($statLines) {
    $parsed = $statLines | ForEach-Object {
        $h = @{}; foreach ($pair in ($_ -split ' ' | Select-Object -Skip 1)) { $k, $v = $pair -split '='; $h[$k] = [double]::Parse($v, [Globalization.CultureInfo]::InvariantCulture) }; $h
    }
    $uiFrames = [ordered]@{
        fps = [math]::Round(($parsed | ForEach-Object { $_.count } | Measure-Object -Sum).Sum / (5 * $parsed.Count), 1)
        p50Ms = ($parsed | ForEach-Object { $_.p50 } | Measure-Object -Average).Average
        p95Ms = ($parsed | ForEach-Object { $_.p95 } | Measure-Object -Maximum).Maximum
        p99Ms = ($parsed | ForEach-Object { $_.p99 } | Measure-Object -Maximum).Maximum
        over33 = ($parsed | ForEach-Object { $_.over33 } | Measure-Object -Sum).Sum
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
    gpu3DPercentSamples = @($gpu | ForEach-Object { [math]::Round($_, 2) })
    frames = $frames
    uiFrames = $uiFrames
    occlusionEvents = @(Get-Content $log -ErrorAction SilentlyContinue | Where-Object { $_ -like 'occlusion-*' })
    capturedAt = (Get-Date).ToString('o')
}
$summary | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $outDir "$Label.json")
Stop-App
'{0,-22} ready {1,6:N0} ms | CPU {2,5:N2}% machine ({3,5:N1}% core) | DWM {4,5:N2}% | private {5,6:N1} MB | WS {6,6:N1} MB | GPU3D {7,5:N2}% {8}' -f `
    $Label, $markers[$ready], $cpu, $cpuOneCore, $dwmCpu, $summary.privateMBAvg, $summary.workingSetMBAvg, $summary.gpu3DPercentAvg,
    $(if ($uiFrames) { "| UI {0} fps p50 {1:N1} p95 {2:N1} p99 {3:N1} ms >33ms {4}" -f $uiFrames.fps, $uiFrames.p50Ms, $uiFrames.p95Ms, $uiFrames.p99Ms, $uiFrames.over33 } elseif ($frames) { "| {0} fps p50 {1} p95 {2} p99 {3} >33ms {4}" -f $frames.fps, $frames.intervalP50Ms, $frames.intervalP95Ms, $frames.intervalP99Ms, $frames.over33Ms } else { '' })
