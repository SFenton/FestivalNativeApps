<#
.SYNOPSIS
    Language/runtime floor benchmark: C++/WinRT vs C# (ReadyToRun) vs C# NativeAOT twins.
.DESCRIPTION
    Builds windows\Bench\Cpp (MSBuild) and windows\Bench\CSharp (dotnet publish, JIT and -p:FstAot=true), writes
    a synthetic benchmark image next to each executable, then runs each variant -Runs times in the desktop
    session and reports medians of: window-activated and first-frame time (ms since OS process start), private
    and working-set memory after settling, and CPU while animating (stepped composition zoom) and static.
    Results: windows\.artifacts\bench\results.json.
.PARAMETER Runs Launches per variant (median reported).
.PARAMETER Seconds CPU sampling window per run.
.PARAMETER SkipBuild Reuse existing outputs.
.EXAMPLE
    pwsh tools/windows/bench.ps1 -Runs 5
#>
param([int]$Runs = 5, [int]$Seconds = 15, [switch]$SkipBuild)
. (Join-Path $PSScriptRoot '_common.ps1')
Initialize-DotnetEnvironment

$benchRoot = Join-Path $WindowsRoot 'Bench'
$out = Join-Path $Artifacts 'bench'
New-Item -ItemType Directory -Force $out | Out-Null
$msbuild = Join-Path $env:ProgramFiles 'Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe'

if (-not $SkipBuild) {
    & $msbuild (Join-Path $benchRoot 'Cpp\BenchCpp.vcxproj') -restore -p:Configuration=Release -p:Platform=x64 -v:m -nologo | Out-Host
    if ($LASTEXITCODE) { throw 'C++ bench build failed.' }
    foreach ($aot in 'false', 'true') {
        dotnet publish (Join-Path $benchRoot 'CSharp\BenchCSharp.csproj') -c Release -p:FstAot=$aot -o (Join-Path $out "cs-$aot") -nologo | Out-Host
        if ($LASTEXITCODE) { throw 'C# bench build failed.' }
    }
}

$variants = [ordered]@{
    'cpp-winrt' = Join-Path $benchRoot 'Cpp\x64\Release\BenchCpp.exe'
    'csharp-r2r' = Join-Path $out 'cs-false\BenchCSharp.exe'
    'csharp-aot' = Join-Path $out 'cs-true\BenchCSharp.exe'
}

# Synthetic, original image (never third-party art).
$art = Join-Path $out 'bench-art.png'
if (-not (Test-Path $art)) {
    python -c @"
import zlib, struct, random
w=h=1024; random.seed(7); rows=bytearray()
for y in range(h):
    rows.append(0)
    for x in range(w):
        n=random.randint(0,40); rows += bytes(((x*255//w+n)%256, (y*255//h+n)%256, ((x+y)*255//(2*w))%256))
c=lambda t,d: struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
open(r'$art','wb').write(b'\x89PNG\r\n\x1a\n'+c(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+c(b'IDAT',zlib.compress(bytes(rows),9))+c(b'IEND',b''))
"@
}
foreach ($exe in $variants.Values) { Copy-Item $art (Split-Path $exe) -Force }

function Measure-Run([string]$Exe, [string[]]$Arguments, [string]$Log) {
    $name = [IO.Path]::GetFileNameWithoutExtension($Exe)
    Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force
    Remove-Item $Log -ErrorAction SilentlyContinue
    $quoted = (@($Arguments) + @('--perf-log', $Log) | ForEach-Object { "'$_'" }) -join ','
    Invoke-InDesktopSession -Script "Start-Process -FilePath '$Exe' -WorkingDirectory '$(Split-Path $Exe)' -ArgumentList @($quoted)" | Out-Null
    $deadline = (Get-Date).AddSeconds(30)
    while (-not ((Test-Path $Log) -and (Select-String -Path $Log -Pattern 'first-frame' -Quiet)) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200 }
    Start-Sleep -Seconds 5
    $p = Get-Process -Name $name | Select-Object -First 1
    $cpu0 = $p.TotalProcessorTime; $t0 = Get-Date
    Start-Sleep -Seconds $Seconds
    $p.Refresh()
    $cpu = ($p.TotalProcessorTime - $cpu0).TotalSeconds / ((Get-Date) - $t0).TotalSeconds * 100
    $markers = @{}
    foreach ($line in Get-Content $Log) { $k, $v = $line -split '='; $markers[$k] = [double]::Parse($v, [Globalization.CultureInfo]::InvariantCulture) }
    $result = [pscustomobject]@{
        activatedMs = $markers['window-activated']; firstFrameMs = $markers['first-frame']
        privateMB = $p.PrivateMemorySize64 / 1MB; workingSetMB = $p.WorkingSet64 / 1MB; cpuPercentOneCore = $cpu
    }
    $p | Stop-Process -Force
    Start-Sleep -Milliseconds 500
    return $result
}

function Median([double[]]$values) { $s = $values | Sort-Object; if ($s.Count) { $s[[int][math]::Floor(($s.Count - 1) / 2)] } }

$results = [ordered]@{}
foreach ($variant in $variants.Keys) {
    $animated = @(); $static = @()
    for ($i = 0; $i -lt $Runs; $i++) {
        $animated += Measure-Run $variants[$variant] @() (Join-Path $out "$variant-a$i.log")
        $static += Measure-Run $variants[$variant] @('--static') (Join-Path $out "$variant-s$i.log")
    }
    $folder = (Get-ChildItem (Split-Path $variants[$variant]) -Recurse -File | Measure-Object Length -Sum).Sum / 1MB
    $results[$variant] = [ordered]@{
        activatedMs = [math]::Round((Median $animated.activatedMs), 0)
        firstFrameMs = [math]::Round((Median ($animated.firstFrameMs + $static.firstFrameMs)), 0)
        privateMB = [math]::Round((Median ($animated.privateMB + $static.privateMB)), 1)
        workingSetMB = [math]::Round((Median ($animated.workingSetMB + $static.workingSetMB)), 1)
        cpuAnimatedOneCore = [math]::Round((Median $animated.cpuPercentOneCore), 2)
        cpuStaticOneCore = [math]::Round((Median $static.cpuPercentOneCore), 2)
        folderMB = [math]::Round($folder, 1)
        runs = $Runs
    }
    '{0,-11} first frame {1,5} ms | activated {2,5} ms | private {3,6} MB | WS {4,6} MB | CPU animated {5,5}% / static {6,5}% of one core | {7} MB on disk' -f `
        $variant, $results[$variant].firstFrameMs, $results[$variant].activatedMs, $results[$variant].privateMB, $results[$variant].workingSetMB,
        $results[$variant].cpuAnimatedOneCore, $results[$variant].cpuStaticOneCore, $results[$variant].folderMB
}
$results | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $out 'results.json')
