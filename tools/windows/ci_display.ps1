<#
.SYNOPSIS
    Sets the CI runner's primary display resolution (windows-ui job only).
.DESCRIPTION
    Hosted windows-latest runners start at 1024x768, which cannot hold the compact (500x800 epx) journey window.
    Changes the primary display mode with ChangeDisplaySettings (current user, not persisted to the registry) and
    prints the resulting mode. Never run this on a lane host: it would change the operator's desktop.
.PARAMETER Width Horizontal pixels.
.PARAMETER Height Vertical pixels.
.EXAMPLE
    pwsh tools/windows/ci_display.ps1 -Width 1920 -Height 1080
#>
param([int]$Width = 1920, [int]$Height = 1080)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $env:GITHUB_ACTIONS) { throw 'ci_display.ps1 changes the desktop resolution; it runs only in GitHub Actions.' }

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class FstDisplay
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODE
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
        public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool EnumDisplaySettings(string device, int mode, ref DEVMODE devMode);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int ChangeDisplaySettings(ref DEVMODE devMode, int flags);

    public static string Current()
    {
        var mode = new DEVMODE { dmSize = (short)Marshal.SizeOf<DEVMODE>() };
        EnumDisplaySettings(null, -1, ref mode);
        return mode.dmPelsWidth + "x" + mode.dmPelsHeight;
    }

    public static int Set(int width, int height)
    {
        var mode = new DEVMODE { dmSize = (short)Marshal.SizeOf<DEVMODE>() };
        if (!EnumDisplaySettings(null, -1, ref mode)) return -100;
        mode.dmPelsWidth = width;
        mode.dmPelsHeight = height;
        mode.dmFields = 0x80000 | 0x100000;  // DM_PELSWIDTH | DM_PELSHEIGHT
        return ChangeDisplaySettings(ref mode, 0);
    }
}
'@

"display before: $([FstDisplay]::Current())"
$code = [FstDisplay]::Set($Width, $Height)
"ChangeDisplaySettings: $code (0 = changed)"
"display after: $([FstDisplay]::Current())"
if ($code -ne 0) { throw "could not set ${Width}x${Height} (code $code)" }
