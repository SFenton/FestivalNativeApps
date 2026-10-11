using Festival.App.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

#region Invalid score indicator
/// <summary>
/// The Songs row's invalid-score indicator (web <c>InvalidScoreIcon</c>, Android <c>InvalidScoreIcon</c>): a red alert
/// glyph when a filtered score was replaced or dropped, a gold warning when only raw over-threshold scores show. It is a
/// real button (Tab stop, Narrator name <see cref="InvalidScoreWarning.Label"/>, at least
/// <see cref="DialogChrome.TargetSize"/> square) whose glyph breathes 1 → 0.4 → 1 on the shared Shop pulse clock
/// (<see cref="ShopPulseClock"/>, web <c>choptIconPulse</c>) and holds still when motion is off.
/// </summary>
public sealed partial class InvalidScoreIndicator : Button
{
    /// <summary>Lowest glyph opacity of the pulse (web <c>choptIconPulse</c> 50% keyframe).</summary>
    public const float LowOpacity = 0.4f;

    private readonly FontIcon glyph;
    private bool attached;

    /// <summary>Creates the indicator for a row.</summary>
    /// <param name="warning">Row warning (reasons, colour and alert message).</param>
    /// <param name="songId">Row song ID (UI Automation ID).</param>
    public InvalidScoreIndicator(InvalidScoreWarning warning, string songId)
    {
        Warning = warning;
        glyph = new FontIcon { Glyph = warning.IsWarning ? "\uE7BA" : "\uE783", FontSize = 20 };
        // Contrast themes: the button's own system foreground instead of the brand red/gold.
        if (!ContrastTheme.IsOn)
            glyph.Foreground = (Brush)Application.Current.Resources[warning.IsWarning ? "FSTEmphasisBrush" : "FSTStatusMissingFillBrush"];
        Content = glyph;
        MinWidth = MinHeight = DialogChrome.TargetSize;
        Padding = new Thickness(0);
        CornerRadius = new CornerRadius(DialogChrome.TargetSize / 2);
        Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        BorderThickness = new Thickness(0);
        VerticalAlignment = VerticalAlignment.Center;
        AutomationProperties.SetName(this, InvalidScoreWarning.Label);
        AutomationProperties.SetAutomationId(this, InvalidScoreWarning.AutomationId(songId));
        ToolTipService.SetToolTip(this, InvalidScoreWarning.Title);
        Loaded += (_, _) => Attach();
        Unloaded += (_, _) => Detach();
    }

    /// <summary>Row warning shown by the alert.</summary>
    public InvalidScoreWarning Warning { get; }

    /// <summary>Binds the glyph's opacity to the shared clock (its <c>Level</c> holds at 1 when motion is off).</summary>
    private void Attach()
    {
        if (attached) return;
        var visual = ElementCompositionPreview.GetElementVisual(glyph);
        var opacity = visual.Compositor.CreateExpressionAnimation("low + (1 - low) * clock.Level");
        opacity.SetReferenceParameter("clock", ShopPulseClock.Acquire(visual.Compositor));
        opacity.SetScalarParameter("low", LowOpacity);
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
}
#endregion
