import SwiftUI
import FestivalCore
import FestivalDesign

/// A persistent user preference, forced to list in compact layouts.
enum ShopViewMode: String, CaseIterable, Identifiable {
    case grid
    case list

    var id: String { rawValue }

    /// Name the active native Shop layout.
    ///
    /// - Returns: Grid or List.
    var label: String { rawValue.capitalized }
}

/// A Shop page can still show official offers when the Songs catalog fails.
private struct ShopSnapshot {
    let payload: ShopPayload
    let songsById: [String: Song]
    let songDetailsError: String?
}

/// Native, keyless Shop page inside Songs navigation, not a fourth compact tab.
struct ShopScreen: View {
    let session: FestivalSession
    let isVisible: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("fst.shop.viewMode") private var preferredMode = ShopViewMode.grid
    @AppStorage("fst.settings.hideShop") private var hideShop = false
    @AppStorage("fst.settings.disableShopHighlighting") private var disableHighlights = false
    @State private var state = LoadState.loading
    @State private var retryRevision = 0

    private enum LoadState {
        case loading
        case loaded(ShopSnapshot)
        case failed(String)
    }

    private struct RequestKey: Equatable {
        let publicationRevision: Int
        let visible: Bool
        let retryRevision: Int
    }

    private var requestKey: RequestKey {
        RequestKey(
            publicationRevision: session.publicationRevision,
            visible: isVisible, retryRevision: retryRevision
        )
    }

    private var viewMode: ShopViewMode {
        sizeClass == .compact || dynamicTypeSize.isAccessibilitySize
            ? .list : preferredMode
    }

