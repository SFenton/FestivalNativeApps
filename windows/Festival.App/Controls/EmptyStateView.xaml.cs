using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Empty state view
/// <summary>
/// The one Windows empty state (empty-error-states R1/R2/R5, issue #377), after the web <c>EmptyState</c>: an optional
/// icon, a level-2 heading, a subtitle and an optional next-step action, centred horizontally and vertically in the
/// region the control fills. It never draws a card and never offers Reset Filters: a filter that hides everything is
/// changed from the page's own filter control. Failures use <see cref="ServiceStatusView"/>; loading uses a
/// <see cref="ProgressRing"/>.
/// </summary>
public sealed partial class EmptyStateView : UserControl
{
    /// <summary>Heading text.</summary>
    public static readonly DependencyProperty TitleProperty = DependencyProperty.Register(
        nameof(Title), typeof(string), typeof(EmptyStateView), new PropertyMetadata(null, OnContentChanged));

    /// <summary>Subtitle text; collapsed when empty.</summary>
    public static readonly DependencyProperty SubtitleProperty = DependencyProperty.Register(
        nameof(Subtitle), typeof(string), typeof(EmptyStateView), new PropertyMetadata(null, OnContentChanged));

    /// <summary>Segoe Fluent Icons glyph above the heading; none when empty.</summary>
    public static readonly DependencyProperty GlyphProperty = DependencyProperty.Register(
        nameof(Glyph), typeof(string), typeof(EmptyStateView), new PropertyMetadata(null, OnContentChanged));

    /// <summary>Optional next-step action (e.g. Select Player); never Reset Filters.</summary>
    public static readonly DependencyProperty ActionProperty = DependencyProperty.Register(
        nameof(Action), typeof(object), typeof(EmptyStateView), new PropertyMetadata(null, OnContentChanged));

    /// <summary>Automation ID of the heading (the state's spec test ID).</summary>
    public static readonly DependencyProperty TitleAutomationIdProperty = DependencyProperty.Register(
        nameof(TitleAutomationId), typeof(string), typeof(EmptyStateView), new PropertyMetadata(null, OnIdsChanged));

    /// <summary>Automation ID of the subtitle.</summary>
    public static readonly DependencyProperty SubtitleAutomationIdProperty = DependencyProperty.Register(
        nameof(SubtitleAutomationId), typeof(string), typeof(EmptyStateView), new PropertyMetadata(null, OnIdsChanged));

    /// <summary>Whether this is the in-section variant (web <c>InstrumentEmptyState</c>).</summary>
    public static readonly DependencyProperty IsCompactProperty = DependencyProperty.Register(
        nameof(IsCompact), typeof(bool), typeof(EmptyStateView), new PropertyMetadata(false, OnCompactChanged));

    /// <summary>Automation ID of the region's scroller (a UI Automation pane), for pages whose region has a spec ID.</summary>
    public static readonly DependencyProperty RegionAutomationIdProperty = DependencyProperty.Register(
        nameof(RegionAutomationId), typeof(string), typeof(EmptyStateView), new PropertyMetadata(null, OnIdsChanged));

    /// <summary>Live-region setting of the subtitle (Polite where a changing message must be spoken).</summary>
    public static readonly DependencyProperty SubtitleLiveSettingProperty = DependencyProperty.Register(
        nameof(SubtitleLiveSetting), typeof(AutomationLiveSetting), typeof(EmptyStateView),
        new PropertyMetadata(AutomationLiveSetting.Off, OnIdsChanged));

    /// <summary>Page variant padding: web <c>padding(48, Gap.xl)</c>.</summary>
    private static readonly Thickness PagePadding = new(12, 48, 12, 48);

    /// <summary>Compact variant padding inside a section.</summary>
    private static readonly Thickness CompactPadding = new(12, 24, 12, 24);

    private readonly Style pageTitleStyle;
    private readonly Style pageSubtitleStyle;

    /// <summary>Creates the view.</summary>
    public EmptyStateView()
    {
        InitializeComponent();
        pageTitleStyle = TitleBlock.Style;
        pageSubtitleStyle = SubtitleBlock.Style;
    }

    /// <summary>Heading text.</summary>
    public string? Title
    {
        get => (string?)GetValue(TitleProperty);
        set => SetValue(TitleProperty, value);
    }

    /// <summary>Subtitle text; collapsed when empty.</summary>
    public string? Subtitle
    {
        get => (string?)GetValue(SubtitleProperty);
        set => SetValue(SubtitleProperty, value);
    }

