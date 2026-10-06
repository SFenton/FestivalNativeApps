using CommunityToolkit.Mvvm.ComponentModel;

namespace Festival.Core.ViewModels;

#region Service info card
/// <summary>
/// Settings "Service Info" card (web <c>useServiceInfo('settings')</c> + <c>SettingsServiceProgressCard</c>): polls the keyless
/// operational <c>GET /api/service-info</c> every 5 s only while Settings is shown (30 s while the window is hidden), with
/// the web's 3 s request timeout, and reduces each read through <see cref="ServiceProgressReducer"/>. A failure after a
/// success shows the failure rather than silently keeping old progress. Like the web card, percent and units are spoken
/// on the phase row rather than printed, band discovery adds its attempt line, and the publication row only shows once
/// a read succeeded.
/// </summary>
public sealed partial class SettingsServiceInfoViewModel : ObservableObject
{
    /// <summary>Web <c>SERVICE_INFO_SETTINGS_POLL_MS</c> / <c>…_UNAVAILABLE_RETRY_MS</c>.</summary>
    public static readonly TimeSpan PollInterval = TimeSpan.FromSeconds(5);

    /// <summary>Web <c>SERVICE_INFO_BACKGROUND_POLL_MS</c> while the window is hidden.</summary>
    public static readonly TimeSpan BackgroundPollInterval = TimeSpan.FromSeconds(30);

    /// <summary>Web <c>SERVICE_INFO_TIMEOUT_MS</c>.</summary>
    public static readonly TimeSpan RequestTimeout = TimeSpan.FromSeconds(3);

    /// <summary>
    /// Parses the Debug/automation <c>FST_DEBUG_SERVICE_INFO_TIMEOUT_MS</c> hook, which lengthens the request timeout so a UI
    /// Automation journey can open Settings, scroll to the card and scan it while a held first read keeps it Loading.
    /// </summary>
    /// <param name="milliseconds">Hook value.</param>
    /// <returns>The timeout, or <see langword="null"/> unless it is a whole number of milliseconds from 1 to 60,000.</returns>
    public static TimeSpan? ParseTimeoutOverride(string? milliseconds) =>
        int.TryParse(milliseconds, System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out var ms)
        && ms is > 0 and <= 60_000 ? TimeSpan.FromMilliseconds(ms) : null;

    private readonly FestivalApiClient api;
    private readonly TimeProvider time;
    private readonly Func<TimeZoneInfo> zone;
    private ServiceProgressMemory? memory;
    private CancellationTokenSource? polling;
    private CancellationTokenSource? wait;
    private bool background;

    /// <summary>Creates the card model (loading until the first read).</summary>
    /// <param name="api">Service client.</param>
    /// <param name="time">Clock for polling and timeouts.</param>
    /// <param name="zone">Display zone provider (fixed in tests).</param>
    public SettingsServiceInfoViewModel(FestivalApiClient api, TimeProvider time, Func<TimeZoneInfo>? zone = null)
    {
        this.api = api;
        this.time = time;
        this.zone = zone ?? (() => TimeZoneInfo.Local);
    }

    #region Rows
    /// <summary>Leading row description (phase while updating, else the status sentence).</summary>
    [ObservableProperty]
    private string stateDescription = "Loading";

    /// <summary>Trailing process state.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ProcessStateText), nameof(ShowsSpinner))]
    private ServiceProcessState processState = ServiceProcessState.Loading;

    /// <summary>Phase row title, or <see langword="null"/> when there is no phase to show.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasPhase), nameof(PhaseAccessibleName))]
    private string? phaseTitle;

    /// <summary>Spoken phase title: phase and subphase as separate sentences (web <c>aria-valuetext</c>), not "Phase · Subphase".</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(PhaseAccessibleName))]
    private string? spokenPhaseTitle;

    /// <summary>Whether the bar shows.</summary>
    [ObservableProperty]
    private bool hasBar;

    /// <summary>Whether the bar is indeterminate (total unknown).</summary>
    [ObservableProperty]
    private bool isIndeterminate;

    /// <summary>Bar value 0–100.</summary>
    [ObservableProperty]
    private double barPercent;

    /// <summary>"42.5%" or "Total not yet known"; spoken on the phase row, not printed (web parity).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(PhaseAccessibleName))]
    private string? progressText;

    /// <summary>Units sentence; spoken on the phase row, not printed (web parity).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(PhaseAccessibleName))]
    private string? unitsText;

    /// <summary>Band discovery attempt line under the bar (web <c>discoveryAttemptText</c>).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasAttempt), nameof(PhaseAccessibleName))]
    private string? attemptText;

    /// <summary>Last successful publication, or <see langword="null"/> while loading or failed (web shows only the state row).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasLastPublished))]
    private string? lastPublished;

    /// <summary>Process state label.</summary>
    public string ProcessStateText => ProcessState.Label();

    /// <summary>Whether the small ring spins beside the state (loading or updating).</summary>
    public bool ShowsSpinner => ProcessState is ServiceProcessState.Loading or ServiceProcessState.Updating;

    /// <summary>Whether a phase row shows.</summary>
    public bool HasPhase => PhaseTitle is not null;