    private var offerActionsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView("Loading Item Shop")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ServiceUnavailableView(title: "Item Shop unavailable", message: message) {
                    retryRevision += 1
                }
            case let .loaded(snapshot):
                shopContent(snapshot)
            }
        }
        .background(ArtworkBackground(
            mode: .carousel, session: session, visible: isVisible
        ))
        .navigationTitle("Item Shop")
        .toolbar {
            if sizeClass != .compact && !dynamicTypeSize.isAccessibilitySize {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        preferredMode = viewMode == .grid ? .list : .grid
                    } label: {
                        Label(
                            viewMode == .grid ? "List View" : "Grid View",
                            systemImage: viewMode == .grid ? "list.bullet" : "square.grid.2x2"
                        )
                    }
                    .accessibilityIdentifier("fst.shop.view-toggle")
                }
            }
        }
        .task(id: requestKey) {
            guard isVisible else { return }
            await load()
        }
    }

    /// Load shop first, then disclose a separately failed detail-catalog read.
    private func load() async {
        let requested = requestKey
        state = .loading
        do {
            let feed = try await session.shop()
            try Task.checkCancellation()
            if feed.sortedSongs.isEmpty {
                guard requested == requestKey else { return }
                state = .loaded(ShopSnapshot(
                    payload: feed, songsById: [:], songDetailsError: nil
                ))
                return
            }
            var songsById: [String: Song] = [:]
            var detailsError: String?
            do {
                let catalog = try await session.catalog()
                try Task.checkCancellation()
                songsById = Dictionary(
                    catalog.catalog.songs.map { ($0.songId, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                detailsError = error.localizedDescription
            }
            guard !Task.isCancelled, requested == requestKey else { return }
            state = .loaded(ShopSnapshot(
                payload: feed, songsById: songsById, songDetailsError: detailsError
            ))
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled, requested == requestKey else { return }
            state = .failed(error.localizedDescription)
        }
    }

    /// Preserve an explicit empty/error/provenance state in either adaptive layout.
    ///
    /// - Parameter snapshot: Public shop feed with optional valid catalog links.
    /// - Returns: Readable list, adaptive grid or genuine empty message.
    @ViewBuilder
    private func shopContent(_ snapshot: ShopSnapshot) -> some View {
        if snapshot.payload.sortedSongs.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "bag")
                    .font(.largeTitle)
                    .accessibilityHidden(true)
                Text("No songs in the Item Shop")
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Check back later - the shop updates regularly.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(BrandTokens.textPrimary)
            .padding(24)
            .background(
                BrandTokens.cardBackground,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("fst.shop.empty")
        } else if viewMode == .list {
            List {
                shopDisclosures(snapshot)
                ForEach(snapshot.payload.sortedSongs) { offer in
                    offerCard(offer, snapshot: snapshot, grid: false)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    shopDisclosures(snapshot)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 210), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(snapshot.payload.sortedSongs) { offer in
                            offerCard(offer, snapshot: snapshot, grid: true)
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    /// Announce true Shop freshness and any separately failed song-detail links.
    ///
    /// - Parameter snapshot: Valid Shop response and optional catalogue failure.
    /// - Returns: Visible warnings without replacing a usable Shop feed.
    @ViewBuilder
    private func shopDisclosures(_ snapshot: ShopSnapshot) -> some View {
        if snapshot.payload.isStale {
            FreshnessDisclosure(
                message: OfflineDisclosure.label(
                    .shop, publicationId: snapshot.payload.publicationId
                ),
                symbol: "wifi.slash"
            )
            .accessibilityIdentifier("fst.shop.offline")
        } else if snapshot.payload.publicationId == nil {
            FreshnessDisclosure(
                message: "Showing live shop without publication verification",
                symbol: "info.circle"
            )
        }
        if let error = snapshot.songDetailsError {
            FreshnessDisclosure(
                message: "Song details unavailable: \(error)",
                symbol: "exclamationmark.triangle"
            )
            .accessibilityIdentifier("fst.shop.song-details-error")
        }
    }

    /// Select a compact row or an artwork-first regular-width card.
    ///
    /// - Parameters:
    ///   - offer: Typed official item shop link and presentation fields.
    ///   - snapshot: Optional catalogue song used only for a valid native detail link.
    ///   - grid: True for a full-width artwork card in regular layouts.
    /// - Returns: Separate official and in-app actions with source badge states.
    @ViewBuilder
    private func offerCard(
        _ offer: ShopSong, snapshot: ShopSnapshot, grid: Bool
    ) -> some View {
        if grid {
            gridOffer(offer, snapshot: snapshot)
        } else {
            listOffer(offer, snapshot: snapshot)
        }
    }

    /// Keep phone rows close to the source's concise artwork/title/action layout.
    ///
    /// - Parameters:
    ///   - offer: Public item with separate official outbound URL.
    ///   - snapshot: Catalogue lookup for safe native Detail navigation.
    /// - Returns: Compact native row with two independent actions.
    private func listOffer(_ offer: ShopSong, snapshot: ShopSnapshot) -> some View {
        offerActionsLayout {
            if let song = snapshot.songsById[offer.songId] {
                NavigationLink(value: SongRoute.detail(song)) {
                    listSummary(offer)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("fst.shop.song.\(offer.songId)")
            } else {
                listSummary(offer)
            }
            Link(destination: offer.shopUrl) {
                Image(systemName: "bag")
                    .font(.title3)
                    .foregroundStyle(BrandTokens.textPrimary)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(BrandTokens.appBackground, in: Capsule())
            }
            .accessibilityLabel("\(offer.title), Open Official Item Shop")
            .accessibilityIdentifier("fst.shop.external.\(offer.songId)")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandTokens.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor(for: offer), lineWidth: 2)
        }
    }

    /// Show artwork and metadata on one line while exposing any shop-state badge.
    ///
    /// - Parameter offer: Item available in the current public Shop feed.
    /// - Returns: Concise source-like row label and original fixture/live art.
    private func listSummary(_ offer: ShopSong) -> some View {
        HStack(spacing: 12) {
            ArtworkTile(raw: offer.albumArt, session: session, size: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(offer.title)
                    .font(.headline)
                    .foregroundStyle(BrandTokens.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(offer.year.map { "\(offer.artist) · \($0)" } ?? offer.artist)
                    .font(.subheadline)
                    .foregroundStyle(BrandTokens.textSecondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            offerBadge(offer, compact: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Let full-bleed artwork and a readable scrim drive the regular-width grid.
    ///
    /// - Parameters:
    ///   - offer: Validated public Shop item.
    ///   - snapshot: Optional current-catalog song for native Detail navigation.
    /// - Returns: One lazy square artwork card with distinct official/Detail actions.
    private func gridOffer(_ offer: ShopSong, snapshot: ShopSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .topTrailing) {
                    Link(destination: offer.shopUrl) {
                        ZStack(alignment: .bottomLeading) {
                            ArtworkTile(
                                raw: offer.albumArt, session: session,
                                size: geometry.size.width
                            )
                            .accessibilityHidden(true)
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.85)],
                                startPoint: .center, endPoint: .bottom
                            )
                            VStack(alignment: .leading, spacing: 4) {
                                Text(offer.title).font(.headline)
                                Text(offer.artist).font(.subheadline)
                            }
                            .foregroundStyle(BrandTokens.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                        }
                        .frame(width: geometry.size.width, height: geometry.size.width)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityLabel(
                        "\(offer.title), \(offer.artist), Open Official Item Shop"
                    )
                    .accessibilityIdentifier("fst.shop.external.\(offer.songId)")
                    offerBadge(offer, compact: false)
                        .padding(8)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            if let song = snapshot.songsById[offer.songId] {
                NavigationLink(value: SongRoute.detail(song)) {
                    Label("View Song Details", systemImage: "music.note")
                }
                .accessibilityIdentifier("fst.shop.song.\(offer.songId)")
            }
        }
        .font(.body)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandTokens.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor(for: offer), lineWidth: 2)
        }
    }

    /// Reflect leaving/new highlights without erasing a hidden preference.
    ///
    /// - Parameter offer: Source-labelled current Shop item.
    /// - Returns: Fluent border color for the effective highlight state.
    private func borderColor(for offer: ShopSong) -> Color {
        switch ShopPresentationPolicy.highlight(
            for: offer, hidden: hideShop, highlightingDisabled: disableHighlights
        ) {
        case .leavingTomorrow: BrandTokens.statusRed
        case .new: BrandTokens.gold
        case nil: BrandTokens.glassBorder
        }
    }

    /// Keep badged meaning in VoiceOver even when compact rows show only an icon.
    ///
    /// - Parameters:
    ///   - offer: Upstream New or Leaving Tomorrow state.
    ///   - compact: Hide text only on narrow rows, preserving spoken labels.
    /// - Returns: Optional visible and accessible Shop badge.
    @ViewBuilder
    private func offerBadge(_ offer: ShopSong, compact: Bool) -> some View {
        if let highlight = ShopPresentationPolicy.highlight(
            for: offer, hidden: hideShop, highlightingDisabled: disableHighlights
        ) {
            let leaving = highlight == .leavingTomorrow
            let title = highlight.label
            HStack(spacing: 4) {
                Image(systemName: leaving ? "clock" : "sparkles")
                if !compact { Text(title) }
            }
            .font(.caption.bold())
            .foregroundStyle(leaving ? BrandTokens.textPrimary : BrandTokens.gold)
            .padding(6)
            .background(
                leaving ? BrandTokens.statusRed : BrandTokens.appBackground,
                in: Capsule()
            )
            .accessibilityLabel(title)
            .accessibilityIdentifier(
                leaving
                    ? "fst.shop.badge.leaving.\(offer.songId)"
                    : "fst.shop.badge.new.\(offer.songId)"
            )
        }
    }
}
