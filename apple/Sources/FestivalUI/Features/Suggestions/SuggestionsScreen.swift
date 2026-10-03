import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - SuggestionsScreen

/// `/suggestions` — score-driven song suggestions for the selected player, ported from the
/// web `SuggestionsPage` (solo mode only; band suggestions are out of scope for this wave).
///
/// One glass card per generated category (`SuggestionCategoryCardView`), loaded a page at a
/// time as the player scrolls near the bottom (web "virtualized incremental loads"), with a
/// toolbar filter sheet for instrument/category toggles.
struct SuggestionsScreen: View {
    let session: FestivalSession
    /// Settings-visible charts, supplied by `FestivalRootView` (mirrors every other
    /// `tabStack` root) instead of re-reading the `fst.settings.show*` keys independently.
    let visibleInstruments: Set<Instrument>
    @State private var viewModel: SuggestionsViewModel
    @State private var filterPresented = false
    /// `batchGeneration` whose stagger has finished: its rows no longer fade, so a row
    /// rebuilt after scrolling away and back appears without a fade (issue #30).
    @State private var settledBatchGeneration: Int?
    /// Revisions already handled by the tasks below; a reappearance re-fires
    /// `.task(id:)` even when the id value is unchanged (the same `NavigationStack`
    /// root quirk Leaderboards hit, Lane W1), and `session.selectionRevision`'s task
    /// calls the destructive `viewModel.invalidate()` — without this guard, popping
    /// back from a suggestion's Song Detail wiped the already-loaded list back to a
    /// loading spinner.
    @State private var handledSelectionRevision: Int?
    @State private var handledPublicationRevision: Int?
    @Environment(\.openProfile) private var openProfile
    @Environment(\.deviceLayout) private var layout
    @AppStorage(SuggestionFilterSettings.storageKey) private var filterData = Data()

    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).
    ///   - visibleInstruments: Settings-visible charts (`FestivalRootView.visibleInstruments`).
    init(session: FestivalSession, visibleInstruments: Set<Instrument>) {
        self.session = session
        self.visibleInstruments = visibleInstruments
        _viewModel = State(initialValue: SuggestionsViewModel(filter: .defaults()))
    }

    /// `visibleInstruments` in source (`Instrument.allCases`) order for the filter sheet's
    /// row list and its default instrument-picker selection.
    private var orderedVisibleInstruments: [Instrument] {
        Instrument.allCases.filter(visibleInstruments.contains)
    }

    private var visibleCategories: [SuggestionCategory] {
        viewModel.visibleCategories(appVisibleInstruments: visibleInstruments)
    }

    var body: some View {
        Group {
            if session.selectedPlayer == nil {
                noProfile
            } else if session.playerLoadState == .syncing {
                syncing
            } else if case let .failed(issue) = session.playerLoadState {
                ServiceStatusView(issue, title: "Could Not Load Player") {
                    Task { await session.refreshSelectedPlayer() }
                }
            } else {
                // iPhone Duo inner display, portrait: suggestions on top, the ones in
                // today's Item Shop below (`SuggestionsDualSource.swift`).
                DualSourceLayout {
                    // A player change fades the old suggestions out, shows the spinner and
                    // fades the new ones in (web `usePageTransition` keyed on the
                    // account, issue #71). Filter changes and new pages do not reload.
                    FestivalReloadGate(
                        key: session.selectedPlayer?.accountId, isLoading: isFirstPageLoading,
                        spinnerLabel: "Loading Suggestions", spinnerIdentifier: "fst.suggestions.loading"
                    ) {
                        content
                    }
                } secondary: {
                    SuggestionsCarouselPane(session: session, source: .itemShop, seeAll: .shop)
                }
            }
        }
        .navigationTitle("Suggestions")
        .festivalBackground(.carousel, session: session)
        .toolbar {
            if session.selectedPlayer != nil, session.playerLoadState == .available {
                // Tab root: page actions precede the bell + avatar, which stay rightmost.
                ToolbarItem(placement: .festivalPageAction) {
                    Button {
                        filterPresented = true
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .tint(viewModel.filter.isActive() ? BrandTokens.gold : BrandTokens.textPrimary)
                    .accessibilityIdentifier("fst.suggestions.filter-button")
                }
            }
            FestivalRootTrailingItems(session: session)
        }
        .festivalProvidesRootTrailingItems()
        .sheet(isPresented: $filterPresented) {
            SuggestionsFilterSheet(
                applied: viewModel.filter, visibleInstruments: orderedVisibleInstruments
            ) { updated in
                viewModel.filter = updated
                if let data = try? updated.encoded() { filterData = data }
            }
        }
        .task { viewModel.filter = SuggestionFilterSettings.decodeSaved(filterData) }
        .task(id: session.selectionRevision) {
            guard handledSelectionRevision != session.selectionRevision else { return }
            handledSelectionRevision = session.selectionRevision
            guard session.selectedPlayer != nil else { return }
            viewModel.invalidate()
            await viewModel.ensureLoaded(session: session)
        }
        .task(id: session.publicationRevision) {
            guard handledPublicationRevision != session.publicationRevision else { return }
            handledPublicationRevision = session.publicationRevision
            await viewModel.ensureLoaded(session: session)
        }
    }

    // MARK: - States

    private var noProfile: some View {
        ContentUnavailableView {
            Label("No Profile Selected", systemImage: "sparkles")
        } description: {
            Text("Select a player to see personalized suggestions.")
        } actions: {
            Button("Choose Profile") { openProfile() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("fst.suggestions.choose-profile")
        }
        .accessibilityIdentifier("fst.suggestions.empty")
    }

    private var syncing: some View {
        ContentUnavailableView {
            Label("Scores Syncing", systemImage: "arrow.triangle.2.circlepath")
        } description: {
            Text("This player's scores are still being published. Check back soon.")
        }
        .accessibilityIdentifier("fst.suggestions.syncing")
    }

    /// Whether the first page is still loading (the gate shows its spinner).
    private var isFirstPageLoading: Bool {
        switch viewModel.loadState {
        case .idle, .loading: viewModel.categories.isEmpty
        case .failed, .loaded: false
        }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            if !viewModel.categories.isEmpty {
                list
            }
        case let .failed(issue):
            ServiceStatusView(issue, title: "Could Not Load Suggestions") {
                Task { await viewModel.ensureLoaded(session: session) }
            }
        case .loaded:
            if visibleCategories.isEmpty {
                emptyState
            } else {
                list
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Suggestions", systemImage: "sparkles")
        } description: {
            Text(
                viewModel.filter.isActive()
                    ? "No suggestions match your filters."
                    : "Play some songs to get personalized suggestions."
            )
        }
        .accessibilityIdentifier("fst.suggestions.no-results")
    }

    private var list: some View {
        let categories = visibleCategories
        // Only the newest generated page fades in, staggered in its own order; earlier
        // pages and rows rebuilt by scrolling appear without a fade (issue #30).
        let fadeIndexes = FadeStagger.batchIndexes(
            order: categories.map(\.id), batch: viewModel.latestBatchIds,
            settled: settledBatchGeneration == viewModel.batchGeneration
        )
        return ScrollView {
            Group {
                if SuggestionsLayout.usesGrid(layout) {
                    // `/duo` G1 (operator, 2026-10-02): two card columns at regular width
                    // (Duo inner display, iPad) instead of one stretched column (Apple's
                    // Duo design talk: "Don't ship a stretched iPhone app"), even count.
                    LazyVGrid(columns: SuggestionsLayout.gridColumns, alignment: .leading, spacing: 20) {
                        cards(categories, fadeIndexes: fadeIndexes, horizontalPadding: 0)
                    }
                    .padding(.horizontal, 16)
                    footer
                } else {
                    LazyVStack(spacing: 20) {
                        cards(categories, fadeIndexes: fadeIndexes, horizontalPadding: 16)
                        footer
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .scrollContentBackground(.hidden)
        .task(id: viewModel.batchGeneration) {
            let generation = viewModel.batchGeneration
            await FadeStagger.settle(afterRevealing: viewModel.latestBatchIds.count) {
                settledBatchGeneration = generation
            }
        }
        .festivalRefreshable { viewModel.startNewMix(); await viewModel.ensureLoaded(session: session) }
        .accessibilityIdentifier("fst.suggestions.list")
    }

    /// The category cards, in order, each loading the next page as it appears.
    ///
    /// - Parameters:
    ///   - categories: Categories to show.
    ///   - fadeIndexes: Staggered fade order of the newest batch.
    ///   - horizontalPadding: Per-card side padding (the grid pads once outside).
    /// - Returns: One card per category.
    private func cards(
        _ categories: [SuggestionCategory], fadeIndexes: [SuggestionCategory.ID: Int], horizontalPadding: CGFloat
    ) -> some View {
        ForEach(categories) { category in
            SuggestionCategoryCardView(
                category: category, session: session,
                currentSeason: viewModel.currentSeason, visibleInstruments: visibleInstruments
            )
                .padding(.horizontal, horizontalPadding)
                // Web `getCardDelay`: the first screenful staggers 125 ms apart.
                .festivalFadeIn(isLoaded: true, index: fadeIndexes[category.id] ?? -1)
                .onAppear { maybeLoadMore(after: category) }
        }
    }

    @ViewBuilder private var footer: some View {
        if viewModel.hasMore {
            // Keep a fixed-height slot while more pages exist so the spinner appearing at
            // the end never changes content height (that read as a bounce at the bottom).
            FestivalLoadingView(accessibilityLabel: "Loading more suggestions")
                .opacity(viewModel.isLoadingMore ? 1 : 0)
                .accessibilityHidden(!viewModel.isLoadingMore)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        } else {
            VStack(spacing: 12) {
                Text("You've seen every current suggestion.")
                    .font(.subheadline)
                    .foregroundStyle(FestivalText.primary)
                Button("Start New Mix") { viewModel.startNewMix() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("fst.suggestions.start-new-mix")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }

    /// Trigger the next page once the player scrolls near the last loaded category.
    ///
    /// - Parameter category: The category that just appeared on screen.
    private func maybeLoadMore(after category: SuggestionCategory) {
        guard category.id == visibleCategories.suffix(3).first?.id else { return }
        Task { await viewModel.loadMore() }
    }
}

// MARK: - Layout

/// How Suggestions lays out its category cards (`/duo` G1, operator 2026-10-02).
enum SuggestionsLayout {
    /// Two flexible card columns, top-aligned.
    static let gridColumns = [
        GridItem(.flexible(), spacing: 20, alignment: .top),
        GridItem(.flexible(), spacing: 20, alignment: .top),
    ]

    /// Whether the cards form the two-column grid.
    ///
    /// - Parameter layout: Current `\.deviceLayout`.
    /// - Returns: True at regular width (iPhone Duo inner display, a wide iPad column),
    ///   false on iPhone and the folded Duo (one column).
    static func usesGrid(_ layout: DeviceLayout) -> Bool {
        layout.widthClass == .regular
    }
}
