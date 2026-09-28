<#
.SYNOPSIS
    Runs Festival.Core unit tests, optionally with Cobertura coverage and the repo coverage gate.
.PARAMETER Coverage Collect coverage (coverlet) to windows\.artifacts\coverage\coverage.cobertura.xml and run
    tools/coverage_gate.py --language csharp (95% logic: Data/Domain, 90% UX: ViewModels).
.PARAMETER Filter dotnet test --filter expression for iterating on a subset.
.EXAMPLE
    pwsh tools/windows/test.ps1 -Coverage
#>
param([switch]$Coverage, [string]$Filter)
. (Join-Path $PSScriptRoot '_common.ps1')
Initialize-DotnetEnvironment

$arguments = @('test', $TestProject, '-nologo')
if ($Filter) { $arguments += @('--filter', $Filter) }
if ($Coverage) {
    $results = Join-Path $Artifacts 'coverage\raw'
    if (Test-Path $results) { Remove-Item -Recurse -Force $results }
    $arguments += @('--settings', (Join-Path $WindowsRoot 'coverage.runsettings'), '--collect:XPlat Code Coverage', '--results-directory', $results)
}
dotnet @arguments
if ($LASTEXITCODE -ne 0) { throw "Tests failed ($LASTEXITCODE)." }

if ($Coverage) {
    $report = Get-ChildItem $results -Recurse -Filter coverage.cobertura.xml | Select-Object -First 1
    $target = Join-Path $Artifacts 'coverage\coverage.cobertura.xml'
    Copy-Item $report.FullName $target -Force
    [xml]$xml = Get-Content $target
    'Line coverage {0:P2} ({1}/{2}), branch {3:P2}' -f [double]$xml.coverage.'line-rate', $xml.coverage.'lines-covered', $xml.coverage.'lines-valid', [double]$xml.coverage.'branch-rate'
    python (Join-Path $RepoRoot 'tools\coverage_gate.py') --language csharp --report $target
    if ($LASTEXITCODE -ne 0) { throw 'Coverage gate failed.' }
}
