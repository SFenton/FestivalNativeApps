// Display scaling ("Scale" in Settings → System → Display) of the primary display, for the accessibility matrix's
// 100%/150% configurations. Windows exposes no public setter: Settings uses DisplayConfigSetDeviceInfo with the
// undocumented DISPLAYCONFIG_DEVICE_INFO_GET/SET_DPI_SCALE types (-3/-4), whose value is a step offset from the
// display's recommended scale. uiwin.py only applies it inside the desktop lock and restores the previous value.

using System.Runtime.InteropServices;

namespace FstUia;

/// <summary>Reads and sets the primary display's scale percentage.</summary>
internal static class DisplayScale
{
    /// <summary>The scale steps Settings offers, in order; the device-info value indexes them relative to the recommended one.</summary>
    private static readonly int[] Steps = [100, 125, 150, 175, 200, 225, 250, 300, 350, 400, 450, 500];

    /// <summary>The primary display's scale, or <see langword="null"/> when it cannot be read.</summary>
    /// <returns>Percent.</returns>
    public static int? Get()
    {
        if (Query() is not { } dpi) return null;
        var index = -dpi.MinScaleRel + dpi.CurScaleRel;
        return index >= 0 && index < Steps.Length ? Steps[index] : null;
    }

    /// <summary>Sets the primary display's scale.</summary>
    /// <param name="percent">One of the Settings steps within the display's range.</param>
    /// <exception cref="ArgumentOutOfRangeException">Unknown or unsupported step.</exception>
    /// <exception cref="InvalidOperationException">The display configuration rejected the change.</exception>
    public static void Set(int percent)
    {
        var dpi = Query() ?? throw new InvalidOperationException("display scale is not readable");
        var index = Array.IndexOf(Steps, percent);
        var relative = index + dpi.MinScaleRel;
        if (index < 0 || relative < dpi.MinScaleRel || relative > dpi.MaxScaleRel)
            throw new ArgumentOutOfRangeException(nameof(percent), $"display_scale {percent} is outside this display's range");
        var set = new DpiSet
        {
            Header = new Header { Type = SetDpiScale, Size = Marshal.SizeOf<DpiSet>(), AdapterId = dpi.Header.AdapterId, Id = dpi.Header.Id },
            ScaleRel = relative,
        };
        var status = DisplayConfigSetDeviceInfo(ref set);
        if (status != 0) throw new InvalidOperationException($"DisplayConfigSetDeviceInfo failed ({status})");
        Thread.Sleep(2500); // every window re-lays out for the new DPI
    }

    /// <summary>DPI device info of the first active path's source (the primary display on this host).</summary>
    private static DpiGet? Query()
    {
        if (GetDisplayConfigBufferSizes(QdcOnlyActivePaths, out var paths, out var modes) != 0 || paths == 0) return null;
        var pathBuffer = Marshal.AllocHGlobal((int)paths * PathInfoSize);
        var modeBuffer = Marshal.AllocHGlobal((int)modes * ModeInfoSize);
        try
        {
            if (QueryDisplayConfig(QdcOnlyActivePaths, ref paths, pathBuffer, ref modes, modeBuffer, IntPtr.Zero) != 0) return null;
            var get = new DpiGet
            {
                Header = new Header
                {
                    Type = GetDpiScale,
                    Size = Marshal.SizeOf<DpiGet>(),
                    AdapterId = Marshal.PtrToStructure<Luid>(pathBuffer),
                    Id = (uint)Marshal.ReadInt32(pathBuffer, 8),
                },
            };
            return DisplayConfigGetDeviceInfo(ref get) == 0 ? get : null;
        }
        finally
        {
            Marshal.FreeHGlobal(pathBuffer);
            Marshal.FreeHGlobal(modeBuffer);
        }
    }

    #region Interop

    private const uint QdcOnlyActivePaths = 0x2;
    private const int GetDpiScale = -3, SetDpiScale = -4;
    private const int PathInfoSize = 72, ModeInfoSize = 64;

    [StructLayout(LayoutKind.Sequential)]
    private struct Luid { public uint LowPart; public int HighPart; }

    [StructLayout(LayoutKind.Sequential)]
    private struct Header { public int Type; public int Size; public Luid AdapterId; public uint Id; }

    [StructLayout(LayoutKind.Sequential)]
    private struct DpiGet { public Header Header; public int MinScaleRel; public int CurScaleRel; public int MaxScaleRel; }

    [StructLayout(LayoutKind.Sequential)]
    private struct DpiSet { public Header Header; public int ScaleRel; }

    [DllImport("user32.dll")] private static extern int GetDisplayConfigBufferSizes(uint flags, out uint paths, out uint modes);
    [DllImport("user32.dll")] private static extern int QueryDisplayConfig(uint flags, ref uint paths, IntPtr pathInfo, ref uint modes, IntPtr modeInfo, IntPtr topology);
    [DllImport("user32.dll")] private static extern int DisplayConfigGetDeviceInfo(ref DpiGet info);
    [DllImport("user32.dll")] private static extern int DisplayConfigSetDeviceInfo(ref DpiSet info);

    #endregion
}
