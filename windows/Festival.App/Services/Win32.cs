using System.Runtime.InteropServices;

namespace Festival.App.Services;

#region Win32
/// <summary>Minimal Win32 interop.</summary>
internal static partial class Win32
{
    /// <summary>DPI of the monitor hosting a window.</summary>
    /// <param name="hwnd">Window handle.</param>
    /// <returns>DPI (96 = 100%).</returns>
    [LibraryImport("user32.dll")]
    internal static partial uint GetDpiForWindow(nint hwnd);
}
#endregion
