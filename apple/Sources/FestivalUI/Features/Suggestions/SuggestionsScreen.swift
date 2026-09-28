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
    @Environment(\.openProfile) private var openProfile
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
            } else if case let .failed(message) = session.playerLoadState {
                ServiceUnavailableView(
                    title: "Could Not Load Player", message: message,
                    retry: { Task { await session.refreshSelectedPlayer() } }
                )
            } else {
                content
            }
        }
        .navigationTitle("Suggestions")
        .festivalBackground(.carousel, session: session)
        .toolbar {
            if session.selectedPlayer != nil, session.playerLoadState == .available {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        filterPresented = true
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .tint(viewModel.filter.isActive() ? BrandTokens.gold : BrandTokens.textPrimary)
                    .accessibilityIdentifier("fst.suggestions.filter-button")
                }
            }
        }
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
            guard session.selectedPlayer != nil else { return }
            viewModel.invalidate()
            await viewModel.ensureLoaded(session: session)
        }
        .task(id: session.publicationRevision) {
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

    @ViewBuilder private var content: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            if viewModel.categories.isEmpty {
                ProgressView("Loading Suggestions\u{2026}")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("fst.suggestions.loading")
            } else {
                list
            }
        case let .failed(message):
            ServiceUnavailableView(
                title: "Could Not Load Suggestions", message: message,
                retry: { Task { await viewModel.ensureLoaded(session: session) } }
            )
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
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(visibleCategories) { category in
                    SuggestionCategoryCardView(category: category, session: session)
                        .padding(.horizontal, 16)
                        .onAppear { maybeLoadMore(after: category) }
                }
                footer
            }
            .padding(.vertical, 16)
        }
        .scrollContentBackground(.hidden)
        .refreshable { viewModel.startNewMix(); await viewModel.ensureLoaded(session: session) }
        .accessibilityIdentifier("fst.suggestions.list")
    }

    @ViewBuilder private var footer: some View {
        if viewModel.isLoadingMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        } else if !viewModel.hasMore {
            VStack(spacing: 12) {
                Text("You've seen every current suggestion.")
                    .font(.subheadline)
                    .foregroundStyle(BrandTokens.textSecondary)
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
