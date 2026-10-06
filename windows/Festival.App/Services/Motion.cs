using Windows.UI.ViewManagement;

namespace Festival.App.Services;

#region Motion
/// <summary>
/// App-wide decorative-motion switch shared by fade-ins and the Item Shop pulse: off under Windows "Animation effects"
/// off, in-app Reduce Motion or <c>--reduce-motion</c>; looping motion also pauses while the window is minimized,
/// covered or otherwise hidden (the same signal that stills the artwork backdrop).
/// </summary>
public static class Motion
{
    private static readonly UISettings SystemSettings = new();
    private static bool paused;
    private static bool foreground = true;

    /// <summary>Raised on the UI thread when <see cref="Allowed"/>, <see cref="Paused"/> or <see cref="Foreground"/> may have changed.</summary>
    public static event EventHandler? Changed;

    /// <summary>Whether decorative motion may run now.</summary>
    public static bool Allowed => MotionSwitch.Allowed(
        SystemSettings.AnimationsEnabled, App.Session.Settings.ReduceMotion, App.Options.ReduceMotion);

    /// <summary>Whether looping motion should hold still because nobody can see the window.</summary>
    public static bool Paused => paused;

    /// <summary>
    /// Whether the main window is the activated (foreground) window. Only the first-run demos' data-swap rotation holds
    /// on it (issue #58: rotate only while the app is in the foreground; issue #258). Looping decorative motion (Shop
    /// pulses, marquees) follows <see cref="Paused"/> instead, like the artwork backdrop, so it keeps running in a window
    /// that is visible beside the active app.
    /// </summary>
    public static bool Foreground => foreground;

    /// <summary>Records the window's activation (called from the shell's <c>Window.Activated</c> handler).</summary>
    /// <param name="activated">Code- or pointer-activated; <see langword="false"/> when deactivated.</param>
    public static void UpdateForeground(bool activated)
    {
        if (foreground == activated) return;
        foreground = activated;
        Changed?.Invoke(null, EventArgs.Empty);
    }

    /// <summary>Records the window's visibility and the current settings (called by the shell's backdrop policy).</summary>
    /// <param name="hidden">Minimized, covered, cloaked, locked or display off.</param>
    public static void Update(bool hidden)
    {
        paused = hidden;
        Changed?.Invoke(null, EventArgs.Empty);
    }
}
#endregion
