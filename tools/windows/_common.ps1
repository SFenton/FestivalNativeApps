<#
.SYNOPSIS
    Shared helpers for tools/windows/*.ps1 (dot-source this file).
.DESCRIPTION
    Paths, dotnet environment, app executable resolution and running commands inside the signed-in
    desktop session. SSH sessions run in session 0, which has no desktop: GUI launches, screenshots and
    frame capture go through a one-shot "run only when user is logged on" scheduled task (/IT) so they
    execute in the console user's session. No credentials are stored or requested.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:WindowsRoot = Join-Path $RepoRoot 'windows'
$script:Artifacts = Join-Path $WindowsRoot '.artifacts'
$script:AppProject = Join-Path $WindowsRoot 'Festival.App\Festival.App.csproj'
$script:TestProject = Join-Path $WindowsRoot 'Festival.Core.Tests\Festival.Core.Tests.csproj'
$script:AppExeName = 'FestivalScoreTracker.exe'
$script:AppProcessName = 'FestivalScoreTracker'
$script:ToolsCache = Join-Path $env:LOCALAPPDATA 'FestivalTools'

function Initialize-DotnetEnvironment {
    <# .SYNOPSIS Makes dotnet/NativeAOT find vswhere and keeps CLI output quiet. #>
    $installer = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer'
    if ((Test-Path $installer) -and ($env:PATH -notlike "*$installer*")) { $env:PATH = "$env:PATH;$installer" }
    $env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
    $env:DOTNET_NOLOGO = '1'
    $env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
}

function Get-AppExe {
    <#
    .SYNOPSIS Resolves the app executable for a configuration.
    .PARAMETER Configuration Debug (dotnet build output) or Release (published to .artifacts).
    .PARAMETER Aot Use the NativeAOT Release publish.
    .OUTPUTS Full path; throws if it has not been built.
    #>
    param([ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug', [switch]$Aot)
    $path = if ($Configuration -eq 'Debug') {
        Join-Path $WindowsRoot "Festival.App\bin\x64\Debug\net9.0-windows10.0.26100.0\win-x64\$AppExeName"
    } else {
        Join-Path $Artifacts ("app\Release" + $(if ($Aot) { '-aot' } else { '' }) + "\$AppExeName")
    }
    if (-not (Test-Path $path)) { throw "App not built: $path. Run tools/windows/build.ps1 -Configuration $Configuration$(if ($Aot) { ' -Aot' })." }
    return $path
}

function Test-DesktopSession {
    <# .SYNOPSIS True when this process already runs in an interactive desktop session (not session 0). #>
    return (Get-Process -Id $PID).SessionId -ne 0
}

function Invoke-InDesktopSession {
    <#
    .SYNOPSIS Runs a PowerShell script block's text in the signed-in desktop session and returns its output.
    .PARAMETER Script PowerShell source to run (Windows PowerShell 5.1, so System.Drawing is available).
    .PARAMETER TimeoutSeconds How long to wait for completion.
    .PARAMETER NoWait Start it and return immediately (for launching the app).
    .PARAMETER Purpose Label recorded by the desktop lock.
    .NOTES Every hop holds the shared FIFO desktop lock (≤300 s) for its duration only.
    #>
    param([Parameter(Mandatory)][string]$Script, [int]$TimeoutSeconds = 120, [switch]$NoWait, [string]$Purpose = 'script')
    $work = Join-Path $env:TEMP ("fst-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $work | Out-Null
    $body = Join-Path $work 'body.ps1'
    $out = Join-Path $work 'out.txt'
    $done = Join-Path $work 'done.txt'
    $wrapped = @"
`$ErrorActionPreference = 'Stop'
try { & { $Script } *>&1 | Out-File -FilePath '$out' -Encoding utf8 } catch { `$_ | Out-String | Out-File -FilePath '$out' -Append -Encoding utf8 }
'done' | Out-File -FilePath '$done'
"@
    Set-Content -Path $body -Value $wrapped -Encoding UTF8
    # Queue on the shared desktop lock (tools/windows/desktop_lock.py) like uiwin.py and other lanes.
    $taskArgs = @('-NoProfile', '-File', (Join-Path $PSScriptRoot '_desktop_task.ps1'), '-Body', $body, '-Done', $done, '-TimeoutSeconds', $TimeoutSeconds)
    if ($NoWait) { $taskArgs += '-NoWait' }
    python (Join-Path $PSScriptRoot 'desktop_lock.py') --purpose "tools/windows $Purpose" -- pwsh @taskArgs
    if ($LASTEXITCODE -ne 0) { throw "Desktop-session step failed ($LASTEXITCODE): see $work" }
    if ($NoWait) { return }
    if (Test-Path $out) { Get-Content $out -Raw }
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}

function Stop-App {
    <#
    .SYNOPSIS Stops running instances built from this worktree only.
    .NOTES Parallel lanes run their own builds on the same desktop; stopping every process with the app's name
          closed other lanes' windows mid-capture.
    #>
    $mine = { Get-Process -Name $AppProcessName -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($WindowsRoot, [StringComparison]::OrdinalIgnoreCase) } }
    & $mine | Stop-Process -Force
    for ($i = 0; $i -lt 20 -and (& $mine); $i++) { Start-Sleep -Milliseconds 250 }
}

function Get-AppProcess {
    <#
    .SYNOPSIS Returns the running app process (any session), or $null.
    .NOTES From session 0 MainWindowHandle is always 0 (EnumWindows only sees its own desktop), so window
          handles are resolved inside the desktop session by the scripts that need them.
    #>
    Get-Process -Name $AppProcessName -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($WindowsRoot, [StringComparison]::OrdinalIgnoreCase) } |
        Select-Object -First 1
}

# Desktop-session snippet: waits for the app's main window and sets $hwnd/$proc ($env:FST_CAPTURE_PROCESS overrides the name).
$script:FindWindowSnippet = @"
`$proc = `$null; `$deadline = (Get-Date).AddSeconds(45)
while ((Get-Date) -lt `$deadline) {
    `$proc = Get-Process -Name '$(if ($env:FST_CAPTURE_PROCESS) { $env:FST_CAPTURE_PROCESS } else { $AppProcessName })' -ErrorAction SilentlyContinue | Where-Object { `$_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if (`$proc) { break }
    Start-Sleep -Milliseconds 200
}
if (-not `$proc) { throw 'App window not found.' }
`$hwnd = `$proc.MainWindowHandle
"@
