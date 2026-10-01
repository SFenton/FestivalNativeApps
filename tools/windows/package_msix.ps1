<#
.SYNOPSIS
    Builds the unsigned Microsoft Store MSIX for the Windows app.
.DESCRIPTION
    Stamps windows\store-identity.json (Partner Center identity) and the version into
    Festival.App\Package.appxmanifest, publishes with -p:FstMsix=true and restores the manifest. The Store signs
    the uploaded package, so no certificate is involved. Version is <csproj major>.<minor>.<commit count>.0:
    monotonic on master and with the revision 0 the Store requires. Writes <OutDir>\FestivalScoreTracker_<v>_x64.<ext>
    plus build.json {version, sha, placeholder, package} for tools/release/fst_store.py.
.PARAMETER OutDir Output folder (default windows\.artifacts\msix).
.PARAMETER AllowPlaceholder Build even while store-identity.json still has placeholders (CI packaging check);
    the result is marked placeholder and fst_store.py never submits it.
.PARAMETER Version Override the computed four-part version.
.EXAMPLE
    pwsh tools/windows/package_msix.ps1 -AllowPlaceholder
#>
param(
    [string]$OutDir,
    [switch]$AllowPlaceholder,
    [string]$Version
)
. (Join-Path $PSScriptRoot '_common.ps1')
Initialize-DotnetEnvironment
$ErrorActionPreference = 'Stop'

if (-not $OutDir) { $OutDir = Join-Path $Artifacts 'msix' }
$identityFile = Join-Path $WindowsRoot 'store-identity.json'
$identity = Get-Content -Raw $identityFile | ConvertFrom-Json
$fields = @($identity.packageName, $identity.publisher, $identity.publisherDisplayName)
$placeholder = [bool]($fields | Where-Object { -not $_ -or $_ -match 'placeholder' })
if ($placeholder -and -not $AllowPlaceholder) {
    throw "windows\store-identity.json still has placeholders; copy Package/Identity/Name, Publisher and PublisherDisplayName from Partner Center > Product identity (or pass -AllowPlaceholder for a packaging check)."
}

$sha = (git -C $RepoRoot rev-parse HEAD).Trim()
if (-not $Version) {
    $csproj = [xml](Get-Content -Raw $AppProject)
    $semver = ($csproj.Project.PropertyGroup | ForEach-Object { $_.Version } | Where-Object { $_ } | Select-Object -First 1)
    $parts = $semver.Split('.')
    $count = [int](git -C $RepoRoot rev-list --count HEAD).Trim()
    if ($count -gt 65535) { throw "commit count $count exceeds the MSIX version field" }
    $Version = '{0}.{1}.{2}.0' -f $parts[0], $parts[1], $count
}
if ($Version -notmatch '^\d+\.\d+\.\d+\.0$') { throw "MSIX version $Version must be four numbers ending in .0" }

$manifestPath = Join-Path $WindowsRoot 'Festival.App\Package.appxmanifest'
$original = [System.IO.File]::ReadAllText($manifestPath)
$staging = Join-Path $OutDir 'pkg'
try {
    $xml = [xml]$original
    $xml.Package.Identity.Name = [string]$identity.packageName
    $xml.Package.Identity.Publisher = [string]$identity.publisher
    $xml.Package.Identity.Version = $Version
    $xml.Package.Properties.PublisherDisplayName = [string]$identity.publisherDisplayName
    $xml.Save($manifestPath)

    if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
    Stop-App
    dotnet publish $AppProject -c Release -p:Platform=x64 -p:FstMsix=true "-p:AppxPackageDir=$staging\" -nologo -clp:NoSummary
    if ($LASTEXITCODE -ne 0) { throw "MSIX publish failed ($LASTEXITCODE)." }
} finally {
    [System.IO.File]::WriteAllText($manifestPath, $original)
}

$package = Get-ChildItem $staging -Recurse -File -Include *.msixupload, *.msix |
    Sort-Object { if ($_.Extension -eq '.msixupload') { 0 } else { 1 } } | Select-Object -First 1
if (-not $package) { throw "no .msix/.msixupload produced under $staging" }
$name = 'FestivalScoreTracker_{0}_x64{1}' -f $Version, $package.Extension
$final = Join-Path $OutDir $name
Copy-Item $package.FullName $final -Force
[ordered]@{ version = $Version; sha = $sha; placeholder = $placeholder; package = $name } |
    ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $OutDir 'build.json')
Remove-Item -Recurse -Force $staging
'MSIX {0} ({1:N1} MB){2}: {3}' -f $Version, ((Get-Item $final).Length / 1MB), $(if ($placeholder) { ' [placeholder identity]' } else { '' }), $final
