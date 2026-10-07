using System.ComponentModel;

namespace Festival.App;

#region Route policy and window title
/// <summary>Anonymous redirects after deselection and the page-specific window title.</summary>
public sealed partial class MainWindow
{
    /// <summary>Top route of the visible section's stack (<see langword="null"/> at its root).</summary>
    private AppRoute? CurrentRoute =>
        frames.TryGetValue(current, out var frame) && routeStacks.TryGetValue(frame, out var stack) ? stack.Peek() : null;

    /// <summary>Wires the policy (called once from the constructor).</summary>
    private void InitializeRoutePolicy() => session.PropertyChanged += OnRoutePolicySessionChanged;

    /// <summary>Sets "Festival Score Tracker - &lt;page&gt;" for the taskbar and Alt+Tab (the title-bar caption stays the brand).</summary>
    private void UpdateWindowTitle() => Title = WindowTitles.For(current, CurrentRoute);

    /// <summary>
    /// Deselecting on a player-only page (e.g. Statistics) redirects to Songs, as the web's guards re-render; Player History
    /// stays and shows its no-player state.
    /// </summary>
    /// <param name="sender">Session.</param>
    /// <param name="e">Changed property.</param>
    private void OnRoutePolicySessionChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(FestivalSession.Settings) || session.HasPlayer) return;
        if (CurrentRoute is { } route && AppRouteParser.RequiresPlayer(route)) ShowSongsRoot();
    }
}
#endregion
