using System.Runtime.InteropServices;
using Microsoft.UI.Dispatching;

namespace Festival.App.Services;

#region Occlusion tracker
/// <summary>
/// Reports when the main window cannot be seen although it is not minimized: fully covered by opaque windows above it,
/// cloaked (another virtual desktop), the session locked, or the console display off. Event-driven, like Chromium's
/// native window occlusion tracker: out-of-context WinEvent hooks (foreground, show/hide, move/size, minimize, cloak)
/// schedule one debounced Z-order walk on the UI thread, so nothing runs while the desktop is idle.
/// </summary>
internal sealed unsafe partial class OcclusionTracker : IDisposable
{
    #region Fields
    private static readonly TimeSpan Debounce = TimeSpan.FromMilliseconds(150);
    private static OcclusionTracker? instance;
    private static Guid consoleDisplayState = new(0x6FE69556, 0x704A, 0x47A0, 0x8F, 0x24, 0xC2, 0x8D, 0x93, 0x6F, 0xDA, 0x47);
    private readonly nint hwnd;
    private readonly uint processId = (uint)Environment.ProcessId;
    private readonly DispatcherQueueTimer timer;
    private readonly List<nint> hooks = [];
    private readonly nint powerNotification;
    private bool covered;
    private bool cloaked;
    private bool locked;
    private bool displayOff;
    private bool disposed;
    #endregion

    /// <summary>Starts tracking a top-level window. Create on its UI thread (the hooks need its message loop).</summary>
    /// <param name="hwnd">Window handle.</param>
    /// <param name="queue">UI dispatcher queue.</param>
    public OcclusionTracker(nint hwnd, DispatcherQueue queue)
    {
        this.hwnd = hwnd;
        instance = this;
        timer = queue.CreateTimer();
        timer.Interval = Debounce;
        timer.IsRepeating = false;
        timer.Tick += (_, _) => Recompute();
        foreach (var (min, max) in HookedEvents)
        {
            var hook = SetWinEventHook(min, max, 0, (nint)(delegate* unmanaged<nint, uint, nint, int, int, uint, uint, void>)&OnWinEvent,
                0, 0, WinEventOutOfContext | WinEventSkipOwnProcess);
            if (hook != 0) hooks.Add(hook);
        }
        SetWindowSubclass(hwnd, &SubclassProc, SubclassId, 0);
        WTSRegisterSessionNotification(hwnd, NotifyForThisSession);
        fixed (Guid* guid = &consoleDisplayState) powerNotification = RegisterPowerSettingNotification(hwnd, guid, DeviceNotifyWindowHandle);
        Recompute();
    }

    /// <summary>Raised on the UI thread when <see cref="IsHidden"/> changes.</summary>
    public event EventHandler? Changed;

    /// <summary>Whether the window is shown but nobody can see it.</summary>
    public bool IsHidden => covered || cloaked || locked || displayOff;

    /// <summary>Human-readable reason for diagnostics (<c>covered</c>, <c>cloaked</c>, <c>locked</c>, <c>display-off</c> or <c>visible</c>).</summary>
    public string Reason => covered ? "covered" : cloaked ? "cloaked" : locked ? "locked" : displayOff ? "display-off" : "visible";

    /// <summary>Schedules a re-check (own activation, move, resize or Z-order change, which the hooks skip).</summary>
    public void Invalidate()
    {
        if (!disposed && !timer.IsRunning) timer.Start();
    }