    /// <summary>Whether the attempt line shows.</summary>
    public bool HasAttempt => AttemptText is not null;

    /// <summary>Whether the publication row shows.</summary>
    public bool HasLastPublished => LastPublished is not null;

    /// <summary>
    /// Narrator name for the phase row, joined like the web bar's <c>aria-valuetext</c>: phase, subphase, progress, units
    /// and attempts.
    /// </summary>
    public string PhaseAccessibleName =>
        string.Join(". ", new[] { SpokenPhaseTitle ?? PhaseTitle, HasBar ? ProgressText : null, UnitsText, AttemptText }.Where(s => s is not null));

    /// <summary>Whether polling is running.</summary>
    public bool IsPolling => polling is not null;

    /// <summary>Per-read timeout: <see cref="RequestTimeout"/> unless an automation hook lengthens it (<see cref="ParseTimeoutOverride"/>).</summary>
    public TimeSpan ReadTimeout { get; set; } = RequestTimeout;
    #endregion

    #region Polling
    /// <summary>Starts polling (idempotent).</summary>
    public void Start()
    {
        if (polling is not null) return;
        polling = new CancellationTokenSource();
        _ = PollAsync(polling.Token);
    }

    /// <summary>Stops polling (Settings hidden).</summary>
    public void Stop()
    {
        polling?.Cancel();
        polling = null;
    }

    /// <summary>Whether the window is hidden (slower cadence); wakes a pending wait so the new cadence applies.</summary>
    public bool Background
    {
        get => background;
        set
        {
            if (background == value) return;
            background = value;
            if (!value) wait?.Cancel();
        }
    }

    /// <summary>Reads until cancelled.</summary>
    /// <param name="token">Stop token.</param>
    /// <returns>Task.</returns>
    private async Task PollAsync(CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            await PollOnceAsync(token);
            if (token.IsCancellationRequested) return;
            using var delay = CancellationTokenSource.CreateLinkedTokenSource(token);
            wait = delay;
            try
            {
                await Task.Delay(Background ? BackgroundPollInterval : PollInterval, time, delay.Token);
            }
            catch (OperationCanceledException)
            {
                // Stopped, or woken early by returning to the foreground.
            }
            finally
            {
                wait = null;
            }
        }
    }

    /// <summary>One read with the web's timeout (<see cref="ReadTimeout"/>).</summary>
    /// <param name="token">Stop token.</param>
    /// <returns>Task.</returns>
    internal async Task PollOnceAsync(CancellationToken token)
    {
        using var timeout = new CancellationTokenSource(ReadTimeout, time);
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(token, timeout.Token);
        try
        {
            Apply(await api.GetServiceInfoAsync(linked.Token));
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested)
        {
            // Stopped.
        }
        catch (Exception error) when (error is FestivalApiException or OperationCanceledException)
        {
            ApplyFailure();
        }
    }
    #endregion

    #region State
    /// <summary>Folds one successful read into the rows.</summary>
    /// <param name="snapshot">Read.</param>
    internal void Apply(ServiceInfoSnapshot snapshot)
    {
        var info = snapshot.Info;
        var (display, next) = ServiceProgressReducer.Reduce(memory, info);
        memory = next;
        var updating = info.CurrentUpdate?.Status == "updating";
        var state = ServiceInfoText.ProcessState(info);
        var phaseLabel = ServiceInfoText.PhaseLabel(info, display);
        var showPhase = updating || display.PhaseId is not null || info.CurrentUpdate?.Phase is not null;
        var bar = display.BarProgress;
        var showBar = updating && bar?.Kind != ServiceBarKind.NotApplicable;
        var determinate = bar is { Kind: ServiceBarKind.Exact, Percent: not null };

        StateDescription = updating ? phaseLabel : ServiceInfoText.ServiceState(info, state);
        ProcessState = state;
        HasBar = showBar;
        IsIndeterminate = showBar && !determinate;
        BarPercent = determinate ? bar!.Percent!.Value : 0;
        ProgressText = showBar ? ServiceInfoText.ProgressText(bar) : null;
        UnitsText = showBar ? ServiceInfoText.UnitsText(bar) : null;
        AttemptText = showBar ? ServiceInfoText.DiscoveryAttemptText(display) : null;
        var subphaseLabel = showPhase ? ServiceInfoText.SubphaseLabel(info, display) : null;
        var phaseTitle = showPhase ? ServiceInfoText.PhaseTitle(phaseLabel, subphaseLabel) : null;
        SpokenPhaseTitle = phaseTitle is null || phaseTitle == phaseLabel ? null : $"{phaseLabel}. {subphaseLabel}";
        PhaseTitle = phaseTitle;
        LastPublished = ServiceInfoText.LastPublished(info, zone());
    }

    /// <summary>Shows the failed state (web "Failed to load data"): the state row only.</summary>
    internal void ApplyFailure()
    {
        memory = null;
        StateDescription = "Failed to load data";
        ProcessState = ServiceProcessState.Stopped;
        HasBar = false;
        IsIndeterminate = false;
        ProgressText = null;
        UnitsText = null;
        AttemptText = null;
        SpokenPhaseTitle = null;
        PhaseTitle = null;
        LastPublished = null;
    }
    #endregion
}
#endregion
