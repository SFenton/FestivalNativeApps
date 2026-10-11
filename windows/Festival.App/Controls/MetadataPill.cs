using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Metadata pill
/// <summary>
/// One Songs-row metadata pill host (score text, accuracy box, stars, intensity meter, …). UI Automation sees exactly one
/// raw-view element per pill, named with the field's spoken text and carrying its <c>fst.songs.metadata.*</c> ID; the
/// inner text, stars and meter are decoration of that element, so a row never exposes extra stops for Narrator (the row's
/// list item already speaks every field).
/// A season or percentile pill (<see cref="MetadataPills"/>) also remembers its theme roles and re-resolves them when the
/// Windows contrast theme changes while it is on screen (pattern <c>metadata-pills</c>, design/windows.md contrast
/// themes): its brushes are assigned in code and its label opts out of the automatic High Contrast backplate, so nothing
/// else would repaint it.
/// </summary>
public sealed partial class MetadataPill : Grid
{
    private MetadataPillLook? look;
    private bool listening;

    /// <summary>Creates a pill; it listens for contrast-theme changes only while loaded and styled with a look.</summary>
    public MetadataPill()
    {
        Loaded += (_, _) =>
        {
            Listen(look is not null);
            // A theme switch while the pill was off screen (a recycled or cached row) left stale brushes.
            PaintLook();
        };
        Unloaded += (_, _) => Listen(false);
    }

    /// <summary>Control type the peer reports: <see cref="AutomationControlType.Text"/> or an image (stars, meter).</summary>
    public AutomationControlType ControlType { get; set; } = AutomationControlType.Text;

    /// <summary>The theme roles last applied through <see cref="ApplyLook"/>, or <see langword="null"/> for other pills.</summary>
    public MetadataPillLook? Look => look;

    /// <summary>
    /// Paints the pill's fill, stroke and label (its first child, a <see cref="TextBlock"/>) with the look's role brushes and
    /// keeps them current across contrast-theme switches.
    /// </summary>
    /// <param name="value">Theme roles.</param>
    public void ApplyLook(MetadataPillLook value)
    {
        look = value;
        PaintLook();
        if (IsLoaded) Listen(true);
    }

    /// <summary>Resolves the stored look's role brushes for the current theme.</summary>
    private void PaintLook()
    {
        if (look is null) return;
        Background = Services.ContrastTheme.Brush(look.FillKey);
        BorderBrush = Services.ContrastTheme.Brush(look.StrokeKey);
        if (Children.Count > 0 && Children[0] is TextBlock label) label.Foreground = Services.ContrastTheme.Brush(look.TextKey);
    }

    /// <summary>Subscribes to or unsubscribes from <see cref="Services.ContrastTheme.Changed"/> once.</summary>
    /// <param name="on">Whether to listen.</param>
    private void Listen(bool on)
    {
        if (on == listening) return;
        listening = on;
        if (on) Services.ContrastTheme.Changed += OnColorsChanged;
        else Services.ContrastTheme.Changed -= OnColorsChanged;
    }

    /// <summary>Re-resolves the role brushes on the UI thread after a system colour change (raised off the UI thread).</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private void OnColorsChanged(object? sender, EventArgs e) => DispatcherQueue?.TryEnqueue(PaintLook);

    /// <summary>Names the pill for UI Automation and keeps it in the raw view (the row item speaks every field).</summary>
    /// <param name="name">Spoken text.</param>
    /// <param name="automationId">Test ID, or <see langword="null"/>.</param>
    public void Label(string name, string? automationId)
    {
        AutomationProperties.SetName(this, name);
        if (automationId is not null) AutomationProperties.SetAutomationId(this, automationId);
        AutomationProperties.SetAccessibilityView(this, AccessibilityView.Raw);
    }

    /// <summary>Exposes the pill as one element with no children (a bare panel has no automation peer).</summary>
    /// <returns>Automation peer.</returns>
    protected override AutomationPeer OnCreateAutomationPeer() => new MetadataPillPeer(this);

    /// <summary>Text- or image-typed peer with no children.</summary>
    /// <param name="owner">Pill.</param>
    private sealed partial class MetadataPillPeer(MetadataPill owner) : FrameworkElementAutomationPeer(owner)
    {
        /// <inheritdoc />
        protected override AutomationControlType GetAutomationControlTypeCore() => owner.ControlType;

        /// <inheritdoc />
        protected override string GetClassNameCore() => nameof(MetadataPill);

        /// <inheritdoc />
        protected override IList<AutomationPeer>? GetChildrenCore() => null;
    }
}
#endregion
