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
/// text instead. In-page text that opts in with <see cref="WrapsAtLargeText"/> wraps onto as many lines as it needs at
/// large Windows text sizes (<see cref="Festival.Core.Domain.LargeText"/>) instead of scrolling or ellipsizing (Apple's in-page
/// <c>marqueeWrapsAtAccessibilitySizes</c>, Android <c>wrapAtLargeText</c>). Screen readers always get the full text.
/// </summary>
public sealed partial class MarqueeText : Panel
{
    /// <summary>Displayed text.</summary>
    public static readonly DependencyProperty TextProperty = DependencyProperty.Register(
        nameof(Text), typeof(string), typeof(MarqueeText), new PropertyMetadata("", (d, _) => ((MarqueeText)d).OnTextChanged()));

    /// <summary>TextBlock style for both copies.</summary>
    public static readonly DependencyProperty TextStyleProperty = DependencyProperty.Register(
        nameof(TextStyle), typeof(Style), typeof(MarqueeText), new PropertyMetadata(null, (d, _) => ((MarqueeText)d).OnStyleChanged()));

    /// <summary>
    /// Wrap instead of scrolling at large Windows text sizes (in-page song header lines, pattern <c>song-header</c> R3).
    /// Off by default: rows, cards and bar titles stay on one line at every text size.
    /// </summary>
    public static readonly DependencyProperty WrapsAtLargeTextProperty = DependencyProperty.Register(
        nameof(WrapsAtLargeText), typeof(bool), typeof(MarqueeText), new PropertyMetadata(false, (d, _) => ((MarqueeText)d).OnWrapsAtLargeTextChanged()));

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
    private bool wrapped;
    private bool listeningToTextScale;

    /// <summary>Creates the control.</summary>
    public MarqueeText()
    {
        Children.Add(primary);
        Children.Add(copy);
        AutomationProperties.SetAccessibilityView(copy, AccessibilityView.Raw);
        primary.IsTextTrimmedChanged += (_, _) => IsTextTrimmedChanged?.Invoke(this, EventArgs.Empty);
        IsHitTestVisible = false;
        SizeChanged += (_, _) => { UpdateClip(); QueueUpdate(); };
        Loaded += (_, _) => { Services.Motion.Changed += OnMotionChanged; SyncTextScaleListener(true); UpdateWrap(); QueueUpdate(); };
        Unloaded += (_, _) => { Services.Motion.Changed -= OnMotionChanged; SyncTextScaleListener(false); Stop(); };
    }

    #region Large text wrap
    /// <inheritdoc cref="WrapsAtLargeTextProperty" />
    public bool WrapsAtLargeText
    {
        get => (bool)GetValue(WrapsAtLargeTextProperty);
        set => SetValue(WrapsAtLargeTextProperty, value);
    }

    /// <summary>Whether the text currently wraps (large text with <see cref="WrapsAtLargeText"/> on); it never scrolls then.</summary>
    public bool IsWrapped => wrapped;

    /// <summary>Re-evaluates the wrap mode and whether to follow text size changes.</summary>
    private void OnWrapsAtLargeTextChanged()
    {
        SyncTextScaleListener(IsLoaded);
        UpdateWrap();
    }

    /// <summary>Follows Windows text size changes only while loaded and opted in (rows stay unsubscribed).</summary>
    /// <param name="loaded">Whether the control is (being) loaded.</param>
    private void SyncTextScaleListener(bool loaded)
    {
        var listen = loaded && WrapsAtLargeText;
        if (listen == listeningToTextScale) return;
        listeningToTextScale = listen;
        if (listen) SystemSettings.TextScaleFactorChanged += OnTextScaleChanged;
        else SystemSettings.TextScaleFactorChanged -= OnTextScaleChanged;
    }

    /// <summary>Text size changed (raised off the UI thread).</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="args">Unused.</param>
    private void OnTextScaleChanged(UISettings sender, object args) => DispatcherQueue?.TryEnqueue(UpdateWrap);

    /// <summary>Switches between the one-line marquee and the wrapped full text.</summary>
    private void UpdateWrap()
    {
        var wrap = WrapsAtLargeText && Festival.Core.Domain.LargeText.Applies(SystemSettings.TextScaleFactor);
        if (wrap == wrapped) return;
        Stop();
        wrapped = wrap;
        primary.TextWrapping = wrap ? TextWrapping.Wrap : TextWrapping.NoWrap;
        primary.TextTrimming = wrap ? TextTrimming.None : TextTrimming.CharacterEllipsis;
        InvalidateMeasure();
        QueueUpdate();
    }
    #endregion

    /// <summary>Re-evaluates when motion settings or window visibility change.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private void OnMotionChanged(object? sender, EventArgs e) => QueueUpdate();

    /// <summary>Plays or stops after layout settles (overflow is known only after measure).</summary>
    private void QueueUpdate() => DispatcherQueue?.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, UpdatePlayback);

    /// <summary>Scrolls while loaded, overflowing and allowed to move; otherwise shows the static ellipsized text.</summary>
    private void UpdatePlayback()
    {
        var animate = IsLoaded && !wrapped && Overflows && MotionAllowed && Services.Motion.Allowed && !Services.Motion.Paused;
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

    /// <summary>
    /// Whether the text is wider than the space it has. Any measurable overflow counts (not a whole-epx slack): the static
    /// TextBlock ellipsizes even a fraction of an epx, and that ellipsis must scroll rather than hide part of a name.
    /// </summary>
    public bool Overflows => naturalWidth > ActualWidth + 0.1;

    /// <summary>Starts scrolling if the text overflows and motion is allowed (normally driven automatically).</summary>
    public void Play()
    {
        if (playing || wrapped || !Overflows || !MotionAllowed || !SystemSettings.AnimationsEnabled) return;
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
        if (wrapped)
        {
            // Large text: the whole text on as many lines as it needs, never wider than the column.
            primary.Measure(availableSize);
            naturalWidth = primary.DesiredSize.Width;
            return primary.DesiredSize;
        }
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
        primary.TextTrimming = playing || wrapped ? TextTrimming.None : TextTrimming.CharacterEllipsis;
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
