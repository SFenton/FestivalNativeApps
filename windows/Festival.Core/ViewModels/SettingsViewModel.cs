using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Settings
/// <summary>
/// Settings page (web <c>SettingsPage.tsx</c>): App Settings, Debug-only Diagnostics, Item Shop, Show Instruments,
/// Show Instrument Metadata, the native additive Accessibility section, Version, live Service Info, First Run Guides,
/// Licenses and an app-only Reset. Every value persists through <see cref="FestivalSession.UpdateSettings"/>.
/// </summary>
public sealed partial class SettingsViewModel : ObservableObject
{
    private readonly FestivalSession session;
    private bool serviceVersionRequested;
    private bool featuresRequested;

    /// <summary>Creates the page model.</summary>
    /// <param name="session">Shared session.</param>
    /// <param name="appVersion">App version shown under Version.</param>
    /// <param name="debugBuild">Whether this is a Debug build (shows Diagnostics).</param>
    public SettingsViewModel(FestivalSession session, string appVersion = "", bool debugBuild = false)
    {
        this.session = session;
        AppVersion = appVersion.Length > 0 ? appVersion : "Unknown";
        IsDebugBuild = debugBuild;
        Instruments = InstrumentInfo.All.Select(i => new InstrumentToggle(this, i)).ToList();
        Metadata = Enum.GetValues<MetadataField>().Select(f => new MetadataToggle(this, f)).ToList();
        FirstRunPages = Enum.GetValues<FirstRunPageKey>().Select(p => new FirstRunReplayItem(p)).ToList();
        QuickLinks = new QuickLinksViewModel("Quick Links", 32);
        QuickLinks.SetSections(QuickLinkSections());
        ServiceInfo = new SettingsServiceInfoViewModel(session.Api, session.Time);
        RebuildOrders();
        session.PropertyChanged += OnSessionChanged;
    }

    /// <summary>Raised when the page should present a first-run replay.</summary>
    public event EventHandler<FirstRunPageKey>? ReplayRequested;

    #region App settings
    /// <summary>Show Instrument Icons.</summary>
    public bool ShowInstrumentIcons
    {
        get => session.Settings.ShowInstrumentIcons;
        set => session.UpdateSettings(s => s with { ShowInstrumentIcons = value });
    }

    /// <summary>Enable Independent Song Row Visual Order.</summary>
    public bool EnableVisualOrder
    {
        get => session.Settings.EnableVisualOrder;
        set => session.UpdateSettings(s => s with { EnableVisualOrder = value });
    }

    /// <summary>Visible song-row metadata fields in their saved order (drag or Move Up/Down to reorder, as on the web).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasVisibleMetadata))]
    private ObservableCollection<ReorderItemViewModel> songRowOrder = [];

    /// <summary>Whether any metadata field is visible (else the list is replaced by the "none visible" sentence).</summary>
    public bool HasVisibleMetadata => SongRowOrder.Count > 0;

    /// <summary>CHOpt text-path column order rows.</summary>
    [ObservableProperty]
    private ObservableCollection<ReorderItemViewModel> pathColumnOrder = [];

    /// <summary>Visible metadata fields in the saved order.</summary>
    public string VisualOrderSummary
    {
        get
        {
            var visible = session.Settings.SongRowVisualOrder.Where(session.Settings.IsMetadataVisible).Select(f => f.Label()).ToList();
            return visible.Count == 0 ? "No metadata fields are currently visible." : string.Join(" · ", visible);
        }
    }

    /// <summary>Saved path column order.</summary>
    public string PathColumnSummary => string.Join(" · ", session.Settings.PathColumnOrder.Select(c => c.Label()));

    /// <summary>Filter Invalid Scores.</summary>
    public bool FilterInvalidScores
    {
        get => session.Settings.FilterInvalidScores;
        set => session.UpdateSettings(s => s with { FilterInvalidScores = value });
    }

    /// <summary>Leeway percent (−5…+5, 0.1 steps).</summary>
    public double Leeway
    {
        get => session.Settings.Leeway;
        set => session.UpdateSettings(s => s with { Leeway = ScoreLeeway.Clamp(value) });
    }

