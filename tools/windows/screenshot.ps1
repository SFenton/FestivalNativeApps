<#
.SYNOPSIS
    Captures the app window to a PNG, downscaling until it is under a size budget.
.DESCRIPTION
    Runs in the desktop session: PrintWindow(PW_RENDERFULLCONTENT) captures the DirectComposition content
    even when the window is partly covered. Optionally launches the app first (same parameters as
    launch.ps1) and waits -Delay seconds for content to settle.
.PARAMETER Out Output PNG path.
.PARAMETER MaxKB Size budget; the image is downscaled in 10% steps until it fits (default 300 KB).
.PARAMETER Delay Seconds to wait after launch before capturing.
.PARAMETER Launch Launch first with -Tab/-Route/-Configuration/-Aot/-Fixture/-ExtraArgs.
.EXAMPLE
    pwsh tools/windows/screenshot.ps1 -Launch -Tab songs -Out windows/reports/screenshots/songs.png
#>
param(
    [Parameter(Mandatory)][string]$Out,
    [int]$MaxKB = 300,
    [int]$Delay = 6,
    [switch]$Launch,
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

if ($Launch) {
    & (Join-Path $PSScriptRoot 'launch.ps1') -Configuration $Configuration -Aot:$Aot -Tab $Tab -Route $Route -Fixture:$Fixture -Width $Width -Height $Height -ExtraArgs $ExtraArgs | Out-Host
    Start-Sleep -Seconds $Delay
}
if (-not (Get-AppProcess)) { throw 'The app is not running; pass -Launch.' }
$target = [IO.Path]::GetFullPath($Out)
New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null

$capture = @"
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class Cap {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out RECT r, int size);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
'@
[Cap]::SetProcessDPIAware() | Out-Null
$FindWindowSnippet
`$h = [IntPtr]`$hwnd
`$w = New-Object Cap+RECT; [Cap]::GetWindowRect(`$h, [ref]`$w) | Out-Null
`$f = New-Object Cap+RECT; [Cap]::DwmGetWindowAttribute(`$h, 9, [ref]`$f, 16) | Out-Null
`$bmp = New-Object System.Drawing.Bitmap (`$w.Right - `$w.Left), (`$w.Bottom - `$w.Top)
`$g = [System.Drawing.Graphics]::FromImage(`$bmp); `$dc = `$g.GetHdc()
[Cap]::PrintWindow(`$h, `$dc, 2) | Out-Null
`$g.ReleaseHdc(`$dc); `$g.Dispose()
# Crop the invisible resize border to the DWM frame bounds.
`$crop = New-Object System.Drawing.Rectangle (`$f.Left - `$w.Left), (`$f.Top - `$w.Top), (`$f.Right - `$f.Left), (`$f.Bottom - `$f.Top)
`$crop.Intersect((New-Object System.Drawing.Rectangle 0, 0, `$bmp.Width, `$bmp.Height))
`$full = `$bmp.Clone(`$crop, `$bmp.PixelFormat); `$bmp.Dispose()
`$scale = 1.0
do {
    `$wd = [int](`$full.Width * `$scale); `$ht = [int](`$full.Height * `$scale)
    `$img = New-Object System.Drawing.Bitmap `$wd, `$ht
    `$gg = [System.Drawing.Graphics]::FromImage(`$img)
    `$gg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    `$gg.DrawImage(`$full, 0, 0, `$wd, `$ht); `$gg.Dispose()
    `$img.Save('$target', [System.Drawing.Imaging.ImageFormat]::Png); `$img.Dispose()
    `$kb = (Get-Item '$target').Length / 1KB
    `$scale -= 0.1
} while (`$kb -gt $MaxKB -and `$scale -gt 0.25)
"{0}x{1} {2:N0} KB" -f `$wd, `$ht, `$kb
"@
$result = Invoke-InDesktopSession -Script $capture -TimeoutSeconds 60
"Saved $target ($($result.Trim()))"
