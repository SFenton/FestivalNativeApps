using System.Globalization;
using Festival.App.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Navigation;

namespace Festival.App.Pages;

#region Suggestions page
/// <summary>
/// Suggestions: a virtualized list of generated category cards with incremental loading and a staged
/// instrument/type filter flyout. The page (and its mix) is cached for the section's lifetime.
/// </summary>
public sealed partial class SuggestionsPage : Page
{
    /// <summary>Creates the page.</summary>
    public SuggestionsPage()
    {
        ViewModel = new SuggestionsViewModel(App.Session, new JsonFileSuggestionFilterStore(JsonFileSuggestionFilterStore.DefaultPath), DebugSeed());
        ScreenReader.Attach(this, [ViewModel], () => ViewModel.ShowLoading,
            () => ViewModel.ShowList ? "Suggestions loaded" : ViewModel.ShowEmpty ? ViewModel.EmptyMessage : null, "Loading suggestions");
        InitializeComponent();
        ViewModel.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(SuggestionsViewModel.IsFilterActive)) UpdateFilterTint();
            if (e.PropertyName == nameof(SuggestionsViewModel.VisibleInstruments)) SyncInstrumentPicker();
            if (e.PropertyName == nameof(SuggestionsViewModel.Phase) && ViewModel.ShowList) PerfLog.Mark("suggestions-rendered");
        };
        Loaded += (_, _) => UpdateFilterTint();
    }

    /// <summary>Page model.</summary>
    public SuggestionsViewModel ViewModel { get; }

    /// <inheritdoc />
    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        await ViewModel.AppearCommand.ExecuteAsync(null);
    }

    /// <summary>Fixed mix seed for deterministic Debug/automation screenshots (<c>FST_DEBUG_SUGGESTIONS_SEED</c>).</summary>
    /// <returns>Seed source, or <see langword="null"/> for a random seed per mix.</returns>
    private static Func<uint>? DebugSeed()
    {
        if (uint.TryParse(App.LaunchEnvironment("FST_DEBUG_SUGGESTIONS_SEED"), NumberStyles.None, CultureInfo.InvariantCulture, out var seed))
            return () => seed;
        return null;
    }

    #region List
    /// <summary>Loads the next batch when the third-from-last card is realized.</summary>
    /// <param name="sender">List.</param>
    /// <param name="args">Container info.</param>
    private void OnCardContainerChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        if (args.InRecycleQueue || !ViewModel.ShouldLoadMore(args.ItemIndex)) return;
        // Defer: the collection must not change during this layout pass.
        DispatcherQueue.TryEnqueue(() => ViewModel.LoadMoreCommand.Execute(null));
    }
    #endregion

    #region Filter
    /// <summary>Starts a draft from the applied filter.</summary>
    /// <param name="sender">Flyout.</param>
    /// <param name="e">Unused.</param>
    private void OnFilterOpening(object sender, object e)
    {
        ViewModel.FilterDraft.Begin();
        SyncInstrumentPicker();
    }

    /// <summary>Shows the draft's Settings-visible charts and selection in the Instrument Selector.</summary>
    private void SyncInstrumentPicker()
    {
        InstrumentPicker.Instruments = ViewModel.FilterDraft.Instruments.ToList();
        InstrumentPicker.Selected = ViewModel.FilterDraft.SelectedInstrument;
    }

    /// <summary>Instrument Selector pick: shows that chart's per-type switches (none when cleared).</summary>
    /// <param name="sender">Selector.</param>
    /// <param name="instrument">New selection.</param>
    private void OnFilterInstrumentChanged(object? sender, Instrument? instrument) => ViewModel.FilterDraft.SelectedInstrument = instrument;

    /// <summary>Clears the filter from the empty state.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnResetFilters(object sender, RoutedEventArgs e) => ViewModel.ApplyFilter(SuggestionFilterSettings.Default);

    /// <summary>Tints the filter button gold while a filter is applied (like Songs).</summary>
    private void UpdateFilterTint()
    {
        FilterButton.ClearValue(ForegroundProperty);
        if (ViewModel.IsFilterActive) FilterButton.Foreground = (Brush)Application.Current.Resources["FSTEmphasisBrush"];
    }
    #endregion
}
#endregion