    /// <summary>Slider header, e.g. "Maximum Score Leeway: +1.0%".</summary>
    public string LeewayText => $"Maximum Score Leeway: {ScoreLeeway.Format(Leeway)}";

    /// <summary>Slider value text for Narrator.</summary>
    public string LeewayValue => ScoreLeeway.Format(Leeway);

    /// <summary>Web <c>maxScoreLeewayDesc</c> with live numbers.</summary>
    public string LeewayDescription =>
        $"This slider controls a percentage value that allows for some expanded range of scores to still be valid. For example, a CHOpt path with a max score of 100k and {ScoreLeeway.Format(Leeway)} leeway will allow the app to accept scores up to {ScoreLeeway.MaxEffectiveScore(Leeway).ToString("N0", CultureInfo.GetCultureInfo("en-US"))} as “valid”.";

    /// <summary>CHOpt path default view (0 Image, 1 Text) for the RadioButtons.</summary>
    public int PathDefaultViewIndex
    {
        get => (int)session.Settings.PathDefaultView;
        set
        {
            if (value is 0 or 1) session.UpdateSettings(s => s with { PathDefaultView = (PathDisplayMode)value });
        }
    }

    /// <summary>Experimental ranks (not yet available: shown off and disabled).</summary>
    public bool ExperimentalRanks => session.Settings.ExperimentalRanks;
    #endregion

    #region Diagnostics
    /// <summary>Whether this is a Debug build (Diagnostics visible).</summary>
    public bool IsDebugBuild { get; }

    /// <summary>Tap Diagnostics (off also turns telemetry off).</summary>
    public bool TapDiagnostics
    {
        get => session.Settings.TapDiagnostics;
        set => session.UpdateSettings(s => s with { TapDiagnostics = value, TapTelemetry = value && s.TapTelemetry });
    }

    /// <summary>Upload Tap Telemetry (requires diagnostics).</summary>
    public bool TapTelemetry
    {
        get => session.Settings.TapTelemetry;
        set => session.UpdateSettings(s => s with { TapTelemetry = value && s.TapDiagnostics });
    }

    /// <summary>Telemetry toggle description (web copy).</summary>
    public string TapTelemetryDescription => TapDiagnostics
        ? "Send sanitized tap diagnostic batches to the development service logs while diagnostics are enabled."
        : "Enable Tap Diagnostics first, then upload sanitized batches to the development service logs.";
    #endregion

    #region Item Shop
    /// <summary>Hide Item Shop.</summary>
    public bool HideShop
    {
        get => session.Settings.HideShop;
        set => session.UpdateSettings(s => s with { HideShop = value });
    }

    /// <summary>Disable Item Shop Highlighting (web wording and polarity; kept while the Shop is hidden).</summary>
    public bool DisableShopHighlighting
    {
        get => session.Settings.DisableShopHighlighting;
        set => session.UpdateSettings(s => s with { DisableShopHighlighting = value });
    }

    /// <summary>Whether highlighting can change (not while the Shop is hidden).</summary>
    public bool CanToggleShopHighlight => !HideShop;
    #endregion

    #region Instruments and metadata
    /// <summary>One toggle per chart in service order.</summary>
    public List<InstrumentToggle> Instruments { get; }

    /// <summary>One toggle per metadata field.</summary>
    public List<MetadataToggle> Metadata { get; }

    /// <summary>Metadata section subtitle (web hint, adjusted for the anonymous state as on iPhone).</summary>
    public string MetadataDescription => session.HasPlayer
        ? "When filtering songs down to one instrument in the song list, extra metadata for that song can appear. Choose what you'd like to see in the song row here."
        : "Select a player to customize score metadata. Intensity also applies to rows without a player.";

    /// <summary>Whether a chart is visible.</summary>
    /// <param name="instrument">Chart.</param>
    /// <returns>Visibility.</returns>
    internal bool IsVisible(Instrument instrument) => session.Settings.VisibleInstruments.Contains(instrument);

    /// <summary>Whether a chart's toggle can change (the last visible chart cannot be turned off).</summary>
    /// <param name="instrument">Chart.</param>
    /// <returns><see langword="true"/> when editable.</returns>
    internal bool CanToggle(Instrument instrument) => !(IsVisible(instrument) && session.Settings.VisibleInstruments.Count == 1);

