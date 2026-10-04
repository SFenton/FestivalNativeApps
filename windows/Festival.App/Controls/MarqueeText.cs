using System.Numerics;
using Microsoft.UI.Composition;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Media;
using Windows.Foundation;
using Windows.UI.ViewManagement;

namespace Festival.App.Controls;

#region Marquee text
/// <summary>
/// Single-line text that, whenever it overflows its space, scrolls a two-copy track on the compositor thread like
/// the web <c>MarqueeText</c> (8 s cycle, 5% dwell at each end, 28 px gap, phase-aligned across instances from one
/// epoch so neighbouring rows move together). Text that fits is drawn plainly. Motion off (Windows Animation effects,
/// in-app or launch Reduce Motion), a hidden/minimized window or an unloaded row stops it and shows the ellipsized
/// text instead. Screen readers always get the full text.
/// </summary>
public sealed partial class MarqueeText : Panel
{
    /// <summary>Displayed text.</summary>
    public static readonly DependencyProperty TextProperty = DependencyProperty.Register(
        nameof(Text), typeof(string), typeof(MarqueeText), new PropertyMetadata("", (d, _) => ((MarqueeText)d).OnTextChanged()));

    /// <summary>TextBlock style for both copies.</summary>
    public static readonly DependencyProperty TextStyleProperty = DependencyProperty.Register(
        nameof(TextStyle), typeof(Style), typeof(MarqueeText), new PropertyMetadata(null, (d, _) => ((MarqueeText)d).OnStyleChanged()));

    /// <summary>Seconds for one scroll-and-dwell cycle (web default 8).</summary>
    public static double CycleSeconds { get; set; } = 8;

    /// <summary>Gap between the copies in epx (web default 28).</summary>
    public const double Gap = 28;

    /// <summary>Global kill switch (Reduce Motion); the system animation setting is checked on each play.</summary>
    public static bool MotionAllowed { get; set; } = true;

    private static readonly UISettings SystemSettings = new();
    private readonly TextBlock primary = new() { TextWrapping = TextWrapping.NoWrap, TextTrimming = TextTrimming.CharacterEllipsis };
    private readonly TextBlock copy = new() { TextWrapping = TextWrapping.NoWrap, Visibility = Visibility.Collapsed };
    private static readonly DateTimeOffset Epoch = DateTimeOffset.UnixEpoch;
    private double naturalWidth;
    private bool playing;

    /// <summary>Creates the control.</summary>
    public MarqueeText()
    {
        Children.Add(primary);
        Children.Add(copy);
        AutomationProperties.SetAccessibilityView(copy, AccessibilityView.Raw);
        primary.IsTextTrimmedChanged += (_, _) => IsTextTrimmedChanged?.Invoke(this, EventArgs.Empty);
        IsHitTestVisible = false;
        SizeChanged += (_, _) => { UpdateClip(); QueueUpdate(); };
        Loaded += (_, _) => { Services.Motion.Changed += OnMotionChanged; QueueUpdate(); };
        Unloaded += (_, _) => { Services.Motion.Changed -= OnMotionChanged; Stop(); };
    }

    /// <summary>Re-evaluates when motion settings or window visibility change.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private void OnMotionChanged(object? sender, EventArgs e) => QueueUpdate();

