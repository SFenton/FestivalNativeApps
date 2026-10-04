using System.Numerics;
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI;
using Microsoft.UI.Composition;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Media;
using Windows.Foundation;
using Windows.Storage.Streams;

namespace Festival.App.Controls;

#region Artwork background
/// <summary>
/// The one shared animated album-art backdrop. All motion is keyframe animation on the composition
/// thread (no per-frame UI-thread work); the UI thread only swaps a cover every five seconds. Decorative:
/// hidden from UI Automation and hit testing.
/// </summary>
public sealed partial class ArtworkBackground : Grid
{
    #region Fields
    private const float Bleed = 24;
    private static readonly string[] AnimatedProperties = ["Opacity", "Scale", "Offset"];
    private readonly DispatcherQueueTimer timer;
    private Compositor? compositor;
    private ContainerVisual? root;
    private readonly SpriteVisual?[] slots = new SpriteVisual?[2];
    private SpriteVisual? cover;
    private SpriteVisual? dim;
    private int front;
    private ArtworkCarousel? carousel;
    private ArtworkMode mode = ArtworkMode.Static;
    private string? songArt;
    private bool showingSong;
    private bool songImageShown;
    private bool hasFrontImage;
    private bool frozen;
    private float coverOpacity;
    private float dimOpacity;
    private CancellationTokenSource loadCancellation = new();
    #endregion

    /// <summary>Creates the host; visuals are built when it is loaded.</summary>
    public ArtworkBackground()
    {
        IsHitTestVisible = false;
        // Raw view only: screen readers and the control view skip it; UI tests read its state from ItemStatus.
        AutomationProperties.SetAccessibilityView(this, AccessibilityView.Raw);
        AutomationProperties.SetAutomationId(this, "fst.shell.artwork-background");
        AutomationProperties.SetItemStatus(this, ArtworkBackgroundStatus.NoArt);
        Background = (Brush)Application.Current.Resources["FSTAppBackgroundBrush"];
        timer = DispatcherQueue.GetForCurrentThread().CreateTimer();
        timer.Interval = ArtworkCarousel.Dwell;
        timer.Tick += (_, _) => _ = AdvanceAsync();
        Loaded += (_, _) => EnsureVisuals();
        SizeChanged += (_, _) => Layout();
    }

    /// <summary>Current resolved mode.</summary>
    public ArtworkMode Mode => mode;

    /// <summary>Whether a cover is drawn: the song cover on Song Detail, else the front carousel cover.</summary>
    private bool ImageShown => showingSong ? songImageShown : slots[front]?.Brush is not null;

    /// <summary>A panel has no peer by default; this one exposes the raw-view state element for UI tests.</summary>
    /// <returns>Automation peer.</returns>
    protected override AutomationPeer OnCreateAutomationPeer() => new FrameworkElementAutomationPeer(this);

    /// <summary>Number of cover swaps performed (perf diagnostics).</summary>
    public int SwapCount { get; private set; }

    /// <summary>Supplies catalogue art for the carousel (≤100 shuffled covers).</summary>
    /// <param name="artReferences">Song <c>albumArt</c> values.</param>
    public void SetCatalog(IEnumerable<string?> artReferences)
    {
        carousel = new ArtworkCarousel(artReferences);
        hasFrontImage = false;
        Refresh();
    }

    /// <summary>Applies the playback policy.</summary>
    /// <param name="next">Resolved mode.</param>
    public void ApplyMode(ArtworkMode next)
    {
        if (next == mode) return;
        mode = next;
        Services.PerfLog.Event("backdrop-" + next.ToString().ToLowerInvariant());
        Refresh();
    }

    /// <summary>Shows a static, dimmed song cover over the paused carousel (Song Detail).</summary>
    /// <param name="albumArt">Song art reference; <see langword="null"/> shows the brand surface.</param>
    public void ShowSong(string? albumArt)
    {
        showingSong = true;
        songArt = albumArt;
        Refresh();
    }

    /// <summary>Returns to the rotating carousel.</summary>
    public void ShowCarousel()
    {
        if (!showingSong) return;
        showingSong = false;
        songArt = null;
        Refresh();
    }

