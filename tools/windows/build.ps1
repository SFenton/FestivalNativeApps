<#
.SYNOPSIS
    Builds the Windows app and Core library.
.DESCRIPTION
    Debug: dotnet build (output under Festival.App\bin). Release: dotnet publish (trimmed, ReadyToRun) to
    windows\.artifacts\app\Release; -Aot publishes NativeAOT to windows\.artifacts\app\Release-aot.
.PARAMETER Configuration Debug or Release.
.PARAMETER Aot NativeAOT publish (Release only).
.PARAMETER Clean Remove previous outputs first.
.EXAMPLE
    pwsh tools/windows/build.ps1 -Configuration Release
#>
param(
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug',
    [switch]$Aot,
    [switch]$Clean
)
. (Join-Path $PSScriptRoot '_common.ps1')
Initialize-DotnetEnvironment

if ($Clean) {
    Get-ChildItem $WindowsRoot -Directory -Recurse -Include bin, obj | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

Stop-App  # a running instance locks its output folder
$started = Get-Date
if ($Configuration -eq 'Debug') {
    if ($Aot) { throw '-Aot requires -Configuration Release.' }
    dotnet build $AppProject -c Debug -p:Platform=x64 -nologo -clp:NoSummary
} else {
    $out = Join-Path $Artifacts ("app\Release" + $(if ($Aot) { '-aot' } else { '' }))
    if (Test-Path $out) { Remove-Item -Recurse -Force $out }
    $aotFlag = if ($Aot) { 'true' } else { 'false' }
    dotnet publish $AppProject -c Release -p:Platform=x64 -p:FstAot=$aotFlag -o $out -nologo -clp:NoSummary
}
if ($LASTEXITCODE -ne 0) { throw "Build failed ($LASTEXITCODE)." }
$exe = Get-AppExe -Configuration $Configuration -Aot:$Aot
$size = (Get-ChildItem (Split-Path $exe) -Recurse -File | Measure-Object Length -Sum).Sum / 1MB
'{0} build OK in {1:N0} s: {2} (folder {3:N1} MB)' -f $Configuration, ((Get-Date) - $started).TotalSeconds, $exe, $size
