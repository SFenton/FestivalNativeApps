using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Paths
/// <summary>
/// CHOpt Paths dialog: instrument, difficulty and image/text selectors reset on every opening; image and text
/// each load independently and an older request never paints after a newer choice.
/// </summary>
public sealed partial class SongPathsViewModel : ObservableObject
{
    /// <summary>Zoom steps for the image.</summary>
    public const double MinZoom = 1, MaxZoom = 3, ZoomStep = 1.5;

    private readonly FestivalSession session;
    private CancellationTokenSource? request;
    private int revision;

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
        showText = session.Settings.PathDefaultView == PathDisplayMode.Text;
        Status = new ServiceStatusViewModel($"paths:{song.SongId}", "Path unavailable", LoadAsync, session.Time);
        ShowWarning = session.Settings.VisibleInstruments.Contains(Instrument.Karaoke) && !session.Settings.PathUnavailableWarningDismissed;
    }

    /// <summary>Song.</summary>
    public Song Song { get; }

    /// <summary>Selectable instruments.</summary>
    public List<Instrument> Instruments { get; }

    /// <summary>Instrument labels for the picker.</summary>
    public List<string> InstrumentLabels { get; }

    /// <summary>Difficulty labels for the segmented picker.</summary>
    public List<string> DifficultyLabels { get; } = [.. PathDifficultyInfo.All.Select(d => d.Label())];

    /// <summary>Failed-read presentation.</summary>
    public ServiceStatusViewModel Status { get; }

    /// <summary>Whether the Karaoke-unavailable warning shows on this opening.</summary>
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

    /// <summary>Load lifecycle for the current selection.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsLoading), nameof(ShowImage), nameof(ShowTable), nameof(ShowError), nameof(ShowNotGenerated))]
    private LoadState state = LoadState.Idle;

    /// <summary>Loaded image.</summary>
    [ObservableProperty]
    private PathImage? image;

    /// <summary>Loaded text data.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Summary), nameof(MaxScoreText))]
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

    /// <summary>Whether loading.</summary>
    public bool IsLoading => State is LoadState.Loading or LoadState.Idle;

    /// <summary>Whether the image shows.</summary>
    public bool ShowImage => State == LoadState.Loaded && !ShowText && Image is not null;

    /// <summary>Whether the table shows.</summary>
    public bool ShowTable => State == LoadState.Loaded && ShowText && Data is not null;

    /// <summary>Whether the error shows.</summary>
    public bool ShowError => State == LoadState.Failed;

    /// <summary>Whether the service has no path for this chart and difficulty (HTTP 404).</summary>
    public bool ShowNotGenerated => State == LoadState.Empty;

    /// <summary>Path summary line.</summary>
    public string Summary => Data is { } d ? (string.IsNullOrWhiteSpace(d.PathSummary) ? "No path summary provided" : d.PathSummary) : "";

    /// <summary>"Max score: 123,456".</summary>
    public string MaxScoreText => Data is { } d ? "Max score: " + ScoreFormatting.Score(d.TotalScore) : "";

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

    /// <summary>Spoken image description.</summary>
    public string ImageDescription => $"{Instrument.Label()} {Difficulty.Label()} CHOpt path";

    /// <summary>Loads the current selection (first call on open; selector changes reload automatically).</summary>
    /// <returns>Load task.</returns>
    public async Task LoadAsync()
    {
        request?.Cancel();
        var cancellation = request = new CancellationTokenSource();
        var mine = ++revision;
        var (instrument, difficulty, text) = (Instrument, Difficulty, ShowText);
        State = LoadState.Loading;
        try
        {
            if (text)
            {
                var path = await session.Api.GetPathDataAsync(Song.SongId, instrument, difficulty, Song.PathArtifactGenerationId, cancellation.Token);
                if (mine != revision) return;
                Data = path;
                Rows = path.ActivationRows();
            }
            else
            {
                var picture = await session.Api.GetPathImageAsync(Song.SongId, instrument, difficulty, Song.PathArtifactGenerationId, cancellation.Token);
                if (mine != revision) return;
                Image = picture;
            }
            Status.Clear();
            State = LoadState.Loaded;
            OnPropertyChanged(nameof(ShowImage));
            OnPropertyChanged(nameof(ShowTable));
        }
        catch (OperationCanceledException)
        {
            // Superseded by a newer selection or the dialog closing.
        }
        catch (FestivalApiException error) when (error is { Kind: FestivalApiErrorKind.HttpStatus, StatusCode: 404 })
        {
            if (mine != revision) return;
            Status.Clear();
            State = LoadState.Empty;
        }
        catch (FestivalApiException error)
        {
            if (mine != revision) return;
            Status.Report(error);
            State = LoadState.Failed;
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

    partial void OnInstrumentIndexChanged(int value) => Reload();

    partial void OnDifficultyIndexChanged(int value) => Reload();

    partial void OnShowTextChanged(bool value) => Reload();

    /// <summary>Resets zoom and reloads after a selector change.</summary>
    private void Reload()
    {
        Zoom = MinZoom;
        OnPropertyChanged(nameof(ImageDescription));
        _ = LoadAsync();
    }
}
#endregion
