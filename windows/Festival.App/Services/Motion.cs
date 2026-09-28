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

    /// <summary>Raised on the UI thread when <see cref="Allowed"/> or <see cref="Paused"/> may have changed.</summary>
    public static event EventHandler? Changed;

    /// <summary>Whether decorative motion may run now.</summary>
    public static bool Allowed => MotionSwitch.Allowed(
        SystemSettings.AnimationsEnabled, App.Session.Settings.ReduceMotion, App.Options.ReduceMotion);

    /// <summary>Whether looping motion should hold still because nobody can see the window.</summary>
    public static bool Paused => paused;

    /// <summary>Records the window's visibility and the current settings (called by the shell's backdrop policy).</summary>
    /// <param name="hidden">Minimized, covered, cloaked, locked or display off.</param>
    public static void Update(bool hidden)
    {
        paused = hidden;
        Changed?.Invoke(null, EventArgs.Empty);
    }
}
#endregion
