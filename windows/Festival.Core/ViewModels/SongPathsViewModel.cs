using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Swap phases
/// <summary>
/// Where a Paths content swap is (web <c>PathsModal</c> phases <c>fadeOutImage</c> → <c>spinner</c> →
/// <c>fadeOutSpinner</c> → <c>fadeInImage</c>/<c>textStagger</c> → <c>idle</c>).
/// </summary>
public enum PathSwapPhase
{
    /// <summary>The previous chart, table or message is fading out.</summary>
    ContentOut,
    /// <summary>The spinner is fading in or holding while the new content loads.</summary>
    Spinner,
    /// <summary>The spinner is fading out.</summary>
    SpinnerOut,
    /// <summary>The presented content is fading in or shown.</summary>
    Content,
}

/// <summary>Web <c>PathsModal</c> swap timing.</summary>
public static class PathSwapTiming
{
    /// <summary>Content and spinner fade (web <c>FADE_MS</c>).</summary>
    public static readonly TimeSpan Fade = TimeSpan.FromMilliseconds(300);

    /// <summary>Minimum spinner hold for an image (web <c>MIN_SPINNER_MS</c>).</summary>
    public static readonly TimeSpan MinImageSpinner = TimeSpan.FromMilliseconds(400);

    /// <summary>Minimum spinner hold for the table (web <c>MIN_TEXT_SPINNER_MS</c>).</summary>
    public static readonly TimeSpan MinTextSpinner = TimeSpan.FromMilliseconds(500);
}
#endregion

#region Instrument option
/// <summary>One entry of the compact instrument <c>ComboBox</c>: icon and name (every option has an icon).</summary>
/// <param name="Instrument">Chart.</param>
/// <param name="Label">Visible and spoken name, e.g. <c>Lead</c>.</param>
/// <param name="IconFile">Bundled icon file (keyboard art for Pro Lead/Bass on keyboard songs).</param>
public sealed record PathInstrumentOption(Instrument Instrument, string Label, string IconFile)
{
    /// <summary>The name, which UI Automation reads as the combo box's value.</summary>
    /// <returns><see cref="Label"/>.</returns>
    public override string ToString() => Label;
}
#endregion

#region Paths
/// <summary>
/// CHOpt Paths dialog: instrument, difficulty and image/text selectors reset on every opening; image and text
/// each load independently and an older request never paints after a newer choice.
/// <para>
/// When <see cref="AnimateSwaps"/> allows motion a switch runs the web swap: the presented content fades out
/// (<see cref="PathSwapTiming.Fade"/>), the spinner fades in and holds for at least the web minimum while the read
/// (and <see cref="PrepareImageAsync"/>) runs, fades out, and the new content fades in. A newer selection cancels the
/// sequence, so the spinner, never the stale content, stays up. Without motion the swap is instant.
/// </para>
/// </summary>
public sealed partial class SongPathsViewModel : ObservableObject
{
    /// <summary>Zoom steps for the image.</summary>
    public const double MinZoom = 1, MaxZoom = 3, ZoomStep = 1.5;

    /// <summary>
    /// Fit-zoom width of the path image: the full viewport width (the image is centred, and Fluent's overlay scroll
    /// bars take no layout space, issue #87), never upscaled past the image's own pixel width.
    /// </summary>
    /// <param name="viewportWidth">Scroll viewport width in effective pixels.</param>
    /// <param name="pixelWidth">Decoded image width in physical pixels.</param>
    /// <param name="rasterizationScale">Display scale (physical per effective pixel); non-positive means 1.</param>
    /// <returns>Image width in effective pixels, at least 1.</returns>
    public static double FitImageWidth(double viewportWidth, int pixelWidth, double rasterizationScale)
    {
        var scale = rasterizationScale > 0 ? rasterizationScale : 1;
        var available = double.IsFinite(viewportWidth) ? viewportWidth : 1;
        return Math.Max(1, Math.Min(available, pixelWidth / scale));
    }

    /// <summary>
    /// Whether the chart scroller shows scroll bars (issues #87, #279). The owner asked for no scroll bar or indicator beside
    /// the path image, so the bars are hidden while Windows auto-hides scroll bars (the default); wheel, Ctrl+wheel, pinch,
    /// touch, touchpad and arrow/Page keys still scroll and zoom. Turning off Settings › Accessibility › Visual effects ›
    /// "Always show scrollbars" is an explicit request for visible bars, so they show then (the macOS Paths precedent:
    /// hidden indicators that still appear when System Settings asks to always show scroll bars).
    /// </summary>
    /// <param name="systemAutoHidesScrollBars"><c>UISettings.AutoHideScrollBars</c>.</param>
    /// <returns><see langword="true"/> only when the system always shows scroll bars.</returns>
    public static bool ShowChartScrollBars(bool systemAutoHidesScrollBars) => !systemAutoHidesScrollBars;

