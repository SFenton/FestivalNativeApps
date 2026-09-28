using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Settings
/// <summary>Settings page: profile, instrument visibility (last chart stays on) and additive accessibility overrides.</summary>
public sealed partial class SettingsViewModel : ObservableObject
{
    private readonly FestivalSession session;

    /// <summary>Creates the page model.</summary>
    /// <param name="session">Shared session.</param>
    public SettingsViewModel(FestivalSession session)
    {
        this.session = session;
        Instruments = InstrumentInfo.All.Select(i => new InstrumentToggle(this, i)).ToList();
        session.PropertyChanged += OnSessionChanged;
    }

    /// <summary>One toggle per chart in service order.</summary>
    public IReadOnlyList<InstrumentToggle> Instruments { get; }

    /// <summary>Selected player name, or a prompt.</summary>
    public string ProfileText => session.SelectedPlayer is { } p ? p.DisplayName : "No player selected";

    /// <summary>Whether a player is selected.</summary>
    public bool HasPlayer => session.HasPlayer;

    /// <summary>Service origin shown under About.</summary>
    public string ServiceOrigin => session.Api.BaseUri.GetLeftPart(UriPartial.Authority);

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

    /// <summary>Deselects the player.</summary>
    [RelayCommand]
    private void DeselectPlayer() => session.DeselectPlayer();

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

    /// <summary>Re-raises derived properties on settings changes.</summary>
    /// <param name="sender">Session.</param>
    /// <param name="e">Changed property.</param>
    private void OnSessionChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(FestivalSession.Settings)) return;
        foreach (var toggle in Instruments) toggle.Refresh();
        OnPropertyChanged(nameof(ProfileText));
        OnPropertyChanged(nameof(HasPlayer));
        OnPropertyChanged(nameof(ReduceMotion));
        OnPropertyChanged(nameof(DisableAnimatedArtwork));
        OnPropertyChanged(nameof(SaveData));
    }
}

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
#endregion
