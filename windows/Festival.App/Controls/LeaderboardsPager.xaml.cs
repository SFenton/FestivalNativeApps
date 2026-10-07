using System.ComponentModel;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Festival.App.Services;
using Windows.System;

namespace Festival.App.Controls;

#region Pager
/// <summary>
/// The shared board pager (IDs <c>&lt;prefix&gt;.page-*</c>) for Full Rankings, Band Rankings, the song leaderboard, the song
/// band leaderboard and Player Bands. Renders any <see cref="IBoardPager"/>.
/// </summary>
public sealed partial class LeaderboardsPager : UserControl
{
    /// <summary>Width the full five-control row needs; below it « and » drop.</summary>
    private const double FullWidth = 380;

    private bool compact;

    /// <summary>System GrayText for an unavailable glyph under a contrast theme (rebuilt on a system colour change).</summary>
    private Brush? grayText;

    /// <summary>Pager model.</summary>
    public static readonly DependencyProperty PagerProperty = DependencyProperty.Register(
        nameof(Pager), typeof(IBoardPager), typeof(LeaderboardsPager),
        new PropertyMetadata(null, (d, e) => ((LeaderboardsPager)d).Attach(e.OldValue as IBoardPager)));

    /// <summary>Automation ID prefix (e.g. <c>fst.player-bands</c>); defaults to the rankings model's own prefix.</summary>
    public static readonly DependencyProperty IdPrefixProperty = DependencyProperty.Register(
        nameof(IdPrefix), typeof(string), typeof(LeaderboardsPager), new PropertyMetadata(null, (d, _) => ((LeaderboardsPager)d).ApplyIds()));

    /// <summary>Creates the pager.</summary>
    public LeaderboardsPager()
    {
        InitializeComponent();
        foreach (var button in Buttons) button.IsEnabledChanged += (sender, _) => Dim((Button)sender);
        // A contrast theme switched on or off while a board is open re-applies the dim rule (issue #242: code-set state does
        // not follow {ThemeResource}).
        Loaded += (_, _) =>
        {
            ContrastTheme.Changed -= OnColorsChanged;
            ContrastTheme.Changed += OnColorsChanged;
            ApplyDimming();
        };
        Unloaded += (_, _) => ContrastTheme.Changed -= OnColorsChanged;
    }

