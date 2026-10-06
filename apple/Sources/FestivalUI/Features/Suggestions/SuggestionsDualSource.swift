import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Suggestions carousel region

/// Suggestions as an endless, swipeable carousel for a dual-source bottom region on
/// the iPhone Duo inner display in portrait (`.agents/design/apple/duo.md`,
/// "Dual-source half-fold layouts").
///
/// Uses the same `SuggestionGenerator` pipeline as the Suggestions page (one card per
/// generated category, `SuggestionCategoryCardView`), the player's saved Suggestions
/// filter, and loads the next page as the player swipes near the end.
///
/// - ``Source/all``: every catalogue song (under Songs).
/// - ``Source/itemShop``: only songs in the current Item Shop (under Item Shop and
///   Suggestions). The Shop feed and the catalogue must come from the same observed
///   publication, or the region pauses (Shop invariant, `AGENTS.md`); the generator's
///   candidate set is filtered client-side, with no service change.
struct SuggestionsCarouselPane: View {
    /// Which songs the generator may suggest.
    enum Source: Sendable, Equatable {
        /// The whole catalogue.
        case all
        /// Songs in the current Item Shop.
        case itemShop
    }

    let session: FestivalSession
    let source: Source
    /// Route for the header's "View All", if any.
    var seeAll: AppRoute?

    @State private var viewModel = SuggestionsViewModel(filter: .defaults())
    @State private var shopGate: ShopGate = .notNeeded
    @State private var handledKey: LoadKey?
    @Environment(\.openProfile) private var openProfile
    @AppStorage(SuggestionFilterSettings.storageKey) private var filterData = Data()
    @AppStorage("fst.settings.hideShop") private var hideShop = false
    private var visible = VisibleInstrumentsReader()

    /// Item Shop candidates for ``Source/itemShop``.
    private enum ShopGate: Equatable {
        case notNeeded
        case loading
        case ready
        case empty
        case failed(ServiceIssue)
    }

    /// Everything that forces a reload.
    private struct LoadKey: Equatable {
        let selection: Int
        let publication: Int
        let retry: Int
    }

    @State private var retryRevision = 0

    /// Create a pane.
    ///
    /// - Parameters:
    ///   - session: Shared app session.
    ///   - source: Whole catalogue or Item Shop songs only.
    ///   - seeAll: Route for the header's "View All" link.
    init(session: FestivalSession, source: Source, seeAll: AppRoute? = nil) {
        self.session = session
        self.source = source
        self.seeAll = seeAll
    }

    private var title: String { source == .itemShop ? "Item Shop Picks" : "Suggestions" }

    private var loadKey: LoadKey {
        LoadKey(selection: session.selectionRevision, publication: session.publicationRevision, retry: retryRevision)
    }

    private var categories: [SuggestionCategory] {
        viewModel.visibleCategories(appVisibleInstruments: Set(visible.instruments))
    }

    var body: some View {
        DualSourcePane(
            title, systemImage: source == .itemShop ? "bag.fill" : "sparkles", seeAll: seeAll,
            identifier: source == .itemShop ? "suggestions.shop" : "suggestions"
        ) {
            content
        }
        .task(id: loadKey) {
            guard handledKey != loadKey else { return }
            handledKey = loadKey
            viewModel.filter = SuggestionFilterSettings.decodeSaved(filterData)
            await load()
        }
    }

    // MARK: States