    /// <inheritdoc />
    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        timer.Stop();
        foreach (var hook in hooks) UnhookWinEvent(hook);
        hooks.Clear();
        RemoveWindowSubclass(hwnd, &SubclassProc, SubclassId);
        WTSUnRegisterSessionNotification(hwnd);
        if (powerNotification != 0) UnregisterPowerSettingNotification(powerNotification);
        if (ReferenceEquals(instance, this)) instance = null;
    }

    #region Evaluation
    /// <summary>Walks the windows above this one and updates the covered/cloaked state.</summary>
    private void Recompute()
    {
        if (disposed) return;
        var wasHidden = IsHidden;
        cloaked = IsCloaked(hwnd);
        covered = !cloaked && IsWindowVisible(hwnd) && !IsIconic(hwnd) && ComputeCovered();
        if (wasHidden != IsHidden)
        {
            PerfLog.Event("occlusion-" + Reason);
            Changed?.Invoke(this, EventArgs.Empty);
        }
    }

    /// <summary>Whether opaque windows above this one cover its on-screen frame.</summary>
    /// <returns><see langword="true"/> when fully covered.</returns>
    private bool ComputeCovered()
    {
        var target = VisibleBounds(hwnd).Intersect(VirtualScreen());
        if (target.IsEmpty) return false;
        var above = new List<WindowSnapshot>();
        var count = 0;
        for (var other = GetWindow(hwnd, GwHwndPrev); other != 0 && count < 4096; other = GetWindow(other, GwHwndPrev), count++)
        {
            if (!IsWindowVisible(other) || IsIconic(other)) continue;
            GetWindowThreadProcessId(other, out var owner);
            if (owner == processId) continue;
            var bounds = VisibleBounds(other);
            if (bounds.Intersect(target).IsEmpty) continue;
            above.Add(Snapshot(other, bounds));
        }
        return WindowOcclusion.IsOccluded(target, above);
    }

    /// <summary>Reads the occlusion-relevant attributes of a visible, overlapping window.</summary>
    /// <param name="window">Handle.</param>
    /// <param name="bounds">Its visible frame.</param>
    /// <returns>Snapshot.</returns>
    private static WindowSnapshot Snapshot(nint window, PixelRect bounds)
    {
        var exStyle = (long)GetWindowLongPtrW(window, GwlExStyle);
        var layered = (exStyle & WsExLayered) != 0;
        var layeredOpaque = false;
        if (layered && GetLayeredWindowAttributes(window, out _, out var alpha, out var flags))
            layeredOpaque = (flags & LwaColorKey) == 0 && ((flags & LwaAlpha) == 0 || alpha == 255);
        return new WindowSnapshot(bounds, Cloaked: IsCloaked(window), ClickThrough: (exStyle & WsExTransparent) != 0,
            Layered: layered, LayeredOpaque: layeredOpaque, HasRegion: GetWindowRgnBox(window, out _) != 0);
    }
    #endregion

    #region Callbacks
    /// <summary>WinEvent hook: schedules a re-check for top-level window events.</summary>
    [UnmanagedCallersOnly]
    private static void OnWinEvent(nint hook, uint eventType, nint window, int objectId, int childId, uint thread, uint time)
    {
        if (window == 0 || objectId != ObjIdWindow || childId != ChildIdSelf) return;
        if (eventType == EventObjectLocationChange && GetAncestor(window, GaRoot) != window) return;
        instance?.Invalidate();
    }

    /// <summary>Window subclass: session lock/unlock and console display on/off.</summary>
    [UnmanagedCallersOnly]
    private static nint SubclassProc(nint window, uint message, nint wParam, nint lParam, nuint id, nuint data)
    {
        if (instance is { } tracker)
        {
            if (message == WmWtsSessionChange && wParam is WtsSessionLock or WtsSessionUnlock)
                tracker.SetFlag(ref tracker.locked, wParam == WtsSessionLock);
            else if (message == WmPowerBroadcast && wParam == PbtPowerSettingChange && lParam != 0)
            {
                var setting = (PowerBroadcastSetting*)lParam;
                if (setting->PowerSetting == consoleDisplayState && setting->DataLength >= 4)
                    tracker.SetFlag(ref tracker.displayOff, setting->Data == 0);
            }
        }
        return DefSubclassProc(window, message, wParam, lParam);
    }

    /// <summary>Updates a session/power flag and notifies on a visibility change.</summary>
    /// <param name="flag">Field.</param>
    /// <param name="value">New value.</param>
    private void SetFlag(ref bool flag, bool value)
    {
        if (flag == value) return;
        var wasHidden = IsHidden;
        flag = value;
        if (wasHidden == IsHidden) return;
        PerfLog.Event("occlusion-" + Reason);
        Changed?.Invoke(this, EventArgs.Empty);
    }
    #endregion

    #region Win32
    private const uint WinEventOutOfContext = 0x0000;
    private const uint WinEventSkipOwnProcess = 0x0002;
    private const uint EventObjectLocationChange = 0x800B;
    private const int ObjIdWindow = 0;
    private const int ChildIdSelf = 0;
    private const uint GaRoot = 2;
    private const uint GwHwndPrev = 3;
    private const int GwlExStyle = -20;
    private const long WsExTransparent = 0x20;
    private const long WsExLayered = 0x80000;
    private const uint LwaColorKey = 0x1;
    private const uint LwaAlpha = 0x2;
    private const uint DwmwaExtendedFrameBounds = 9;
    private const uint DwmwaCloaked = 14;
    private const uint WmWtsSessionChange = 0x02B1;
    private const uint WmPowerBroadcast = 0x0218;
    private const nint PbtPowerSettingChange = 0x8013;
    private const nint WtsSessionLock = 7;
    private const nint WtsSessionUnlock = 8;
    private const uint NotifyForThisSession = 0;
    private const uint DeviceNotifyWindowHandle = 0;
    private const nuint SubclassId = 0x0F57;

    /// <summary>Hooked event ranges: foreground; move/size end; minimize start/end; show/hide; location; cloak/uncloak.</summary>
    private static readonly (uint Min, uint Max)[] HookedEvents =
        [(0x0003, 0x0003), (0x000B, 0x000B), (0x0016, 0x0017), (0x8002, 0x8003), (EventObjectLocationChange, EventObjectLocationChange), (0x8017, 0x8018)];

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    private struct PowerBroadcastSetting { public Guid PowerSetting; public uint DataLength; public uint Data; }

    /// <summary>Visible frame (DWM extended frame bounds; the window rectangle when DWM has none).</summary>
    private static PixelRect VisibleBounds(nint window)
    {
        Rect r;
        if (DwmGetWindowAttribute(window, DwmwaExtendedFrameBounds, &r, (uint)sizeof(Rect)) != 0) GetWindowRect(window, out r);
        return new PixelRect(r.Left, r.Top, r.Right, r.Bottom);
    }

    /// <summary>Bounding box of all monitors.</summary>
    private static PixelRect VirtualScreen()
    {
        var x = GetSystemMetrics(76);
        var y = GetSystemMetrics(77);
        return new PixelRect(x, y, x + GetSystemMetrics(78), y + GetSystemMetrics(79));
    }

    /// <summary>Whether DWM cloaks a window.</summary>
    private static bool IsCloaked(nint window)
    {
        uint value = 0;
        return DwmGetWindowAttribute(window, DwmwaCloaked, &value, sizeof(uint)) == 0 && value != 0;
    }

    [LibraryImport("user32.dll")]
    private static partial nint SetWinEventHook(uint eventMin, uint eventMax, nint module, nint callback, uint processId, uint threadId, uint flags);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool UnhookWinEvent(nint hook);

    [LibraryImport("user32.dll")]
    private static partial nint GetWindow(nint window, uint command);

    [LibraryImport("user32.dll")]
    private static partial nint GetAncestor(nint window, uint flags);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool IsWindowVisible(nint window);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool IsIconic(nint window);

    [LibraryImport("user32.dll")]
    private static partial nint GetWindowLongPtrW(nint window, int index);

    [LibraryImport("user32.dll")]
    private static partial uint GetWindowThreadProcessId(nint window, out uint processId);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetLayeredWindowAttributes(nint window, out uint colorKey, out byte alpha, out uint flags);

    [LibraryImport("user32.dll")]
    private static partial int GetWindowRgnBox(nint window, out Rect box);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetWindowRect(nint window, out Rect rect);

    [LibraryImport("user32.dll")]
    private static partial int GetSystemMetrics(int index);

    [LibraryImport("user32.dll")]
    private static partial nint RegisterPowerSettingNotification(nint recipient, Guid* setting, uint flags);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool UnregisterPowerSettingNotification(nint handle);

    [LibraryImport("dwmapi.dll")]
    private static partial int DwmGetWindowAttribute(nint window, uint attribute, void* value, uint size);

    [LibraryImport("comctl32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool SetWindowSubclass(nint window, delegate* unmanaged<nint, uint, nint, nint, nuint, nuint, nint> proc, nuint id, nuint data);

    [LibraryImport("comctl32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool RemoveWindowSubclass(nint window, delegate* unmanaged<nint, uint, nint, nint, nuint, nuint, nint> proc, nuint id);

    [LibraryImport("comctl32.dll")]
    private static partial nint DefSubclassProc(nint window, uint message, nint wParam, nint lParam);

    [LibraryImport("wtsapi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool WTSRegisterSessionNotification(nint window, uint flags);

    [LibraryImport("wtsapi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool WTSUnRegisterSessionNotification(nint window);
    #endregion
}
#endregion