    /// <summary>
    /// Zoom factor reported by the image scroller, as a model zoom: clamped to <see cref="MinZoom"/>–<see cref="MaxZoom"/>
    /// and snapped onto a bound within half a displayed percent. The scroller returns a float that DPI snapping can leave
    /// just past a bound (1.0003 at 150% display scale), which read "100%" while Zoom out stayed enabled (issue #279).
    /// </summary>
    /// <param name="factor">The scroller's zoom factor.</param>
    /// <returns>Model zoom, exactly a bound when within 0.005 of it; <see cref="MinZoom"/> for a non-finite factor.</returns>
    public static double NormalizeZoom(double factor)
    {
        const double tolerance = 0.005;
        if (!double.IsFinite(factor)) return MinZoom;
        var zoom = Math.Clamp(factor, MinZoom, MaxZoom);
        if (zoom - MinZoom < tolerance) return MinZoom;
        return MaxZoom - zoom < tolerance ? MaxZoom : zoom;
    }

    private readonly FestivalSession session;
    private CancellationTokenSource? request;
    private int revision;
    private bool presentedText;
    private Instrument presentedInstrument;
    private PathDifficulty presentedDifficulty = PathDifficulty.Expert;

    /// <summary>Creates a Paths session.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="song">Song.</param>
    /// <param name="instruments">Visible, charted, path-capable instruments (non-empty).</param>
    public SongPathsViewModel(FestivalSession session, Song song, IReadOnlyList<Instrument> instruments)
    {
        this.session = session;
        Song = song;
        Instruments = [.. instruments];
        InstrumentLabels = [.. instruments.Select(i => i.Label())];
        InstrumentOptions = [.. instruments.Select(i => new PathInstrumentOption(i, i.Label(), i.IconFile(song.UsesKeyboardIcon)))];
        showText = presentedText = session.Settings.PathDefaultView == PathDisplayMode.Text;
        presentedInstrument = Instruments[0];
        Status = new ServiceStatusViewModel($"paths:{song.SongId}", "Path Unavailable", LoadAsync, session.Time);
        ShowWarning = session.Settings.VisibleInstruments.Contains(Instrument.Karaoke) && !session.Settings.PathUnavailableWarningDismissed &&
                      !session.PathNoticeShown;
        if (ShowWarning) session.PathNoticeShown = true;
    }

    /// <summary>Song.</summary>
    public Song Song { get; }

    /// <summary>Selectable instruments.</summary>
    public List<Instrument> Instruments { get; }

    /// <summary>Instrument labels for the picker.</summary>
    public List<string> InstrumentLabels { get; }

    /// <summary>Compact instrument picker entries, in <see cref="Instruments"/> order (index = <see cref="InstrumentIndex"/>).</summary>
    public List<PathInstrumentOption> InstrumentOptions { get; }

    /// <summary>Difficulty labels for the segmented picker.</summary>
    public List<string> DifficultyLabels { get; } = [.. PathDifficultyInfo.All.Select(d => d.Label())];

    /// <summary>Failed-read presentation.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Whether the Karaoke-unavailable notice shows (first opening per app session, until "Don't show again").</summary>
    [ObservableProperty]
    private bool showWarning;

    /// <summary>Selected instrument index.</summary>
    [ObservableProperty]
    private int instrumentIndex;

    /// <summary>Selected difficulty index (Expert by default).</summary>
    [ObservableProperty]
    private int difficultyIndex = (int)PathDifficulty.Expert;

    /// <summary>Text (structured table) instead of the image.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(DisplayIndex))]
    private bool showText;

    /// <summary>Load lifecycle of the presented content (lags the selection while the old content fades out).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ShowImage), nameof(ShowTable), nameof(ShowError), nameof(ShowNotGenerated))]
    private LoadState state = LoadState.Idle;

    /// <summary>Swap phase.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLoading), nameof(ContentOpacity), nameof(SpinnerOpacity))]
    private PathSwapPhase phase = PathSwapPhase.Spinner;

    /// <summary>Loaded image.</summary>
    [ObservableProperty]
    private PathImage? image;

    /// <summary>Loaded text data (the web table shows only the activation rows: no path summary or max score).</summary>
    [ObservableProperty]
    private SongPathData? data;

    /// <summary>Resolved activation rows.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasNoActivations))]
    private List<PathActivationRow> rows = [];

    /// <summary>Image zoom (1–3).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ZoomText), nameof(CanZoomIn), nameof(CanZoomOut))]
    private double zoom = MinZoom;