    #region Visual tree
    /// <summary>Builds the composition tree once.</summary>
    private void EnsureVisuals()
    {
        if (root is not null) return;
        compositor = ElementCompositionPreview.GetElementVisual(this).Compositor;
        root = compositor.CreateContainerVisual();
        // Clip to the host (the whole window, behind the title bar and pane): the bleed and drift scale overflow it.
        root.Clip = compositor.CreateInsetClip();
        for (var i = 0; i < slots.Length; i++)
        {
            slots[i] = compositor.CreateSpriteVisual();
            slots[i]!.Opacity = 0;
            root.Children.InsertAtTop(slots[i]);
        }
        cover = compositor.CreateSpriteVisual();
        cover.Opacity = 0;
        root.Children.InsertAtTop(cover);
        dim = compositor.CreateSpriteVisual();
        dim.Brush = compositor.CreateColorBrush(Colors.Black);
        dim.Opacity = 0;
        root.Children.InsertAtTop(dim);
        ElementCompositionPreview.SetElementChildVisual(this, root);
        Layout();
        Refresh();
    }

    /// <summary>Sizes visuals to the host plus a bleed so pans never reveal an edge.</summary>
    private void Layout()
    {
        if (root is null) return;
        var size = new Vector2((float)ActualWidth, (float)ActualHeight);
        root.Size = size;
        foreach (var visual in slots.Append(cover))
        {
            visual!.Size = size + new Vector2(Bleed * 2);
            visual.CenterPoint = new Vector3(visual.Size / 2, 0);
            if (visual.TryGetAnimationController("Offset") is null) visual.Offset = new Vector3(-Bleed, -Bleed, 0);
        }
        // The scrim overhangs the clip like the art does, so DPI rounding of the host size can never leave an
        // undimmed edge row or column.
        dim!.Size = size + new Vector2(Bleed * 2);
        dim.Offset = new Vector3(-Bleed, -Bleed, 0);
    }
    #endregion

    #region Playback
    /// <summary>Re-applies mode, song and carousel state.</summary>
    private void Refresh()
    {
        if (root is null) return;
        timer.Stop();
        loadCancellation.Cancel();
        loadCancellation = new CancellationTokenSource();
        var hidden = mode == ArtworkMode.Hidden;
        root.IsVisible = !hidden;
        if (hidden)
        {
            ReleaseImages();
            UpdateState(TimeSpan.Zero);
            return;
        }
        if (showingSong)
        {
            FreezeMotion();
            _ = ShowCoverAsync(songArt, loadCancellation.Token);
            return;
        }
        FadeCover(0, TimeSpan.FromMilliseconds(450));
        songImageShown = false;
        switch (mode)
        {
            case ArtworkMode.Paused:
                FreezeMotion();
                break;
            case ArtworkMode.Static:
                StopMotion();
                if (!hasFrontImage) _ = AdvanceAsync();
                break;
            default:
                // Resuming from a freeze starts the next crossfade and drift at once instead of holding a still frame.
                if (!hasFrontImage || frozen) _ = AdvanceAsync();
                frozen = false;
                timer.Start();
                break;
        }
        UpdateState(TimeSpan.FromMilliseconds(450));
    }

    /// <summary>Loads the next cover (up to three immediate attempts) and crossfades to it.</summary>
    /// <returns>Swap task.</returns>
    private async Task AdvanceAsync()
    {
        if (carousel is null || compositor is null) return;
        var token = loadCancellation.Token;
        for (var attempt = 0; attempt < 3 && !carousel.IsExhausted; attempt++)
        {
            if (carousel.Next() is not { } next) return;
            var brush = await LoadBrushAsync(next.Cover, token);
            if (token.IsCancellationRequested) return;
            if (brush is null)
            {
                carousel.ReportFailure();
                continue;
            }
            Swap(brush, next.Preset);
            return;
        }
    }