    /// <summary>Sets a chart's visibility.</summary>
    /// <param name="instrument">Chart.</param>
    /// <param name="visible">Visibility.</param>
    internal void SetVisible(Instrument instrument, bool visible) =>
        session.UpdateSettings(s => s.WithInstrumentVisible(instrument, visible));

    /// <summary>Whether a metadata field is on.</summary>
    /// <param name="field">Field.</param>
    /// <returns>Visibility.</returns>
    internal bool IsMetadataOn(MetadataField field) => session.Settings.IsMetadataVisible(field);

    /// <summary>Whether a metadata switch is editable: all with a player, only Intensity without one.</summary>
    /// <param name="field">Field.</param>
    /// <returns><see langword="true"/> when editable.</returns>
    internal bool CanToggleMetadata(MetadataField field) => session.HasPlayer || field == MetadataField.Intensity;

    /// <summary>Sets a metadata field.</summary>
    /// <param name="field">Field.</param>
    /// <param name="on">Visibility.</param>
    internal void SetMetadata(MetadataField field, bool on) => session.UpdateSettings(s => s.WithMetadataVisible(field, on));
    #endregion

    #region Accessibility
    /// <summary>Additive reduce motion.</summary>
    public bool ReduceMotion
    {
        get => session.Settings.ReduceMotion;
        set => session.UpdateSettings(s => s with { ReduceMotion = value });
    }

    /// <summary>Additive: stop artwork animation.</summary>
    public bool DisableAnimatedArtwork
    {
        get => session.Settings.DisableAnimatedArtwork;
        set => session.UpdateSettings(s => s with { DisableAnimatedArtwork = value });
    }

    /// <summary>Additive: no artwork (data saving).</summary>
    public bool SaveData
    {
        get => session.Settings.SaveData;
        set => session.UpdateSettings(s => s with { SaveData = value });
    }

    /// <summary>Additive: increase contrast.</summary>
    public bool MoreContrast
    {
        get => session.Settings.MoreContrast;
        set => session.UpdateSettings(s => s with { MoreContrast = value });
    }

    /// <summary>Additive: reduce transparency.</summary>
    public bool LessTransparency
    {
        get => session.Settings.LessTransparency;
        set => session.UpdateSettings(s => s with { LessTransparency = value });
    }
    #endregion

    #region Version and service
    /// <summary>App version.</summary>
    public string AppVersion { get; }

    /// <summary>Build configuration.</summary>
    public string BuildConfiguration => IsDebugBuild ? "Debug" : "Release";

    /// <summary>Service build version from <c>/api/version</c> ("Loading" until read, "Unavailable" on failure).</summary>
    [ObservableProperty]
    private string serviceVersion = "Loading";

    /// <summary>Service origin.</summary>
    public string ServiceOrigin => session.Api.BaseUri.GetLeftPart(UriPartial.Authority);

    /// <summary>Live Service Info card.</summary>
    public SettingsServiceInfoViewModel ServiceInfo { get; }

    /// <summary>
    /// Whether Report an Issue / Request a Feature show: only after <c>GET /api/features</c> reports
    /// <c>feedback: true</c> (hidden while unknown, off or unreadable; issue #78).
    /// </summary>
    [ObservableProperty]
    private bool feedbackAvailable;

    /// <summary>Settings became visible: start Service Info polling and read the service version and features once.</summary>
    public void Activate()
    {
        ServiceInfo.Start();
        if (!featuresRequested)
        {
            featuresRequested = true;
            _ = LoadFeaturesAsync();
        }
        if (serviceVersionRequested) return;
        serviceVersionRequested = true;
        _ = LoadServiceVersionAsync();
    }

    /// <summary>Reads <c>/api/features</c> (a pure, keyless read); a failure hides the rows and allows a later retry.</summary>
    /// <returns>Task.</returns>
    internal async Task LoadFeaturesAsync()
    {
        try
        {
            FeedbackAvailable = await session.Api.GetFeedbackEnabledAsync();
        }
        catch (FestivalApiException)
        {
            FeedbackAvailable = false;
            featuresRequested = false;
        }
    }