    /// <summary>0 = Image, 1 = Text (segmented control).</summary>
    public int DisplayIndex
    {
        get => ShowText ? 1 : 0;
        set => ShowText = value == 1;
    }

    /// <summary>Selected instrument.</summary>
    public Instrument Instrument => Instruments[Math.Clamp(InstrumentIndex, 0, Instruments.Count - 1)];

    /// <summary>Selected difficulty.</summary>
    public PathDifficulty Difficulty => (PathDifficulty)Math.Clamp(DifficultyIndex, 0, 3);

    /// <summary>Whether the spinner is up (fading in, holding or fading out).</summary>
    public bool IsLoading => Phase is PathSwapPhase.Spinner or PathSwapPhase.SpinnerOut;

    /// <summary>Target opacity of the presented content (the view animates the change).</summary>
    public double ContentOpacity => Phase == PathSwapPhase.Content ? 1 : 0;

    /// <summary>Target opacity of the spinner (the view animates the change).</summary>
    public double SpinnerOpacity => Phase == PathSwapPhase.Spinner ? 1 : 0;

    /// <summary>Whether motion is allowed for the swap (the view supplies the system/app setting; default instant).</summary>
    public Func<bool> AnimateSwaps { get; set; } = () => false;

    /// <summary>Prepares (decodes) a loaded image while the spinner is up, before it is presented.</summary>
    public Func<PathImage, CancellationToken, Task>? PrepareImageAsync { get; set; }

    /// <summary>Screen-reader announcements: loading on a switch, then what loaded (failures: the status view).</summary>
    public event EventHandler<Announcement>? Announced;

    /// <summary>Whether the image shows.</summary>
    public bool ShowImage => State == LoadState.Loaded && !presentedText && Image is not null;

    /// <summary>Whether the table shows.</summary>
    public bool ShowTable => State == LoadState.Loaded && presentedText && Data is not null;

    /// <summary>Whether the error shows.</summary>
    public bool ShowError => State == LoadState.Failed;

    /// <summary>Whether the service has no path for this chart and difficulty (HTTP 404).</summary>
    public bool ShowNotGenerated => State == LoadState.Empty;

    /// <summary>Whether a loaded table has no activations.</summary>
    public bool HasNoActivations => Rows.Count == 0;

    /// <summary>Saved text-table column order.</summary>
    public IReadOnlyList<PathColumnKey> Columns => SettingsOrder.Normalize(session.Settings.PathColumnOrder);

    /// <summary>"150%".</summary>
    public string ZoomText => $"{Math.Round(Zoom * 100):0}%";

    /// <summary>Whether zooming in is possible.</summary>
    public bool CanZoomIn => Zoom < MaxZoom;

    /// <summary>Whether zooming out is possible.</summary>
    public bool CanZoomOut => Zoom > MinZoom;

    /// <summary>Selects a chart from the Instrument Selector (ignored when it isn't offered).</summary>
    /// <param name="instrument">Chart.</param>
    public void SelectInstrument(Instrument instrument)
    {
        var index = Instruments.IndexOf(instrument);
        if (index >= 0) InstrumentIndex = index;
    }

    /// <summary>Spoken image description of the presented chart.</summary>
    public string ImageDescription => $"{presentedInstrument.Label()} {presentedDifficulty.Label()} CHOpt path";

    /// <summary>Copy shown when the service has no path for the chart and difficulty.</summary>
    public const string NotGeneratedText = "No path has been generated for this instrument and difficulty yet.";

    /// <summary>Loads the current selection (first call on open; selector changes reload automatically).</summary>
    /// <returns>Load task.</returns>
    public async Task LoadAsync()
    {
        request?.Cancel();
        var cancellation = request = new CancellationTokenSource();
        var token = cancellation.Token;
        var mine = ++revision;
        var (instrument, difficulty, text) = (Instrument, Difficulty, ShowText);
        var animate = AnimateSwaps();
        // The opening read is announced by the dialog title; switches and retries announce loading and the result.
        var announce = State != LoadState.Idle;
        var fetch = FetchAsync(instrument, difficulty, text, token);
        try
        {
            if (animate && Phase is PathSwapPhase.Content or PathSwapPhase.ContentOut)
            {
                Phase = PathSwapPhase.ContentOut;
                await Task.Delay(PathSwapTiming.Fade, session.Time, token);
            }
            // Unmount the old content before anything new shows: no stale chart or automation nodes.
            presentedText = text;
            State = LoadState.Loading;
            Zoom = MinZoom;
            Phase = PathSwapPhase.Spinner;
            if (announce) Announced?.Invoke(this, new Announcement($"Loading {instrument.Label()} {difficulty.Label()} path", AnnouncementKind.Progress));
            var minimum = animate ? Task.Delay(text ? PathSwapTiming.MinTextSpinner : PathSwapTiming.MinImageSpinner, session.Time, token) : Task.CompletedTask;
            var result = await fetch;
            await minimum;
            if (animate)
            {
                Phase = PathSwapPhase.SpinnerOut;
                await Task.Delay(PathSwapTiming.Fade, session.Time, token);
            }
            if (mine != revision) return;
            var summary = Present(result, instrument, difficulty);
            Phase = PathSwapPhase.Content;
            if (announce && summary is not null) Announced?.Invoke(this, new Announcement(summary, AnnouncementKind.Completed));
        }
        catch (OperationCanceledException)
        {
            // Superseded by a newer selection or the dialog closing.
        }
    }