    @ViewBuilder private var content: some View {
        if session.selectedPlayer == nil {
            DualSourceMessage(
                "No Profile Selected", systemImage: "sparkles",
                message: source == .itemShop
                    ? "Select a player to see which Item Shop songs suit them."
                    : "Select a player to see personalized suggestions here."
            ) {
                Button("Choose Profile") { openProfile() }
                    .festivalProminentButton()
                    .accessibilityIdentifier("fst.dual.suggestions.choose-profile")
            }
        } else if source == .itemShop, hideShop {
            DualSourceMessage(
                "Item Shop Hidden", systemImage: "bag",
                message: "Turn off Hide Item Shop in Settings to see Item Shop picks."
            )
        } else if session.playerLoadState == .syncing {
            DualSourceMessage(
                "Scores Syncing", systemImage: "arrow.triangle.2.circlepath",
                message: "This player's scores are still being published. Check back soon."
            )
        } else if case let .failed(issue) = session.playerLoadState {
            retryable(issue)
        } else if case let .failed(issue) = shopGate {
            retryable(issue)
        } else if shopGate == .empty {
            DualSourceMessage(
                "Item Shop Empty", systemImage: "bag",
                message: "No Festival songs are in the Item Shop right now."
            )
        } else if viewModel.candidatesPaused {
            DualSourceMessage(
                "Picks Paused", systemImage: "pause.circle",
                message: "The Item Shop updated before the song list. Picks resume once Songs update."
            )
        } else {
            switch viewModel.loadState {
            case let .failed(issue):
                retryable(issue)
            case .loaded where categories.isEmpty && !viewModel.hasMore:
                DualSourceMessage(
                    "No Suggestions", systemImage: "sparkles",
                    message: viewModel.filter.isActive()
                        ? "No suggestions match your filters."
                        : "Play some songs to get personalized suggestions."
                )
            case .loaded where !categories.isEmpty:
                carousel
            default:
                FestivalLoadingView(accessibilityLabel: "Loading \(title)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func retryable(_ issue: ServiceIssue) -> some View {
        ServiceStatusInline(issue, scope: "dual.\(source == .itemShop ? "shop-" : "")suggestions") {
            retryRevision += 1
        }
        .padding(.horizontal, 16)
    }

    /// One card per category, then an end card once the mix is exhausted.
    private var carousel: some View {
        HorizontalCarousel(
            title, items: categories.map(Card.category) + (viewModel.hasMore ? [] : [.end]),
            minimumCardWidth: 300, hasMore: viewModel.hasMore,
            onNearEnd: { Task { await viewModel.loadMore() } }
        ) { card in
            switch card {
            case let .category(category):
                SuggestionCategoryCardView(
                    category: category, session: session, currentSeason: viewModel.currentSeason,
                    visibleInstruments: Set(visible.instruments)
                )
            case .end:
                endCard
            }
        }
    }

    /// A carousel card: a category, or the "seen them all" end card.
    private enum Card: Identifiable {
        case category(SuggestionCategory)
        case end
        var id: String {
            switch self {
            case let .category(category): category.id
            case .end: "fst.dual.suggestions.end"
            }
        }
    }

    private var endCard: some View {
        VStack(spacing: 12) {
            Text("You've seen every current suggestion.")
                .font(.subheadline)
                .foregroundStyle(BrandTokens.textSecondary)
                .multilineTextAlignment(.center)
            Button("Start New Mix") {
                viewModel.startNewMix()
                Task { await viewModel.loadMore() }
            }
            .festivalProminentButton()
            .accessibilityIdentifier("fst.dual.suggestions.start-new-mix")
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 160)
        .festivalCard(cornerRadius: 22)
    }

    // MARK: Loading

    /// Resolve Item Shop candidates when needed, then (re)build the generator.
    @MainActor
    private func load() async {
        guard session.selectedPlayer != nil else { return }
        if source == .itemShop {
            guard !hideShop else { return }
            shopGate = .loading
            do {
                let feed = try await session.shop()
                let ids = Set(feed.sortedSongs.map(\.songId))
                guard !ids.isEmpty else {
                    shopGate = .empty
                    return
                }
                viewModel.restrictCandidates(to: ids, publicationId: feed.observedPublicationId)
                shopGate = .ready
            } catch is CancellationError {
                return
            } catch {
                shopGate = .failed(ServiceIssue(error))
                return
            }
        } else {
            viewModel.invalidate()
        }
        await viewModel.ensureLoaded(session: session)
    }
}
