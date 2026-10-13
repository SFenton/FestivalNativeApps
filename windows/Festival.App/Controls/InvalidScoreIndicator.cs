using Festival.App.Services;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

#region Invalid score indicator
/// <summary>
/// A Songs row's Filter Invalid Scores indicator (web <c>InvalidScoreIcon</c>; Android <c>InvalidScoreIcon</c>): a red
/// alert when a filtered score was replaced or dropped, a gold warning when only raw Over CHOpt Threshold scores show.
/// It breathes on the shared Shop clock (<see cref="ShopPulseClock"/>, opacity 1 → <see cref="RestOpacity"/>) and holds
/// still when motion is off. Activating it (click, Enter or Space) opens the "Filtered Score" alert with OK and Settings.
/// UI Automation: a button named "Invalid score indicator" whose help text is the alert message.
/// </summary>
public sealed partial class InvalidScoreIndicator : Button
{
    /// <summary>Hit target in epx (Fluent minimum 40; web <c>GeneralSize.thumb</c>).</summary>
    public const double TargetSize = 40;

    /// <summary>Glyph size in epx (Android 22 dp; web chip-sized icon).</summary>
    public const double GlyphSize = 22;

    /// <summary>Lowest opacity of the breath (web <c>choptIconPulse</c>; Android 0.4).</summary>
    public const float RestOpacity = 0.4f;

    private readonly FontIcon glyph = new() { FontSize = GlyphSize };
    private readonly InvalidScoreWarning warning;
    private bool attached;

    /// <summary>Creates the indicator for one row.</summary>
    /// <param name="warning">Row warning.</param>
    /// <param name="songId">Row song (test ID).</param>
    public InvalidScoreIndicator(InvalidScoreWarning warning, string songId)
    {
        this.warning = warning;
        Width = TargetSize;
        Height = TargetSize;
        MinWidth = TargetSize;
        Padding = new Thickness(0);
        Margin = new Thickness(-((TargetSize - GlyphSize) / 2), 0, -((TargetSize - GlyphSize) / 2) + 4, 0);
        VerticalAlignment = VerticalAlignment.Center;
        Background = new SolidColorBrush(Colors.Transparent);
        BorderThickness = new Thickness(0);
        // Segoe Fluent Icons: ErrorBadge (web IoAlertCircleOutline) or Warning (web IoWarning).
        glyph.Glyph = warning.Warning ? "\uE7BA" : "\uEA39";
        Content = glyph;
        ApplyColors();
        AutomationProperties.SetName(this, InvalidScoreWarning.Label);
        AutomationProperties.SetHelpText(this, warning.Message);
        AutomationProperties.SetAutomationId(this, InvalidScoreWarning.AutomationId(songId));
        ToolTipService.SetToolTip(this, InvalidScoreWarning.Title);
        Click += OnClick;
        Loaded += (_, _) =>
        {
            ContrastTheme.Changed += OnContrastChanged;
            Attach();
        };
        Unloaded += (_, _) =>
        {
            ContrastTheme.Changed -= OnContrastChanged;
            Detach();
        };
    }

    /// <summary>Whether the gold Over CHOpt Threshold warning shows instead of the red alert.</summary>
    public bool IsWarning => warning.Warning;

    /// <summary>The red <c>FSTStatusMissingFillBrush</c> or gold <c>FSTEmphasisBrush</c> role (system colours under a contrast theme).</summary>
    private void ApplyColors() =>
        glyph.Foreground = ContrastTheme.Brush(warning.Warning ? "FSTEmphasisBrush" : "FSTStatusMissingFillBrush");

    /// <summary>Re-colours after a contrast-theme change.</summary>
    /// <param name="sender">Theme.</param>
    /// <param name="e">Unused.</param>
    private void OnContrastChanged(object? sender, EventArgs e) => DispatcherQueue?.TryEnqueue(ApplyColors);

    /// <summary>Binds the glyph's opacity to the shared Shop clock.</summary>
    private void Attach()
    {
        if (attached) return;
        var visual = ElementCompositionPreview.GetElementVisual(glyph);
        var opacity = visual.Compositor.CreateExpressionAnimation("rest + (1 - rest) * clock.Level");
        opacity.SetReferenceParameter("clock", ShopPulseClock.Acquire(visual.Compositor));
        opacity.SetScalarParameter("rest", RestOpacity);
        visual.StartAnimation("Opacity", opacity);
        attached = true;
    }

    /// <summary>Releases the clock.</summary>
    private void Detach()
    {
        if (!attached) return;
        var visual = ElementCompositionPreview.GetElementVisual(glyph);
        visual.StopAnimation("Opacity");
        visual.Opacity = 1;
        ShopPulseClock.Release();
        attached = false;
    }

    /// <summary>Opens the "Filtered Score" alert; Settings opens the Settings section (web <c>navigate('/settings')</c>).</summary>
    /// <param name="sender">Indicator.</param>
    /// <param name="e">Unused.</param>
    private async void OnClick(object sender, RoutedEventArgs e)
    {
        if (XamlRoot is not { } root) return;
        var body = new TextBlock { Text = warning.Message, TextWrapping = TextWrapping.Wrap };
        AutomationProperties.SetAutomationId(body, "fst.songs.invalid-score.message");
        // Modal-shell R5: at large text the message can outgrow a short window, and the template scroller never scrolls.
        // It is a tab stop (as Privacy Policy's) so the keyboard can scroll it.
        var scroller = new ScrollViewer
        {
            Content = body, IsTabStop = true,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
        };
        AutomationProperties.SetAutomationId(scroller, "fst.songs.invalid-score.body");
        var dialog = FestivalDialog.Create(root, InvalidScoreWarning.Title, scroller, "fst.songs.invalid-score.dialog",
            closeText: InvalidScoreWarning.OkAction, primaryText: InvalidScoreWarning.SettingsAction,
            closeAutomationId: "fst.songs.invalid-score.ok");
        if (await FestivalDialog.ShowAsync(dialog) == ContentDialogResult.Primary) MainWindow.Instance?.ShowSettings();
    }
}
#endregion