    /// <summary>Crossfades the back slot in above the front slot and starts its drift.</summary>
    /// <param name="brush">Loaded cover.</param>
    /// <param name="preset">Zoom/pan preset.</param>
    private void Swap(CompositionSurfaceBrush brush, MotionPreset preset)
    {
        var incoming = slots[1 - front]!;
        var outgoing = slots[front]!;
        StopAnimations(incoming);
        if ((incoming.Brush as CompositionSurfaceBrush)?.Surface is IDisposable stale) stale.Dispose();
        incoming.Brush = brush;
        root!.Children.Remove(incoming);
        root.Children.InsertAbove(incoming, outgoing);
        var animate = mode == ArtworkMode.Animated;
        var baseOffset = new Vector3(-Bleed, -Bleed, 0);
        if (animate)
        {
            var fade = compositor!.CreateScalarKeyFrameAnimation();
            fade.InsertKeyFrame(0, 0);
            fade.InsertKeyFrame(1, 1, compositor.CreateStepEasingFunction((int)(ArtworkCarousel.Crossfade.TotalSeconds * CrossfadeStepsPerSecond)));
            fade.Duration = ArtworkCarousel.Crossfade;
            var batch = compositor.CreateScopedBatch(CompositionBatchTypes.Animation);
            incoming.StartAnimation("Opacity", fade);
            batch.End();
            batch.Completed += (_, _) =>
            {
                // Completion is delivered later: a freeze (which stops the fade) and a resumed swap can reuse the
                // outgoing slot as the new front first, and retiring it then would blank the shown cover.
                if (incoming.Brush == brush && ReferenceEquals(slots[front], incoming)) Retire(outgoing);
            };

            var scale = compositor.CreateVector3KeyFrameAnimation();
            scale.InsertKeyFrame(0, new Vector3((float)preset.FromScale, (float)preset.FromScale, 1));
            scale.InsertKeyFrame(1, new Vector3((float)preset.ToScale, (float)preset.ToScale, 1), DriftEasing());
            scale.Duration = ArtworkCarousel.Drift;
            incoming.StartAnimation("Scale", scale);

            var offset = compositor.CreateVector3KeyFrameAnimation();
            var (fromX, fromY) = preset.VisualFrom;
            var (toX, toY) = preset.VisualTo;
            offset.InsertKeyFrame(0, baseOffset + new Vector3((float)fromX, (float)fromY, 0));
            offset.InsertKeyFrame(1, baseOffset + new Vector3((float)toX, (float)toY, 0), DriftEasing());
            offset.Duration = ArtworkCarousel.Drift;
            incoming.StartAnimation("Offset", offset);
        }
        else
        {
            incoming.Opacity = 1;
            incoming.Scale = Vector3.One;
            incoming.Offset = baseOffset;
            Retire(outgoing);
        }
        front = 1 - front;
        hasFrontImage = true;
        SwapCount++;
        UpdateState(animate ? ArtworkCarousel.Crossfade : TimeSpan.Zero);
        Services.PerfLog.Event(animate ? "backdrop-swap-animated" : "backdrop-swap-still");
    }

    /// <summary>
    /// Easing for the slow drift. A step easing quantizes the 6 s zoom/pan to <see cref="DriftStepsPerSecond"/>
    /// updates so the compositor only redraws when the value changes, instead of every display refresh.
    /// </summary>
    /// <returns>Easing function.</returns>
    private CompositionEasingFunction DriftEasing()
    {
        var steps = DriftStepsPerSecond;
        if (steps <= 0) return compositor!.CreateLinearEasingFunction();
        var easing = compositor!.CreateStepEasingFunction((int)(ArtworkCarousel.Drift.TotalSeconds * steps));
        easing.IsFinalStepSingleFrame = false;
        return easing;
    }

    /// <summary>
    /// Drift updates per second (0 = every compositor frame). Measured on a 240 Hz display: continuous drift
    /// cost ~15% of one core and 8.4% GPU; 30 steps/s cost ~6.7% and 2.4% (see platforms/windows.md).
    /// </summary>
    private static int DriftStepsPerSecond => App.Options.DriftFps ?? 30;

    /// <summary>
    /// Crossfade updates per second. Matches the drift so the two step together (30 redraws a second rather than up to
    /// 90 while a fade overlaps a drift, as at 60 steps); 30 opacity steps over 1 s of dimmed art read as continuous.
    /// </summary>
    private static int CrossfadeStepsPerSecond => DriftStepsPerSecond > 0 ? DriftStepsPerSecond : 60;

    /// <summary>Hides a slot and releases its surface.</summary>
    /// <param name="slot">Outgoing slot.</param>
    private static void Retire(SpriteVisual slot)
    {
        StopAnimations(slot);
        slot.Opacity = 0;
        if ((slot.Brush as CompositionSurfaceBrush)?.Surface is IDisposable surface) surface.Dispose();
        slot.Brush = null;
    }

    /// <summary>Shows the song cover (or brand surface) above the carousel.</summary>
    /// <param name="raw">Art reference.</param>
    /// <param name="token">Cancellation.</param>
    /// <returns>Load task.</returns>
    private async Task ShowCoverAsync(string? raw, CancellationToken token)
    {
        var brush = raw is null ? null : await LoadBrushAsync(raw, token);
        if (token.IsCancellationRequested) return;
        cover!.Brush = brush is null ? compositor!.CreateColorBrush(((SolidColorBrush)Background).Color) : brush;
        cover.Scale = Vector3.One;
        cover.Offset = new Vector3(-Bleed, -Bleed, 0);
        songImageShown = brush is not null;
        FadeCover(1, TimeSpan.FromMilliseconds(500));
        UpdateState(TimeSpan.FromMilliseconds(500));
    }

