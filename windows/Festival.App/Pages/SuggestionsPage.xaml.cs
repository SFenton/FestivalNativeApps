using System.Globalization;
using Festival.App.Controls;
using Festival.App.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Navigation;
using Windows.System;
using Windows.UI.ViewManagement;

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
        ViewModel = new SuggestionsViewModel(App.Session, new JsonFileSuggestionFilterStore(JsonFileSuggestionFilterStore.DefaultPath), DebugSeed(), DebugLimit());
        ScreenReader.Attach(this, [ViewModel], () => ViewModel.ShowLoading,
            () => ViewModel.ShowList ? "Suggestions loaded" : ViewModel.ShowEmpty ? ViewModel.EmptyMessage : null, "Loading suggestions");
        InitializeComponent();
        ViewModel.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(SuggestionsViewModel.IsFilterActive)) UpdateFilterTint();
            if (e.PropertyName == nameof(SuggestionsViewModel.VisibleInstruments)) SyncInstrumentPicker();
            if (e.PropertyName == nameof(SuggestionsViewModel.Phase) && ViewModel.ShowList) PerfLog.Mark("suggestions-rendered");
        };
        // Each newly generated batch fades from its first whole line; cards already shown never fade again.
        ViewModel.CardsAdded += (_, start) => FadeIn.Restagger(CardList, ViewModel.FirstWholeLineFrom(start));
        Loaded += (_, _) =>
        {
            UpdateFilterTint();
            OnDemandSplitHost.TextScaleChanged += OnTextScaleChanged;
            UpdateColumns();
        };
        Unloaded += (_, _) => OnDemandSplitHost.TextScaleChanged -= OnTextScaleChanged;
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

    /// <summary>Lower category cap so UI Automation can reach the end-of-mix footer (<c>FST_DEBUG_SUGGESTIONS_LIMIT</c>).</summary>
    /// <returns>Cap, or <see langword="null"/> for the web's 1,000.</returns>
    private static int? DebugLimit() =>
        int.TryParse(App.LaunchEnvironment("FST_DEBUG_SUGGESTIONS_LIMIT"), NumberStyles.None, CultureInfo.InvariantCulture, out var limit) ? limit : null;

    #region List
    /// <summary>Loads the next batch when the line holding the third-from-last card is realized.</summary>
    /// <param name="sender">List.</param>
    /// <param name="args">Container info.</param>
    private void OnCardContainerChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        if (args.InRecycleQueue || !ViewModel.ShouldLoadMoreLine(args.ItemIndex)) return;
        // Defer: the collection must not change during this layout pass.
        DispatcherQueue.TryEnqueue(() => ViewModel.LoadMoreCommand.Execute(null));
    }

    /// <summary>
    /// Arrow keys from a row move to the geometrically nearest row, also across cards (the ListView's own item
    /// navigation would land on a card's first row): Up/Down within a column, Left/Right to the paired card beside it in
    /// two columns (pattern wide-columns; one column has nothing beside a row, so Left/Right stay unhandled).
    /// </summary>
    /// <param name="sender">List.</param>
    /// <param name="e">Key.</param>
    private void OnCardListPreviewKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.OriginalSource is not SuggestionSongRow) return;
        FocusNavigationDirection? direction = e.Key switch
        {
            VirtualKey.Up => FocusNavigationDirection.Up,
            VirtualKey.Down => FocusNavigationDirection.Down,
            VirtualKey.Left when ViewModel.Columns > 1 => FocusNavigationDirection.Left,
            VirtualKey.Right when ViewModel.Columns > 1 => FocusNavigationDirection.Right,
            _ => null,
        };
        if (direction is { } move)
            e.Handled = FocusManager.TryMoveFocus(move, new FindNextElementOptions { SearchRoot = CardList });
    }

    /// <summary>Gap between paired cards: the 16 epx between lines.</summary>
    private const double CardGutter = 16;

    /// <summary>Re-decides the columns when the list's width changes (window resize).</summary>
    /// <param name="sender">List.</param>
    /// <param name="e">Size change.</param>
    private void OnCardListSizeChanged(object sender, SizeChangedEventArgs e) => UpdateColumns();

    /// <summary>Re-decides the columns when the Windows text size changes, on the UI thread.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="args">Unused.</param>
    private void OnTextScaleChanged(UISettings sender, object args) => DispatcherQueue.TryEnqueue(UpdateColumns);

    /// <summary>
    /// Pattern wide-columns (#653): two row-major columns of cards in a wide window at standard text sizes, else one.
    /// A change re-chunks the same cards (nothing reloads or fades again) and keeps the first visible card in view.
    /// </summary>
    private void UpdateColumns()
    {
        if (CardList.ActualWidth <= 0) return;
        var width = CardList.ActualWidth - CardList.Padding.Left - CardList.Padding.Right;
        var columns = WideColumnsHost.Count(CardList, width, CardGutter);
        if (columns == ViewModel.Columns) return;
        var first = CardList.ItemsPanelRoot is ItemsStackPanel panel ? panel.FirstVisibleIndex : -1;
        var card = first >= 0 && first < ViewModel.Lines.Count ? ViewModel.Lines[first].StartIndex : -1;
        if (!ViewModel.SetColumns(columns) || card <= 0) return;
        CardList.ScrollIntoView(ViewModel.Lines[ViewModel.LineOf(card)], ScrollIntoViewAlignment.Leading);
    }
    #endregion

    #region Filter
    /// <summary>Starts a draft from the applied filter and fits the flyout to the window.</summary>
    /// <param name="sender">Flyout.</param>
    /// <param name="e">Unused.</param>
    private void OnFilterOpening(object sender, object e)
    {
        ViewModel.FilterDraft.Begin();
        // Fit the window like the Songs and Item Shop filters: the pinned Reset footer must stay on screen below the button
        // at every size and text scale (compact 500 × 800 at 225% text pushed it off the window; issue #513).
        if (XamlRoot is { } root)
        {
            var below = root.Size.Height - FilterButton.TransformToVisual(null).TransformPoint(new(0, FilterButton.ActualHeight)).Y;
            FilterForm.MaxHeight = Math.Clamp(below - 24, 240, 640);
            FilterForm.Width = Math.Clamp(root.Size.Width - 32, 280, 400);
        }
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

    /// <summary>Tints the filter button gold while a filter is applied (like Songs).</summary>
    private void UpdateFilterTint()
    {
        FilterButton.ClearValue(ForegroundProperty);
        if (ViewModel.IsFilterActive) FilterButton.Foreground = (Brush)Application.Current.Resources["FSTEmphasisBrush"];
    }
    #endregion
}
#endregion