    /// <summary>Re-applies the arrows' dim state on the UI thread after a system colour change.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private void OnColorsChanged(object? sender, EventArgs e) => DispatcherQueue?.TryEnqueue(() =>
    {
        grayText = null;
        ApplyDimming();
    });

    /// <summary>Pager model.</summary>
    public IBoardPager? Pager
    {
        get => (IBoardPager?)GetValue(PagerProperty);
        set => SetValue(PagerProperty, value);
    }

    /// <summary>Automation ID prefix.</summary>
    public string? IdPrefix
    {
        get => (string?)GetValue(IdPrefixProperty);
        set => SetValue(IdPrefixProperty, value);
    }

    /// <summary>The four buttons.</summary>
    private Button[] Buttons => [First, Previous, Next, Last];

    /// <summary>Hides First/Last when the available width is below the full row (compact windows).</summary>
    /// <param name="availableSize">Width offered by the page.</param>
    /// <returns>Desired size.</returns>
    protected override Windows.Foundation.Size MeasureOverride(Windows.Foundation.Size availableSize)
    {
        compact = availableSize.Width < FullWidth;
        var visibility = compact ? Visibility.Collapsed : Visibility.Visible;
        if (FirstHost.Visibility != visibility) FirstHost.Visibility = LastHost.Visibility = visibility;
        return base.MeasureOverride(availableSize);
    }

    /// <summary>Wires commands, IDs and the page text to a new model.</summary>
    /// <param name="old">Previous model.</param>
    private void Attach(IBoardPager? old)
    {
        if (old is not null) old.PropertyChanged -= OnPagerChanged;
        if (Pager is not { } pager) return;
        pager.PropertyChanged += OnPagerChanged;
        First.Command = pager.FirstCommand;
        Previous.Command = pager.PreviousCommand;
        Next.Command = pager.NextCommand;
        Last.Command = pager.LastCommand;
        ApplyIds();
        UpdateState();
    }

    /// <summary>Stamps <c>&lt;prefix&gt;.page-first/previous/page-info/next/last</c>.</summary>
    private void ApplyIds()
    {
        var prefix = IdPrefix ?? (Pager as RankingsPagerViewModel)?.IdPrefix;
        if (prefix is null) return;
        AutomationProperties.SetAutomationId(First, prefix + ".page-first");
        AutomationProperties.SetAutomationId(Previous, prefix + ".page-previous");
        AutomationProperties.SetAutomationId(Info, prefix + ".page-info");
        AutomationProperties.SetAutomationId(Next, prefix + ".page-next");
        AutomationProperties.SetAutomationId(Last, prefix + ".page-last");
    }

    /// <summary>Refreshes the page text and visibility.</summary>
    /// <param name="sender">Pager.</param>
    /// <param name="e">Changed property.</param>
    private void OnPagerChanged(object? sender, PropertyChangedEventArgs e) => UpdateState();

    /// <summary>Writes "page / total", its spoken form, and hides the pager for a single page (web <c>totalPages &gt; 1</c>).</summary>
    private void UpdateState()
    {
        if (Pager is not { } pager) return;
        Info.Text = pager.InfoText;
        AutomationProperties.SetName(Info, pager.InfoAnnouncement);
        Root.Visibility = pager.IsPaged ? Visibility.Visible : Visibility.Collapsed;
        ApplyDimming();
    }

    /// <summary>Applies <see cref="ApplyDimming(Button)"/> to every arrow.</summary>
    private void ApplyDimming()
    {
        foreach (var button in Buttons) ApplyDimming(button);
    }

    /// <summary>
    /// Dims an unavailable arrow as a whole, card surface included (web <c>Opacity.dimmed</c>), outside contrast themes.
    /// Under a contrast theme the host stays fully opaque, so its Window surface and WindowText rim match the rows
    /// (surface-materials R4), and the glyph turns GrayText (<see cref="PagerDimming"/>); a disabled button already gets
    /// GrayText from the pager's <c>ButtonForegroundDisabled</c>, so this also covers an arrow the model disallows before
    /// its command has disabled it.
    /// </summary>
    /// <param name="button">Button.</param>
    private void ApplyDimming(Button button)
    {
        var available = IsAvailable(button);
        var contrast = ContrastTheme.IsOn;
        Host(button).Opacity = PagerDimming.HostOpacity(available, contrast);
        if (PagerDimming.GrayTextGlyph(available, contrast))
            button.Foreground = grayText ??= new SolidColorBrush(
                new Windows.UI.ViewManagement.UISettings().UIElementColor(Windows.UI.ViewManagement.UIElementType.GrayText));
        else
            button.ClearValue(Control.ForegroundProperty);
    }

    /// <summary>
    /// Whether a button can page right now: enabled and allowed by the model's <see cref="IBoardPager.CanGoBack"/> /
    /// <see cref="IBoardPager.CanGoForward"/>. Reading the model as well keeps page 1's First/Previous dimmed even when
    /// the command's initial disabled state raises no <c>IsEnabledChanged</c>.
    /// </summary>
    /// <param name="button">Button.</param>
    /// <returns>Whether it is shown at full opacity.</returns>
    private bool IsAvailable(Button button)
    {
        if (!button.IsEnabled) return false;
        if (Pager is not { } pager) return true;
        return button == First || button == Previous ? pager.CanGoBack : pager.CanGoForward;
    }

    /// <summary>The card-surface host (surface Border + Button) of a pager button.</summary>
    /// <param name="button">Button.</param>
    /// <returns>Its host grid.</returns>
    private FrameworkElement Host(Button button) =>
        button == First ? FirstHost : button == Previous ? PreviousHost : button == Next ? NextHost : LastHost;

    /// <summary>
    /// Re-applies a button's dim state when it is enabled or disabled (<see cref="ApplyDimming(Button)"/>). A focused button
    /// that just became disabled (Next on reaching the last page) hands focus to an enabled one so keyboard paging can continue.
    /// </summary>
    /// <param name="button">Button.</param>
    private void Dim(Button button)
    {
        ApplyDimming(button);
        if (button.IsEnabled || button.FocusState == FocusState.Unfocused) return;
        foreach (var candidate in new[] { Previous, Next, First, Last })
            if (candidate.IsEnabled && Host(candidate).Visibility == Visibility.Visible && candidate.Focus(FocusState.Keyboard)) return;
    }

    /// <summary>Left/Right (Home/End) page while focus is in the pager, like the web's keyboard Paginator.</summary>
    /// <param name="sender">Pager row.</param>
    /// <param name="e">Key.</param>
    private void OnPreviewKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (Pager is not { } pager) return;
        var command = e.Key switch
        {
            VirtualKey.Left => pager.PreviousCommand,
            VirtualKey.Right => pager.NextCommand,
            VirtualKey.Home => pager.FirstCommand,
            VirtualKey.End => pager.LastCommand,
            _ => null,
        };
        if (command is null) return;
        e.Handled = true;
        if (command.CanExecute(null)) command.Execute(null);
    }
}
#endregion
