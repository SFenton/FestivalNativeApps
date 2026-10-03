// Keyboard input for a locked console session. While Windows is locked, SendInput (FlaUI's Keyboard) types into the
// lock screen, but WinUI still processes key messages posted to the app's XAML input-site window, so Tab walks and
// keyboard journeys keep working. Modifiers are applied through the target thread's shared key state.

using System.Runtime.InteropServices;
using System.Text;
using FlaUI.Core.WindowsAPI;

namespace FstUia;

/// <summary>Posted keyboard input for a target window (used automatically while the session is locked).</summary>
internal static class PostedInput
{
    #region Session state

    /// <summary>
    /// Whether the session is locked (the lock screen runs on the <c>Default</c> desktop, so the session lock flag is
    /// checked first) or the interactive desktop is not the user's <c>Default</c> desktop (secure desktop), where real
    /// input would never reach the app.
    /// </summary>
    /// <returns><see langword="true"/> when the session is locked.</returns>
    public static bool IsSessionLocked()
    {
        if (SessionLockFlag() == WtsSessionStateLock) return true;
        var desktop = OpenInputDesktop(0, false, DesktopReadObjects);
        if (desktop == IntPtr.Zero) return true;
        try
        {
            var name = new StringBuilder(256);
            return !GetUserObjectInformationW(desktop, UoiName, name, name.Capacity * 2, out _)
                || !name.ToString().Equals("Default", StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            CloseDesktop(desktop);
        }
    }

    /// <summary>The current session's <c>WTSINFOEX_LEVEL1.SessionFlags</c> (0 locked, 1 unlocked, -1 unknown).</summary>
    private static int SessionLockFlag()
    {
        if (!WTSQuerySessionInformationW(IntPtr.Zero, -1, WtsSessionInfoEx, out var buffer, out _)) return -1;
        try
        {
            // WTSINFOEXW: DWORD Level, then the 8-aligned union WTSINFOEX_LEVEL1 (SessionId, SessionState, SessionFlags).
            return Marshal.ReadInt32(buffer) == 1 ? Marshal.ReadInt32(buffer, 16) : -1;
        }
        finally
        {
            WTSFreeMemory(buffer);
        }
    }

    #endregion

    #region Keys

    /// <summary>
    /// Presses a key chord in the window: modifiers go down (posted and in the shared key state), each other key is
    /// posted down then up, then the modifiers are released.
    /// </summary>
    /// <param name="topLevel">Target top-level window.</param>
    /// <param name="keys">Chord, e.g. <c>SHIFT, TAB</c>.</param>
    /// <exception cref="InvalidOperationException">The window has no XAML input site.</exception>
    public static void Press(IntPtr topLevel, IReadOnlyList<VirtualKeyShort> keys)
    {
        var site = InputSite(topLevel) ?? throw new InvalidOperationException("no InputSiteWindowClass child to post keys to");
        var modifiers = keys.Where(IsModifier).ToList();
        var others = keys.Where(k => !IsModifier(k)).ToList();
        var alt = modifiers.Contains(VirtualKeyShort.ALT);
        var me = GetCurrentThreadId();
        var target = GetWindowThreadProcessId(site, out _);
        var attached = target != me && AttachThreadInput(me, target, true);
        var state = new byte[256];
        try
        {
            GetKeyboardState(state);
            var pressed = (byte[])state.Clone();
            foreach (var modifier in modifiers)
            {
                pressed[(int)modifier] = 0x80;
                PostKey(site, modifier, down: true, alt);
            }
            SetKeyboardState(pressed);
            foreach (var key in others)
            {
                PostKey(site, key, down: true, alt);
                PostKey(site, key, down: false, alt);
            }
            foreach (var modifier in Enumerable.Reverse(modifiers)) PostKey(site, modifier, down: false, alt && modifier != VirtualKeyShort.ALT);
            Thread.Sleep(120); // let the app read the messages while the shared key state still holds the modifiers
        }
        finally
        {
            SetKeyboardState(state);
            if (attached) AttachThreadInput(me, target, false);
        }
    }

    /// <summary>Types text as posted characters.</summary>
    /// <param name="topLevel">Target top-level window.</param>
    /// <param name="text">Text.</param>
    public static void Type(IntPtr topLevel, string text)
    {
        var site = InputSite(topLevel) ?? throw new InvalidOperationException("no InputSiteWindowClass child to post keys to");
        foreach (var ch in text) PostMessageW(site, WmChar, (IntPtr)ch, (IntPtr)1);
    }

    private static bool IsModifier(VirtualKeyShort key) =>
        key is VirtualKeyShort.SHIFT or VirtualKeyShort.CONTROL or VirtualKeyShort.ALT or VirtualKeyShort.LWIN;

    private static void PostKey(IntPtr site, VirtualKeyShort key, bool down, bool alt)
    {
        var scan = MapVirtualKeyW((uint)key, 0);
        long lParam = 1 | ((long)scan << 16);
        if (IsExtended(key)) lParam |= 1L << 24;
        if (alt) lParam |= 1L << 29;
        if (!down) lParam |= (1L << 30) | (1L << 31);
        var message = alt ? (down ? WmSysKeyDown : WmSysKeyUp) : (down ? WmKeyDown : WmKeyUp);
        PostMessageW(site, message, (IntPtr)(int)key, (IntPtr)lParam);
    }

    private static bool IsExtended(VirtualKeyShort key) => key is VirtualKeyShort.LEFT or VirtualKeyShort.RIGHT
        or VirtualKeyShort.UP or VirtualKeyShort.DOWN or VirtualKeyShort.HOME or VirtualKeyShort.END
        or VirtualKeyShort.PRIOR or VirtualKeyShort.NEXT or VirtualKeyShort.INSERT or VirtualKeyShort.DELETE;

    /// <summary>The first XAML input-site child of a top-level window.</summary>
    private static IntPtr? InputSite(IntPtr topLevel)
    {
        IntPtr? found = null;
        EnumChildWindows(topLevel, (hwnd, _) =>
        {
            var name = new StringBuilder(64);
            GetClassNameW(hwnd, name, name.Capacity);
            if (name.ToString() != "InputSiteWindowClass") return true;
            found = hwnd;
            return false;
        }, IntPtr.Zero);
        return found;
    }

    #endregion

    #region Interop

    private const uint DesktopReadObjects = 0x0001;
    private const int UoiName = 2;
    private const uint WmKeyDown = 0x0100, WmKeyUp = 0x0101, WmChar = 0x0102, WmSysKeyDown = 0x0104, WmSysKeyUp = 0x0105;

    private const int WtsSessionInfoEx = 25, WtsSessionStateLock = 0;

    private delegate bool EnumProc(IntPtr hwnd, IntPtr data);

    [DllImport("wtsapi32.dll", SetLastError = true)]
    private static extern bool WTSQuerySessionInformationW(IntPtr server, int sessionId, int infoClass, out IntPtr buffer, out int bytes);
    [DllImport("wtsapi32.dll")] private static extern void WTSFreeMemory(IntPtr memory);

    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
    [DllImport("user32.dll")] private static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool GetUserObjectInformationW(IntPtr handle, int index, StringBuilder info, int length, out int needed);
    [DllImport("user32.dll")] private static extern bool EnumChildWindows(IntPtr parent, EnumProc callback, IntPtr data);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassNameW(IntPtr hwnd, StringBuilder name, int max);
    [DllImport("user32.dll")] private static extern bool PostMessageW(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] private static extern uint MapVirtualKeyW(uint code, uint mapType);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] private static extern bool AttachThreadInput(uint attach, uint to, bool doAttach);
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] private static extern bool GetKeyboardState(byte[] state);
    [DllImport("user32.dll")] private static extern bool SetKeyboardState(byte[] state);

    #endregion
}
