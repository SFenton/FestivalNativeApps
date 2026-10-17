using System.Runtime.InteropServices;

namespace Festival.App.Services;

#region Win32
/// <summary>Minimal Win32 interop.</summary>
internal static partial class Win32
{
    /// <summary>Keeps the display on (with <see cref="ExecutionContinuous"/>) for measurement runs.</summary>
    internal const uint ExecutionDisplayRequired = 0x00000002;

    /// <summary>Keeps the system awake.</summary>
    internal const uint ExecutionSystemRequired = 0x00000001;

    /// <summary>Makes the execution state persist until the next call with this flag alone.</summary>
    internal const uint ExecutionContinuous = 0x80000000;

    /// <summary>DPI of the monitor hosting a window.</summary>
    /// <param name="hwnd">Window handle.</param>
    /// <returns>DPI (96 = 100%).</returns>
    [LibraryImport("user32.dll")]
    internal static partial uint GetDpiForWindow(nint hwnd);

    /// <summary>Window that currently receives keyboard input.</summary>
    /// <returns>Window handle, or 0.</returns>
    [LibraryImport("user32.dll")]
    internal static partial nint GetForegroundWindow();

    /// <summary>Tells the power manager the thread needs the system and/or display on.</summary>
    /// <param name="flags">Combination of the <c>Execution*</c> flags.</param>
    /// <returns>The previous state, or 0 on failure.</returns>
    [LibraryImport("kernel32.dll")]
    internal static partial uint SetThreadExecutionState(uint flags);
}
#endregion