    /// <summary>One read's outcome.</summary>
    /// <param name="Image">Loaded image.</param>
    /// <param name="Data">Loaded table.</param>
    /// <param name="Error">Failure (404 means not generated).</param>
    private sealed record PathFetch(PathImage? Image, SongPathData? Data, FestivalApiException? Error);

    /// <summary>Reads (and prepares) the selection; API failures become a result, cancellation propagates.</summary>
    /// <param name="instrument">Chart.</param>
    /// <param name="difficulty">Difficulty.</param>
    /// <param name="text">Table instead of image.</param>
    /// <param name="token">Cancellation.</param>
    /// <returns>Outcome.</returns>
    private async Task<PathFetch> FetchAsync(Instrument instrument, PathDifficulty difficulty, bool text, CancellationToken token)
    {
        try
        {
            if (text) return new PathFetch(null, await session.Api.GetPathDataAsync(Song.SongId, instrument, difficulty, Song.PathArtifactGenerationId, token), null);
            var picture = await session.Api.GetPathImageAsync(Song.SongId, instrument, difficulty, Song.PathArtifactGenerationId, token);
            if (PrepareImageAsync is { } prepare) await prepare(picture, token);
            return new PathFetch(picture, null, null);
        }
        catch (FestivalApiException error)
        {
            return new PathFetch(null, null, error);
        }
    }

    /// <summary>Presents a read's outcome.</summary>
    /// <param name="result">Outcome.</param>
    /// <param name="instrument">Chart it belongs to.</param>
    /// <param name="difficulty">Difficulty it belongs to.</param>
    /// <returns>Announcement text, or <see langword="null"/> when the status view announces a failure.</returns>
    private string? Present(PathFetch result, Instrument instrument, PathDifficulty difficulty)
    {
        (presentedInstrument, presentedDifficulty) = (instrument, difficulty);
        OnPropertyChanged(nameof(ImageDescription));
        var label = $"{instrument.Label()} {difficulty.Label()}";
        switch (result)
        {
            case { Data: { } path }:
                Data = path;
                Rows = path.ActivationRows();
                Status.Clear();
                State = LoadState.Loaded;
                OnPropertyChanged(nameof(ShowTable));
                return $"{label} path loaded, {(Rows.Count == 1 ? "1 activation" : $"{Rows.Count} activations")}";
            case { Image: { } picture }:
                Image = picture;
                Status.Clear();
                State = LoadState.Loaded;
                OnPropertyChanged(nameof(ShowImage));
                return $"{label} path image loaded";
            case { Error: { Kind: FestivalApiErrorKind.HttpStatus, StatusCode: 404 } }:
                Status.Clear();
                State = LoadState.Empty;
                return NotGeneratedText;
            default:
                Status.Report(result.Error!);
                State = LoadState.Failed;
                return null;
        }
    }

    /// <summary>Cancels any in-flight read (dialog closed).</summary>
    public void Close()
    {
        request?.Cancel();
        revision++;
    }

    /// <summary>Dismisses the warning for this opening, or permanently.</summary>
    /// <param name="permanently">Persist "Don't show again".</param>
    public void DismissWarning(bool permanently)
    {
        ShowWarning = false;
        if (permanently) session.UpdateSettings(s => s with { PathUnavailableWarningDismissed = true });
    }

    /// <summary>Zooms in one step.</summary>
    [RelayCommand]
    private void ZoomIn() => Zoom = Math.Min(MaxZoom, Zoom * ZoomStep);

    /// <summary>Zooms out one step.</summary>
    [RelayCommand]
    private void ZoomOut() => Zoom = Math.Max(MinZoom, Zoom / ZoomStep);

    partial void OnInstrumentIndexChanged(int value)
    {
        OnPropertyChanged(nameof(Instrument));
        Reload();
    }

    partial void OnDifficultyIndexChanged(int value) => Reload();

    partial void OnShowTextChanged(bool value) => Reload();

    /// <summary>Reloads after a selector change (zoom resets once the old chart has faded out).</summary>
    private void Reload() => _ = LoadAsync();
}
#endregion
