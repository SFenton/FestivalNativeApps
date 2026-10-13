using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Metadata pill
/// <summary>
/// One metadata pill host (score text, accuracy box, stars, intensity meter, and the shared season and percentile pills
/// from <see cref="MetadataPills"/>). UI Automation sees exactly one
/// raw-view element per pill, named with the field's spoken text and carrying its test ID; the
/// inner text, stars and meter are decoration of that element, so a row never exposes extra stops for Narrator (the row's
/// list item already speaks every field).
/// </summary>
public sealed partial class MetadataPill : Grid
{
    private Action<MetadataPill>? restyle;

    /// <summary>Control type the peer reports: <see cref="AutomationControlType.Text"/> or an image (stars, meter).</summary>
    public AutomationControlType ControlType { get; set; } = AutomationControlType.Text;

    /// <summary>
    /// Re-applies the pill's code-set brushes. Set by <see cref="MetadataPills"/>: it runs now and again on the UI thread
    /// whenever the contrast theme changes while the pill is loaded (inline brush assignments do not follow
    /// <c>{ThemeResource}</c>; theme-accessibility).
    /// </summary>
    public Action<MetadataPill>? Restyle
    {
        get => restyle;
        set
        {
            if (restyle is null && value is not null)
            {
                Loaded += OnLoaded;
                Unloaded += OnUnloaded;
                if (IsLoaded)
                {
                    Services.ContrastTheme.Changed -= OnColorsChanged;
                    Services.ContrastTheme.Changed += OnColorsChanged;
                }
            }
            restyle = value;
            restyle?.Invoke(this);
        }
    }

    /// <summary>Follows contrast-theme changes while loaded.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        Services.ContrastTheme.Changed -= OnColorsChanged;
        Services.ContrastTheme.Changed += OnColorsChanged;
        restyle?.Invoke(this);
    }

    /// <summary>Stops following contrast-theme changes, so a recycled row's pill is not kept alive.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private void OnUnloaded(object sender, RoutedEventArgs e) => Services.ContrastTheme.Changed -= OnColorsChanged;

    /// <summary>Restyles on the UI thread after a system colour change.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private void OnColorsChanged(object? sender, EventArgs e) => DispatcherQueue?.TryEnqueue(() => restyle?.Invoke(this));

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