    /// <summary>
    /// Shows the dim layer only over a cover (fading it with the cover change) and publishes the reachable state as the
    /// UI Automation item status.
    /// </summary>
    /// <param name="fade">Dim fade length; zero cuts.</param>
    private void UpdateState(TimeSpan fade)
    {
        if (dim is null) return;
        var to = ArtworkBackgroundStatus.DimShown(mode, ImageShown) ? (float)ArtworkCarousel.DimOpacity : 0f;
        if (Math.Abs(dimOpacity - to) >= 0.001f)
        {
            dimOpacity = to;
            dim.StopAnimation("Opacity");
            if (fade <= TimeSpan.Zero)
            {
                dim.Opacity = to;
            }
            else
            {
                var animation = compositor!.CreateScalarKeyFrameAnimation();
                animation.InsertKeyFrame(1, to);
                animation.Duration = fade;
                dim.StartAnimation("Opacity", animation);
            }
        }
        AutomationProperties.SetItemStatus(this, ArtworkBackgroundStatus.Resolve(mode, ImageShown, showingSong));
    }

    /// <summary>Fades the cover layer (opacity-only, so it is also used under reduced motion).</summary>
    /// <param name="to">Target opacity.</param>
    /// <param name="duration">Fade length.</param>
    private void FadeCover(float to, TimeSpan duration)
    {
        if (cover is null || Math.Abs(coverOpacity - to) < 0.001f) return;
        coverOpacity = to;
        var fade = compositor!.CreateScalarKeyFrameAnimation();
        fade.InsertKeyFrame(1, to);
        fade.Duration = duration;
        cover.StartAnimation("Opacity", fade);
    }

    /// <summary>
    /// Stops the carousel at its current frame (hidden, covered or under a song cover). Animations are stopped rather
    /// than paused so an unseen window holds no running composition animation; <see cref="Refresh"/> starts the next
    /// crossfade when motion resumes.
    /// </summary>
    private void FreezeMotion()
    {
        timer.Stop();
        if (!hasFrontImage) return;
        StopMotion();
        frozen = true;
    }

    /// <summary>Freezes motion at its current values (static mode).</summary>
    private void StopMotion()
    {
        foreach (var slot in slots) if (slot is not null) StopAnimations(slot);
        if (slots[front] is { } shown && shown.Brush is not null) shown.Opacity = 1;
    }

    /// <summary>Stops all animations on a visual.</summary>
    /// <param name="visual">Visual.</param>
    private static void StopAnimations(Visual visual)
    {
        foreach (var property in AnimatedProperties) visual.StopAnimation(property);
    }

    /// <summary>Drops all loaded surfaces (save-data mode).</summary>
    private void ReleaseImages()
    {
        foreach (var slot in slots) if (slot is not null) Retire(slot);
        if (cover is not null)
        {
            cover.StopAnimation("Opacity");
            cover.Brush = null;
            cover.Opacity = 0;
            coverOpacity = 0;
        }
        songImageShown = false;
        hasFrontImage = false;
    }

    /// <summary>Loads a cover through the shared byte cache and decodes it at window size.</summary>
    /// <param name="raw">Art reference.</param>
    /// <param name="token">Cancellation.</param>
    /// <returns>Brush, or <see langword="null"/> on failure (logged and skipped).</returns>
    private async Task<CompositionSurfaceBrush?> LoadBrushAsync(string raw, CancellationToken token)
    {
        if (App.Session.Api.ArtworkUri(raw) is not { } url) return null;
        try
        {
            var bytes = await App.Session.Artwork.GetAsync(url, token);
            if (token.IsCancellationRequested) return null;
            using var stream = new InMemoryRandomAccessStream();
            await stream.WriteAsync(bytes.AsBuffer());
            stream.Seek(0);
            var scale = XamlRoot?.RasterizationScale ?? 1.0;
            var edge = Math.Clamp(Math.Max(ActualWidth, ActualHeight) * scale, 256, 1024);
            var surface = LoadedImageSurface.StartLoadFromStream(stream, new Size(edge, edge));
            var completion = new TaskCompletionSource<bool>();
            surface.LoadCompleted += (_, args) => completion.TrySetResult(args.Status == LoadedImageSourceLoadStatus.Success);
            if (!await completion.Task || token.IsCancellationRequested)
            {
                surface.Dispose();
                return null;
            }
            var brush = compositor!.CreateSurfaceBrush(surface);
            brush.Stretch = CompositionStretch.UniformToFill;
            brush.HorizontalAlignmentRatio = 0.5f;
            brush.VerticalAlignmentRatio = 0.5f;
            return brush;
        }
        catch (Exception error) when (error is FestivalApiException or OperationCanceledException or System.Runtime.InteropServices.COMException)
        {
            if (error is not OperationCanceledException) System.Diagnostics.Debug.WriteLine($"Background art failed: {error.Message}");
            return null;
        }
    }
    #endregion
}
#endregion