    /// <summary>Settings hidden: stop polling.</summary>
    public void Deactivate() => ServiceInfo.Stop();

    /// <summary>Reads <c>/api/version</c> (a pure, keyless read); a failure allows a later retry.</summary>
    /// <returns>Task.</returns>
    internal async Task LoadServiceVersionAsync()
    {
        try
        {
            ServiceVersion = await session.Api.GetServiceVersionAsync();
        }
        catch (FestivalApiException)
        {
            ServiceVersion = "Unavailable";
            serviceVersionRequested = false;
        }
    }
    #endregion

    #region First run, quick links and reset
    /// <summary>First Run Guides rows.</summary>
    public List<FirstRunReplayItem> FirstRunPages { get; }

    /// <summary>Opens a page's replay (every slide, gates and seen-state ignored).</summary>
    /// <param name="page">Page.</param>
    [RelayCommand]
    private void ReplayFirstRun(FirstRunPageKey page) => ReplayRequested?.Invoke(this, page);

    /// <summary>Page Quick Links.</summary>
    public QuickLinksViewModel QuickLinks { get; }

    /// <summary>
    /// Restores app settings (profile, Songs sort/filter and navigation stay) and deletes Reset-owned feature state
    /// such as the Suggestions filter (<see cref="AppStateFiles"/>).
    /// </summary>
    [RelayCommand]
    private void ResetAppSettings()
    {
        session.UpdateSettings(s => s.ResetAppSettings());
        session.ResetFeatureState();
    }

    /// <summary>Settings quick-link sections in web order (Diagnostics only in Debug).</summary>
    /// <returns>Sections.</returns>
    private List<QuickLinkSection> QuickLinkSections()
    {
        var sections = new List<QuickLinkSection> { new("app-settings", "App Settings", "") };
        if (IsDebugBuild) sections.Add(new("diagnostics", "Diagnostics", ""));
        sections.AddRange(
        [
            new("item-shop", "Item Shop", ""),
            new("show-instruments", "Show Instruments", ""),
            new("show-metadata", "Show Instrument Metadata", ""),
            new("accessibility", "Accessibility", ""),
            new("version", "Version", ""),
            new("service-info", "Service Info", ""),
            new("first-run", "First Run Guides", ""),
            new("licenses", "Licenses", ""),
            new("privacy-policy", "Privacy Policy", ""),
            new("reset", "Reset Settings", ""),
        ]);
        return sections;
    }
    #endregion

    #region Orders
    /// <summary>
    /// Saves a new visible song-row order (after a drag or a move); fields hidden in Show Instrument Metadata keep their
    /// relative order after the visible ones, as on the web.
    /// </summary>
    /// <param name="visible">Visible fields in their new order.</param>
    public void ApplySongRowOrder(IEnumerable<MetadataField> visible)
    {
        var order = visible.ToList();
        session.UpdateSettings(s => s with
        {
            SongRowVisualOrder = SettingsOrder.Normalize([.. order, .. s.SongRowVisualOrder.Where(f => !order.Contains(f))]),
        });
        RebuildOrders();
    }

    /// <summary>Saves a new CHOpt text-path column order.</summary>
    /// <param name="columns">Columns in their new order.</param>
    public void ApplyPathColumnOrder(IEnumerable<PathColumnKey> columns)
    {
        var order = columns.ToList();
        session.UpdateSettings(s => s with { PathColumnOrder = SettingsOrder.Normalize(order) });
        RebuildOrders();
    }

    /// <summary>Persists a list's row order after a drag (the ListView moved its items in place).</summary>
    /// <param name="rows">Rows in their dropped order.</param>
    public void CommitDrag(IEnumerable<ReorderItemViewModel> rows)
    {
        var list = rows.ToList();
        if (list.Count == 0) return;
        if (list.All(r => r.Key is MetadataField)) ApplySongRowOrder(list.Select(r => (MetadataField)r.Key));
        else if (list.All(r => r.Key is PathColumnKey)) ApplyPathColumnOrder(list.Select(r => (PathColumnKey)r.Key));
    }