    /// <summary>Segoe Fluent Icons glyph above the heading (decorative, raw UIA view); none when empty.</summary>
    public string? Glyph
    {
        get => (string?)GetValue(GlyphProperty);
        set => SetValue(GlyphProperty, value);
    }

    /// <summary>Optional next-step action below the subtitle (e.g. Select Player, Retry while syncing).</summary>
    public object? Action
    {
        get => GetValue(ActionProperty);
        set => SetValue(ActionProperty, value);
    }

    /// <summary>Automation ID of the heading.</summary>
    public string? TitleAutomationId
    {
        get => (string?)GetValue(TitleAutomationIdProperty);
        set => SetValue(TitleAutomationIdProperty, value);
    }

    /// <summary>Automation ID of the subtitle.</summary>
    public string? SubtitleAutomationId
    {
        get => (string?)GetValue(SubtitleAutomationIdProperty);
        set => SetValue(SubtitleAutomationIdProperty, value);
    }

    /// <summary>Automation ID of the region's scroller; unset leaves the scroller unnamed.</summary>
    public string? RegionAutomationId
    {
        get => (string?)GetValue(RegionAutomationIdProperty);
        set => SetValue(RegionAutomationIdProperty, value);
    }

    /// <summary>Live-region setting of the subtitle; Off by default.</summary>
    public AutomationLiveSetting SubtitleLiveSetting
    {
        get => (AutomationLiveSetting)GetValue(SubtitleLiveSettingProperty);
        set => SetValue(SubtitleLiveSettingProperty, value);
    }

    /// <summary>
    /// In-section variant (web <c>InstrumentEmptyState</c>): body-strong text that is not a heading (the section header
    /// is), secondary subtitle, smaller padding, and no own scrolling because the section's page scrolls.
    /// </summary>
    public bool IsCompact
    {
        get => (bool)GetValue(IsCompactProperty);
        set => SetValue(IsCompactProperty, value);
    }

    private static void OnContentChanged(DependencyObject d, DependencyPropertyChangedEventArgs e) => ((EmptyStateView)d).ApplyContent();

    private static void OnIdsChanged(DependencyObject d, DependencyPropertyChangedEventArgs e) => ((EmptyStateView)d).ApplyIds();

    private static void OnCompactChanged(DependencyObject d, DependencyPropertyChangedEventArgs e) => ((EmptyStateView)d).ApplyVariant();

    /// <summary>Shows the text, icon and action, collapsing the parts that are unset.</summary>
    private void ApplyContent()
    {
        TitleBlock.Text = Title ?? "";
        SubtitleBlock.Text = Subtitle ?? "";
        SubtitleBlock.Visibility = string.IsNullOrEmpty(Subtitle) ? Visibility.Collapsed : Visibility.Visible;
        IconGlyph.Glyph = Glyph ?? "";
        IconGlyph.Visibility = string.IsNullOrEmpty(Glyph) ? Visibility.Collapsed : Visibility.Visible;
        ActionPresenter.Content = Action;
        ActionPresenter.Visibility = Action is null ? Visibility.Collapsed : Visibility.Visible;
    }

    /// <summary>Applies the heading and subtitle automation IDs.</summary>
    private void ApplyIds()
    {
        AutomationProperties.SetAutomationId(TitleBlock, TitleAutomationId ?? "");
        AutomationProperties.SetAutomationId(SubtitleBlock, SubtitleAutomationId ?? "");
        AutomationProperties.SetAutomationId(Scroller, RegionAutomationId ?? "");
        AutomationProperties.SetLiveSetting(SubtitleBlock, SubtitleLiveSetting);
    }

    /// <summary>Switches between the page and in-section variants.</summary>
    private void ApplyVariant()
    {
        var compact = IsCompact;
        TitleBlock.Style = compact ? (Style)Resources["CompactTitleStyle"] : pageTitleStyle;
        SubtitleBlock.Style = compact ? (Style)Resources["CompactSubtitleStyle"] : pageSubtitleStyle;
        Stack.Padding = compact ? CompactPadding : PagePadding;
        Scroller.VerticalScrollMode = compact ? ScrollMode.Disabled : ScrollMode.Enabled;
        Scroller.VerticalScrollBarVisibility = compact ? ScrollBarVisibility.Disabled : ScrollBarVisibility.Auto;
        // A section's own header is its heading; the compact message is plain text under it.
        AutomationProperties.SetHeadingLevel(TitleBlock, compact ? AutomationHeadingLevel.None : AutomationHeadingLevel.Level2);
    }
}
#endregion