    /// <summary>Plays or stops after layout settles (overflow is known only after measure).</summary>
    private void QueueUpdate() => DispatcherQueue?.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, UpdatePlayback);

    /// <summary>Scrolls while loaded, overflowing and allowed to move; otherwise shows the static ellipsized text.</summary>
    private void UpdatePlayback()
    {
        var animate = IsLoaded && Overflows && MotionAllowed && Services.Motion.Allowed && !Services.Motion.Paused;
        if (animate == playing) return;
        if (animate) Play();
        else Stop();
    }

    /// <summary>Displayed text.</summary>
    public string Text
    {
        get => (string)GetValue(TextProperty);
        set => SetValue(TextProperty, value);
    }

    /// <summary>TextBlock style.</summary>
    public Style? TextStyle
    {
        get => (Style?)GetValue(TextStyleProperty);
        set => SetValue(TextStyleProperty, value);
    }

    /// <summary>Font weight of both copies (e.g. bold for the selected player's leaderboard row).</summary>
    public Windows.UI.Text.FontWeight FontWeight
    {
        get => primary.FontWeight;
        set
        {
            if (primary.FontWeight.Weight == value.Weight) return;
            primary.FontWeight = copy.FontWeight = value;
            Restart();
        }
    }

    /// <summary>Text brush of both copies; <see langword="null"/> inherits the parent control's foreground again.</summary>
    public Brush? Foreground
    {
        get => primary.Foreground;
        set
        {
            if (value is null)
            {
                primary.ClearValue(TextBlock.ForegroundProperty);
                copy.ClearValue(TextBlock.ForegroundProperty);
            }
            else primary.Foreground = copy.Foreground = value;
        }
    }

    /// <summary>High-contrast adjustment of both copies (the text elements, not this panel).</summary>
    public ElementHighContrastAdjustment TextHighContrastAdjustment
    {
        get => primary.HighContrastAdjustment;
        set => primary.HighContrastAdjustment = copy.HighContrastAdjustment = value;
    }

    /// <summary>Whether the static form currently shows an ellipsis (overflowing while motion is off or stopped).</summary>
    public bool IsTextTrimmed => primary.IsTextTrimmed;

    /// <summary>Raised when <see cref="IsTextTrimmed"/> changes, so a host can offer the full text as a tooltip.</summary>
    public event EventHandler? IsTextTrimmedChanged;

    /// <summary>Whether the text is wider than the space it has.</summary>
    public bool Overflows => naturalWidth > ActualWidth + 1;

    /// <summary>Starts scrolling if the text overflows and motion is allowed (normally driven automatically).</summary>
    public void Play()
    {
        if (playing || !Overflows || !MotionAllowed || !SystemSettings.AnimationsEnabled) return;
        playing = true;
        primary.TextTrimming = TextTrimming.None;
        copy.Visibility = Visibility.Visible;
        InvalidateArrange();
        UpdateLayout();
        var distance = (float)(naturalWidth + Gap);
        foreach (var element in new UIElement[] { primary, copy })
        {
            var visual = ElementCompositionPreview.GetElementVisual(element);
            var compositor = visual.Compositor;
            var animation = compositor.CreateScalarKeyFrameAnimation();
            var linear = compositor.CreateLinearEasingFunction();
            animation.InsertKeyFrame(0f, 0f, linear);
            animation.InsertKeyFrame(0.05f, 0f, linear);
            animation.InsertKeyFrame(0.95f, -distance, linear);
            animation.InsertKeyFrame(1f, -distance, linear);
            animation.Duration = TimeSpan.FromSeconds(CycleSeconds);
            animation.IterationBehavior = AnimationIterationBehavior.Forever;
            visual.Properties.InsertVector3("Translation", Vector3.Zero);
            ElementCompositionPreview.SetIsTranslationEnabled(element, true);
            visual.StartAnimation("Translation.X", animation);
            // Web epoch-based negative animation-delay: every marquee sits at the same point of the shared cycle.
            if (visual.TryGetAnimationController("Translation.X") is { } controller)
                controller.Progress = (float)((DateTimeOffset.UtcNow - Epoch).TotalSeconds % CycleSeconds / CycleSeconds);
        }
    }

    /// <summary>Stops scrolling and restores the ellipsized text (normally driven automatically).</summary>
    public void Stop()
    {
        if (!playing) return;
        playing = false;
        foreach (var element in new UIElement[] { primary, copy })
        {
            var visual = ElementCompositionPreview.GetElementVisual(element);
            visual.StopAnimation("Translation.X");
            visual.Properties.InsertVector3("Translation", Vector3.Zero);
        }
        copy.Visibility = Visibility.Collapsed;
        primary.TextTrimming = TextTrimming.CharacterEllipsis;
        InvalidateArrange();
    }

    /// <inheritdoc />
    protected override Size MeasureOverride(Size availableSize)
    {
        primary.Measure(new Size(double.PositiveInfinity, availableSize.Height));
        naturalWidth = primary.DesiredSize.Width;
        copy.Measure(new Size(double.PositiveInfinity, availableSize.Height));
        var width = double.IsInfinity(availableSize.Width) ? naturalWidth : Math.Min(naturalWidth, availableSize.Width);
        // Static form: measure at the real width so the ellipsis applies.
        if (!playing) primary.Measure(new Size(width, availableSize.Height));
        return new Size(width, primary.DesiredSize.Height);
    }

    /// <inheritdoc />
    protected override Size ArrangeOverride(Size finalSize)
    {
        var height = primary.DesiredSize.Height;
        primary.Arrange(new Rect(0, 0, playing ? naturalWidth : finalSize.Width, height));
        copy.Arrange(new Rect(naturalWidth + Gap, 0, naturalWidth, height));
        return finalSize;
    }

    /// <inheritdoc />
    protected override AutomationPeer OnCreateAutomationPeer() => new MarqueeTextPeer(this);

    /// <summary>Clips the scrolling track to the control's bounds.</summary>
    private void UpdateClip() => Clip = new RectangleGeometry { Rect = new Rect(0, 0, ActualWidth, ActualHeight) };

    /// <summary>Applies new text to both copies.</summary>
    private void OnTextChanged()
    {
        Stop();
        primary.Text = copy.Text = Text ?? "";
        ToolTipService.SetToolTip(this, null);
        InvalidateMeasure();
        QueueUpdate();
    }

    /// <summary>Re-measures after a font change: the scroll distance depends on the text's natural width.</summary>
    private void Restart()
    {
        Stop();
        InvalidateMeasure();
        QueueUpdate();
    }

    /// <summary>Applies a new style to both copies.</summary>
    private void OnStyleChanged()
    {
        primary.Style = copy.Style = TextStyle;
        primary.TextTrimming = playing ? TextTrimming.None : TextTrimming.CharacterEllipsis;
        InvalidateMeasure();
        QueueUpdate();
    }

    /// <summary>Exposes the full text as one static-text element.</summary>
    /// <param name="owner">Control.</param>
    private sealed partial class MarqueeTextPeer(MarqueeText owner) : FrameworkElementAutomationPeer(owner)
    {
        protected override AutomationControlType GetAutomationControlTypeCore() => AutomationControlType.Text;

        protected override string GetNameCore() => owner.Text ?? "";

        protected override IList<AutomationPeer> GetChildrenCore() => [];
    }
}
#endregion