    /// <summary>Moves a visible song-row field.</summary>
    /// <param name="index">Index among visible fields.</param>
    /// <param name="offset">-1 or +1.</param>
    internal void MoveSongRowField(int index, int offset) =>
        ApplySongRowOrder(SettingsOrder.Move([.. SongRowOrder.Select(r => (MetadataField)r.Key)], index, offset));

    /// <summary>Moves a path column.</summary>
    /// <param name="index">Index.</param>
    /// <param name="offset">-1 or +1.</param>
    internal void MovePathColumn(int index, int offset) =>
        ApplyPathColumnOrder(SettingsOrder.Move([.. PathColumnOrder.Select(r => (PathColumnKey)r.Key)], index, offset));

    /// <summary>Rebuilds reorder rows when the saved orders, visibility or row indices change.</summary>
    private void RebuildOrders()
    {
        var rows = session.Settings.SongRowVisualOrder.Where(session.Settings.IsMetadataVisible).ToList();
        if (!IsCurrent(SongRowOrder, [.. rows.Cast<object>()]))
            SongRowOrder = [.. rows.Select((f, i) => new ReorderItemViewModel(f, f.Label(), "fst.settings.song-row-order." + f.Token(), i, rows.Count, MoveSongRowField))];
        var columns = session.Settings.PathColumnOrder;
        if (!IsCurrent(PathColumnOrder, [.. columns.Cast<object>()]))
            PathColumnOrder = [.. columns.Select((c, i) => new ReorderItemViewModel(c, c.Label(), "fst.settings.path-column-order." + c.ToString().ToLowerInvariant(), i, columns.Count, MovePathColumn))];
    }

    /// <summary>Whether rows already show these keys with matching indices.</summary>
    /// <param name="rows">Current rows.</param>
    /// <param name="keys">Saved keys.</param>
    /// <returns><see langword="true"/> when no rebuild is needed.</returns>
    private static bool IsCurrent(IList<ReorderItemViewModel> rows, List<object> keys) =>
        rows.Count == keys.Count && rows.Select((r, i) => r.Key.Equals(keys[i]) && r.Index == i && r.Count == keys.Count).All(ok => ok);
    #endregion

    /// <summary>Re-raises derived properties on settings changes.</summary>
    /// <param name="sender">Session.</param>
    /// <param name="e">Changed property.</param>
    private void OnSessionChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(FestivalSession.Settings)) return;
        foreach (var toggle in Instruments) toggle.Refresh();
        foreach (var toggle in Metadata) toggle.Refresh();
        RebuildOrders();
        OnPropertyChanged(string.Empty);
    }
}
#endregion

#region Rows
/// <summary>One chart's visibility switch.</summary>
public sealed partial class InstrumentToggle : ObservableObject
{
    private readonly SettingsViewModel owner;

    /// <summary>Creates the toggle.</summary>
    /// <param name="owner">Settings page model.</param>
    /// <param name="instrument">Chart.</param>
    internal InstrumentToggle(SettingsViewModel owner, Instrument instrument)
    {
        this.owner = owner;
        Instrument = instrument;
    }

    /// <summary>Chart.</summary>
    public Instrument Instrument { get; }

    /// <summary>Label.</summary>
    public string Label => Instrument.Label();

    /// <summary>Icon file.</summary>
    public string IconFile => Instrument.IconFile();

    /// <summary>Stable automation ID.</summary>
    public string AutomationId => "fst.settings.instrument." + Instrument.ServiceId();

    /// <summary>Whether the chart is visible.</summary>
    public bool IsOn
    {
        get => owner.IsVisible(Instrument);
        set
        {
            if (value != IsOn) owner.SetVisible(Instrument, value);
        }
    }

    /// <summary>Whether the switch is enabled.</summary>
    public bool IsEnabled => owner.CanToggle(Instrument);

    /// <summary>Why the switch is disabled, for its description.</summary>
    public string Description => IsEnabled ? "" : "At least one instrument must stay visible.";

    /// <summary>Raises all derived properties.</summary>
    internal void Refresh()
    {
        OnPropertyChanged(nameof(IsOn));
        OnPropertyChanged(nameof(IsEnabled));
        OnPropertyChanged(nameof(Description));
    }
}

/// <summary>One metadata field switch.</summary>
public sealed partial class MetadataToggle : ObservableObject
{
    private readonly SettingsViewModel owner;

