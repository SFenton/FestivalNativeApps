using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Toggle row
/// <summary>One switch in the Suggestions filter flyout; writes through to the owning draft.</summary>
public sealed partial class SuggestionFilterToggle : ObservableObject
{
    private readonly Action<bool> write;
    private bool syncing;

    /// <summary>Creates a switch.</summary>
    /// <param name="label">Title Case label.</param>
    /// <param name="description">Secondary line (types only).</param>
    /// <param name="iconFile">Instrument icon file (instruments only).</param>
    /// <param name="automationId">Automation ID.</param>
    /// <param name="value">Initial value.</param>
    /// <param name="write">Applies a user change to the draft.</param>
    internal SuggestionFilterToggle(string label, string description, string iconFile, string automationId, bool value, Action<bool> write)
    {
        Label = label;
        Description = description;
        IconFile = iconFile;
        AutomationId = automationId;
        this.write = write;
        isOn = value;
    }

    /// <summary>Label.</summary>
    public string Label { get; }

    /// <summary>Secondary text.</summary>
    public string Description { get; }

    /// <summary>Icon file, or empty.</summary>
    public string IconFile { get; }

    /// <summary>Whether an icon is shown.</summary>
    public bool HasIcon => IconFile.Length > 0;

    /// <summary>Automation ID.</summary>
    public string AutomationId { get; }

    /// <summary>Switch value.</summary>
    [ObservableProperty]
    private bool isOn;

    /// <summary>Updates the value from the draft without writing back.</summary>
    /// <param name="value">Value.</param>
    internal void Sync(bool value)
    {
        syncing = true;
        IsOn = value;
        syncing = false;
    }

    partial void OnIsOnChanged(bool value)
    {
        if (!syncing) write(value);
    }
}
#endregion

#region Filter draft
/// <summary>
/// Suggestions filter (web <c>SuggestionsFilterModal</c>): Instruments, General types and per-instrument types with an
/// instrument picker, plus Reset. Live once <see cref="Begin"/> has loaded the applied filter: every switch applies at
/// once (operator 2026-09-28), so there is no Cancel or Apply.
/// </summary>
public sealed partial class SuggestionsFilterDraft : ObservableObject
{
    private readonly SuggestionsViewModel owner;
    private IReadOnlyList<Instrument> instruments = [];
    private Instrument? detailInstrument;

    /// <summary>Creates the draft.</summary>
    /// <param name="owner">Page model that applies it.</param>
    internal SuggestionsFilterDraft(SuggestionsViewModel owner)
    {
        this.owner = owner;
        draft = owner.Filter;
    }

    /// <summary>Staged value.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanApply))]
    [NotifyCanExecuteChangedFor(nameof(ResetCommand))]
    private SuggestionFilterSettings draft;

    /// <summary>
    /// Instrument whose per-type switches are shown (the Instrument Selector's selection; none on every opening, like the
    /// web's <c>deferSelection</c> selector).
    /// </summary>
    [ObservableProperty]
    private Instrument? selectedInstrument;

    /// <summary>Instrument visibility switches (Settings-visible charts).</summary>
    public ObservableCollection<SuggestionFilterToggle> InstrumentToggles { get; } = [];

    /// <summary>General per-type switches.</summary>
    public ObservableCollection<SuggestionFilterToggle> TypeToggles { get; } = [];

    /// <summary>
    /// Per-type switches for <see cref="SelectedInstrument"/>. Deselecting keeps the last instrument's switches so the
    /// closing accordion fades them out rather than an empty panel (load-transition R10, web <c>CollapseOnExit</c>
    /// <c>lastChildrenRef</c>); <see cref="Begin"/> and a newly selected instrument rebuild them.
    /// </summary>
    public ObservableCollection<SuggestionFilterToggle> InstrumentTypeToggles { get; } = [];

    /// <summary>Settings-visible charts offered by the Instrument Selector (refreshed by <see cref="Begin"/>).</summary>
    public IReadOnlyList<Instrument> Instruments => instruments;

    /// <summary>Whether any instrument is visible in Settings.</summary>
    public bool HasInstruments => instruments.Count > 0;

    /// <summary>Whether the staged value differs from the applied filter (false again once a live change applies).</summary>
    public bool CanApply => !Draft.Equals(owner.Filter);

    /// <summary>Whether switches apply immediately (set once <see cref="Begin"/> finishes loading).</summary>
    public bool IsLive { get; private set; }

    /// <summary>Starts editing from the applied filter (flyout opening).</summary>
    public void Begin()
    {
        IsLive = false;
        instruments = owner.VisibleInstruments;
        OnPropertyChanged(nameof(Instruments));
        OnPropertyChanged(nameof(HasInstruments));
        Draft = owner.Filter;
        InstrumentToggles.Clear();
        foreach (var instrument in instruments)
            InstrumentToggles.Add(new SuggestionFilterToggle(instrument.Label(), "", instrument.IconFile(),
                $"fst.suggestions.filter.instrument.{instrument.ServiceId()}", Draft.IsInstrumentEnabled(instrument),
                on => Draft = Draft.WithInstrument(instrument, on)));
        TypeToggles.Clear();
        foreach (var type in SuggestionCategoryTypeInfo.All)
            TypeToggles.Add(new SuggestionFilterToggle(type.Label(), type.FilterDescription(), "",
                $"fst.suggestions.filter.type.{type.Key()}", Draft.IsGlobalEnabled(type),
                on => Draft = Draft.WithGlobalType(type, on, instruments)));
        SelectedInstrument = null;
        RebuildInstrumentTypes();
        IsLive = true;
    }

    /// <summary>Restores every switch to its default (applied at once while live).</summary>
    [RelayCommand(CanExecute = nameof(CanReset))]
    private void Reset() => Draft = SuggestionFilterSettings.Default;

    private bool CanReset() => Draft.IsActiveFor(owner.VisibleInstruments);

    partial void OnDraftChanged(SuggestionFilterSettings value)
    {
        for (var i = 0; i < InstrumentToggles.Count && i < instruments.Count; i++) InstrumentToggles[i].Sync(value.IsInstrumentEnabled(instruments[i]));
        for (var i = 0; i < TypeToggles.Count; i++) TypeToggles[i].Sync(value.IsGlobalEnabled(SuggestionCategoryTypeInfo.All[i]));
        if (detailInstrument is { } instrument)
            for (var i = 0; i < InstrumentTypeToggles.Count; i++)
                InstrumentTypeToggles[i].Sync(value.IsTypeEnabled(SuggestionCategoryTypeInfo.All[i], instrument));
        if (IsLive && CanApply) owner.ApplyFilter(value);
    }

    partial void OnSelectedInstrumentChanged(Instrument? value)
    {
        if (value is not null) RebuildInstrumentTypes();
    }

    /// <summary>Rebuilds the per-type switches for the selected instrument (none while nothing is selected).</summary>
    private void RebuildInstrumentTypes()
    {
        InstrumentTypeToggles.Clear();
        detailInstrument = SelectedInstrument is { } selected && instruments.Contains(selected) ? selected : null;
        if (detailInstrument is not { } instrument) return;
        foreach (var type in SuggestionCategoryTypeInfo.All)
            InstrumentTypeToggles.Add(new SuggestionFilterToggle(type.Label(), type.FilterDescription(), "",
                $"fst.suggestions.filter.type.{instrument.ServiceId()}.{type.Key()}", Draft.IsTypeEnabled(type, instrument),
                on => Draft = Draft.WithInstrumentType(type, instrument, on, instruments)));
    }
}
#endregion