    /// <summary>Creates the toggle.</summary>
    /// <param name="owner">Settings page model.</param>
    /// <param name="field">Field.</param>
    internal MetadataToggle(SettingsViewModel owner, MetadataField field)
    {
        this.owner = owner;
        Field = field;
    }

    /// <summary>Field.</summary>
    public MetadataField Field { get; }

    /// <summary>Label.</summary>
    public string Label => Field.Label();

    /// <summary>Automation ID.</summary>
    public string AutomationId => "fst.settings.metadata." + Field.Token();

    /// <summary>Whether the field is shown.</summary>
    public bool IsOn
    {
        get => owner.IsMetadataOn(Field);
        set
        {
            if (value != IsOn) owner.SetMetadata(Field, value);
        }
    }

    /// <summary>Whether the switch is enabled.</summary>
    public bool IsEnabled => owner.CanToggleMetadata(Field);

    /// <summary>Why the switch is disabled.</summary>
    public string Description => IsEnabled ? "" : "Select a player to use score metadata.";

    /// <summary>Raises derived properties.</summary>
    internal void Refresh()
    {
        OnPropertyChanged(nameof(IsOn));
        OnPropertyChanged(nameof(IsEnabled));
        OnPropertyChanged(nameof(Description));
    }
}

/// <summary>One row of a drag-to-reorder list, with Move Up/Move Down for keyboard and Narrator users.</summary>
public sealed partial class ReorderItemViewModel
{
    private readonly Action<int, int> move;

    /// <summary>Creates a row.</summary>
    /// <param name="key">Field or column this row stands for.</param>
    /// <param name="label">Label.</param>
    /// <param name="automationId">Automation ID.</param>
    /// <param name="index">Index.</param>
    /// <param name="count">Row count.</param>
    /// <param name="move">Move callback (index, offset).</param>
    internal ReorderItemViewModel(object key, string label, string automationId, int index, int count, Action<int, int> move)
    {
        Key = key;
        Label = label;
        AutomationId = automationId;
        Index = index;
        Count = count;
        this.move = move;
    }

    /// <summary>Field (<see cref="MetadataField"/>) or column (<see cref="PathColumnKey"/>).</summary>
    public object Key { get; }

    /// <summary>Label.</summary>
    public string Label { get; }

    /// <summary>Automation ID.</summary>
    public string AutomationId { get; }

    /// <summary>Index.</summary>
    public int Index { get; }

    /// <summary>Row count.</summary>
    public int Count { get; }

    /// <summary>Position label, e.g. "1".</summary>
    public string Position => (Index + 1).ToString(CultureInfo.InvariantCulture);

    /// <summary>Narrator name, e.g. "Score, position 1 of 8".</summary>
    public string AccessibleName => $"{Label}, position {Index + 1} of {Count}";

    /// <summary>Move Up button name.</summary>
    public string MoveUpName => $"Move {Label} up";

    /// <summary>Move Down button name.</summary>
    public string MoveDownName => $"Move {Label} down";

    /// <summary>Whether Move Up is possible.</summary>
    public bool CanMoveUp => Index > 0;

    /// <summary>Whether Move Down is possible.</summary>
    public bool CanMoveDown => Index < Count - 1;

    /// <summary>Moves up one place.</summary>
    [RelayCommand(CanExecute = nameof(CanMoveUp))]
    private void MoveUp() => move(Index, -1);

    /// <summary>Moves down one place.</summary>
    [RelayCommand(CanExecute = nameof(CanMoveDown))]
    private void MoveDown() => move(Index, 1);
}

/// <summary>One First Run Guides row.</summary>
/// <param name="page">Page.</param>
public sealed class FirstRunReplayItem(FirstRunPageKey page)
{
    /// <summary>Page.</summary>
    public FirstRunPageKey Page { get; } = page;

    /// <summary>Label.</summary>
    public string Label => Page.Label();

    /// <summary>Automation ID.</summary>
    public string AutomationId => "fst.settings.first-run." + Page.Key();

    /// <summary>Accessible button name.</summary>
    public string ButtonName => $"Show {Label} guide";
}
#endregion
