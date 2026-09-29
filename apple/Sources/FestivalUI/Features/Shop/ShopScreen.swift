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
    @Environment(\.playerStatNavigator) private var navigator
    @AppStorage("fst.shop.viewMode") private var preferredMode = ShopViewMode.grid
    @AppStorage("fst.settings.hideShop") private var hideShop = false
    @AppStorage("fst.settings.disableShopHighlighting") private var disableHighlights = false
    @State private var state = LoadState.loading
    @State private var retryRevision = 0
    @State private var loadedKey: RequestKey?
    /// First staggered reveal finished; recycled rows then appear without fading.
    @State private var staggerSettled = false

    private enum LoadState {
        case loading
        case loaded(ShopSnapshot)
        case failed(ServiceIssue)
    }

    /// Identity of one staggered reveal: a load, or a layout switch.
    private struct StaggerKey: Equatable {
        let load: RequestKey?
        let mode: ShopViewMode
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
                FestivalLoadingView(accessibilityLabel: "Loading Item Shop")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(issue):
                ServiceStatusView(issue, title: "Item Shop unavailable") {
                    retryRevision += 1
                }
            case let .loaded(snapshot):
                shopContent(snapshot)
                    // New identity per layout: the switch fades the old layout out and
                    // the new one's rows stagger in, instead of reusing faded-in rows.
                    .id(viewMode)
                    .transition(.opacity)
            }
        }
        // A new load or a List ↔ Grid switch re-runs the staggered reveal for the new
        // layout (web `toggleView`: `setStaggerGen`, batch 6.10).
        .task(id: StaggerKey(load: loadedKey, mode: viewMode)) {
            guard case let .loaded(snapshot) = state else { return }
            staggerSettled = false
            await FadeStagger.settle(afterRevealing: snapshot.payload.sortedSongs.count) {
                staggerSettled = true
            }
        }
        .detailFadeTestSafe()
        .festivalBackground(.carousel, session: session, visible: isVisible)
        .navigationTitle("Item Shop")
        .toolbar {
            if sizeClass != .compact && !dynamicTypeSize.isAccessibilitySize {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            staggerSettled = false
                            preferredMode = viewMode == .grid ? .list : .grid
                        }
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
            // Returning from Song Detail re-runs `.task`; keep the loaded list instead
            // of flashing the spinner and re-priming art (jitter on Back).
            if case .loaded = state, loadedKey == requestKey { return }
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
                loadedKey = requested
                return
            }
            // Warm the first screen's covers while the catalogue loads, so rows
            // reveal with art (bounded; slow covers keep their own placeholder).
            let primePaths = viewMode == .list
                ? ShopArtworkPrimePolicy.paths(for: feed.sortedSongs) : []
            async let primed: Void = primeArtwork(primePaths)
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
            await primed
            guard !Task.isCancelled, requested == requestKey else { return }
            state = .loaded(ShopSnapshot(
                payload: feed, songsById: songsById, songDetailsError: detailsError
            ))
            loadedKey = requested
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled, requested == requestKey else { return }
            state = .failed(ServiceIssue(error))
        }
    }

    /// Decode up to one screen of row covers into the shared bounded thumbnail cache.
    ///
    /// Uses the same `maxPixels` as the row's ``ArtworkTile`` so the rows hit the
    /// in-memory cache; returns after ``ShopArtworkPrimePolicy/timeout`` at most.
    ///
    /// - Parameter paths: Artwork paths from ``ShopArtworkPrimePolicy/paths(for:limit:)``.
    private func primeArtwork(_ paths: [String]) async {
        guard !paths.isEmpty else { return }
        let session = session
        let maxPixels = Int(ShopRowMetrics.art * 3)
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await withTaskGroup(of: Void.self) { downloads in
                    for raw in paths {
                        downloads.addTask {
                            _ = try? await session.preparedArtwork(
                                raw: raw, maxPixels: maxPixels
                            )
                        }
                    }
                    await downloads.waitForAll()
                }
            }
            group.addTask {
                try? await Task.sleep(for: ShopArtworkPrimePolicy.timeout)
            }
            await group.next()
            group.cancelAll()
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
            .foregroundStyle(FestivalText.primary)
            .padding(24)
            .background(
                BrandTokens.cardBackground,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("fst.shop.empty")
        } else if viewMode == .list {
            // A plain ScrollView, not a List: each row holds two sibling actions (Detail
            // and the official bag), and a List would add its own disclosure chevron
            // before the bag instead of after it.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    shopDisclosures(snapshot)
                    ForEach(Array(snapshot.payload.sortedSongs.enumerated()), id: \.element.id) { index, offer in
                        offerCard(offer, snapshot: snapshot, grid: false)
                            .detailStaggeredFadeIn(index: index, settled: staggerSettled)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    shopDisclosures(snapshot)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 210), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(Array(snapshot.payload.sortedSongs.enumerated()), id: \.element.id) { index, offer in
                            offerCard(offer, snapshot: snapshot, grid: true)
                                .detailStaggeredFadeIn(index: index, settled: staggerSettled)
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
        if snapshot.payload.publicationId == nil {
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

    /// Compact two-line phone row matching the installed PWA: art, title, artist ·
    /// year, then the official bag and the Detail chevron (gap #17).
    ///
    /// The Detail link spans the whole row; the bag is a sibling `Link` drawn over
    /// the slot the row reserves for it, so the two actions never nest. At
    /// accessibility sizes the bag becomes a labelled action below the row.
    ///
    /// - Parameters:
    ///   - offer: Public item with separate official outbound URL.
    ///   - snapshot: Catalogue lookup for safe native Detail navigation.
    /// - Returns: Compact native row with two independent actions.
    private func listOffer(_ offer: ShopSong, snapshot: ShopSnapshot) -> some View {
        let song = snapshot.songsById[offer.songId]
        let large = dynamicTypeSize.isAccessibilitySize
        return VStack(alignment: .leading, spacing: 4) {
            if let song {
                NavigationLink(value: AppRoute.songDetail(song)) {
                    listSummary(offer, navigable: true, reservesBag: !large)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("fst.shop.song.\(offer.songId)")
            } else {
                listSummary(offer, navigable: false, reservesBag: !large)
            }
            if large {
                Link(destination: offer.shopUrl) {
                    Label("Open Official Item Shop", systemImage: "bag")
                        .font(.body)
                        .foregroundStyle(FestivalText.primary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 12)
                }
                .accessibilityLabel("\(offer.title), Open Official Item Shop")
                .accessibilityIdentifier("fst.shop.external.\(offer.songId)")
            }
        }
        .overlay(alignment: .trailing) {
            if !large {
                bagLink(offer)
                    .padding(.trailing, ShopRowMetrics.bagTrailingInset(navigable: song != nil))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandTokens.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor(for: offer), lineWidth: 2)
        }
    }

    /// The official Item Shop action as a plain bag glyph with a 44pt target.
    ///
    /// - Parameter offer: Validated public offer whose official URL opens externally.
    /// - Returns: Accessible outbound link.
    private func bagLink(_ offer: ShopSong) -> some View {
        Link(destination: offer.shopUrl) {
            Image(systemName: "bag")
                .font(.body)
                .foregroundStyle(FestivalText.primary)
                .frame(width: ShopRowMetrics.bagSlot, height: ShopRowMetrics.bagSlot)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("\(offer.title), Open Official Item Shop")
        .accessibilityIdentifier("fst.shop.external.\(offer.songId)")
    }

    /// Art, two single-line texts, badge, bag slot and chevron.
    ///
    /// - Parameters:
    ///   - offer: Item available in the current public Shop feed.
    ///   - navigable: Whether a catalogue match makes this row open Song Detail.
    ///   - reservesBag: Leave room for the overlaid bag link (compact text sizes).
    /// - Returns: Concise source-like row label and original fixture/live art.
    private func listSummary(
        _ offer: ShopSong, navigable: Bool, reservesBag: Bool
    ) -> some View {
        let large = dynamicTypeSize.isAccessibilitySize
        return HStack(spacing: ShopRowMetrics.spacing) {
            ArtworkTile(raw: offer.albumArt, session: session, size: ShopRowMetrics.art)
                .accessibilityHidden(true)
                .padding(.trailing, 4)
            VStack(alignment: .leading, spacing: 2) {
                // One line each when they fit; long names wrap rather than
                // truncate (truncation fails the accessibility audit's clipping check).
                Text(offer.title)
                    .font(.headline)
                    .foregroundStyle(FestivalText.primary)
                    .minimumScaleFactor(large ? 1 : 0.9)
                    .fixedSize(horizontal: false, vertical: true)
                Text(offer.year.map { "\(offer.artist) · \($0)" } ?? offer.artist)
                    .font(.subheadline)
                    .foregroundStyle(FestivalText.primary)
                    .minimumScaleFactor(large ? 1 : 0.9)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            offerBadge(offer, compact: true)
            if reservesBag {
                Color.clear
                    .frame(width: ShopRowMetrics.bagReserve, height: ShopRowMetrics.bagSlot)
                    .accessibilityHidden(true)
            }
            if navigable {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(FestivalText.deemphasized)
                    .frame(width: ShopRowMetrics.chevronWidth)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, ShopRowMetrics.rowInset)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The web `ShopCard`: a square of full-bleed art with a bottom scrim holding the
    /// title and artist, the Leaving Tomorrow pill top-right and the highlight border;
    /// the whole card opens the official Item Shop (batch 6.9). Song Detail stays
    /// reachable from the card's context menu and VoiceOver actions.
    ///
    /// - Parameters:
    ///   - offer: Validated public Shop item.
    ///   - snapshot: Optional current-catalog song for native Detail navigation.
    /// - Returns: One square artwork card.
    private func gridOffer(_ offer: ShopSong, snapshot: ShopSnapshot) -> some View {
        let song = snapshot.songsById[offer.songId]
        return GeometryReader { geometry in
            Link(destination: offer.shopUrl) {
                ZStack(alignment: .bottomLeading) {
                    ArtworkTile(raw: offer.albumArt, session: session, size: geometry.size.width)
                        .accessibilityHidden(true)
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.85)],
                        startPoint: .center, endPoint: .bottom
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(offer.title).font(.headline).lineLimit(1)
                        Text(offer.artist).font(.subheadline).lineLimit(1)
                    }
                    .foregroundStyle(FestivalText.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
                .frame(width: geometry.size.width, height: geometry.size.width)
                .overlay(alignment: .topTrailing) {
                    offerBadge(offer, compact: false).padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(borderColor(for: offer), lineWidth: 2)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(offer.title), \(offer.artist), Open Official Item Shop")
            .accessibilityIdentifier("fst.shop.external.\(offer.songId)")
            .contextMenu {
                // A NavigationLink inside a context menu does not push; the root's
                // push action (installed for stat tiles) pushes on this tab.
                if let song, let navigator {
                    Button {
                        navigator.push(.songDetail(song))
                    } label: {
                        Label("View Song Details", systemImage: "music.note")
                    }
                }
                Link(destination: offer.shopUrl) {
                    Label("Open Official Item Shop", systemImage: "bag")
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
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
            .foregroundStyle(leaving ? FestivalText.primary : BrandTokens.gold)
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

// MARK: - Row metrics and first-screen artwork

/// Fixed geometry shared by the compact row and its overlaid bag link.
enum ShopRowMetrics {
    /// Album art edge in points (the PWA's list rows use ~44pt art).
    static let art: CGFloat = 44
    /// Minimum hit target of the official bag action.
    static let bagSlot: CGFloat = 44
    /// Width the row label reserves for the bag; the 44pt target overhangs it
    /// into the spacing on both sides, leaving more room for the text.
    static let bagReserve: CGFloat = 32
    /// Width reserved for the Detail chevron.
    static let chevronWidth: CGFloat = 12
    /// Horizontal spacing between row elements.
    static let spacing: CGFloat = 8
    /// Trailing inset inside the row card.
    static let rowInset: CGFloat = 12

    /// Trailing padding that centres the 44pt bag target on its reserved slot.
    ///
    /// - Parameter navigable: Whether a chevron follows the bag.
    /// - Returns: Distance from the row's trailing edge to the bag target.
    static func bagTrailingInset(navigable: Bool) -> CGFloat {
        let slotEnd = rowInset + (navigable ? chevronWidth + spacing : 0)
        return slotEnd - (bagSlot - bagReserve) / 2
    }
}

/// Which Shop covers to decode before the first reveal, so the first screen of
/// rows paints with art instead of spinners (gap #17).
enum ShopArtworkPrimePolicy {
    /// Rows that fit on one phone screen, plus one partially visible.
    static let count = 12
    /// Never hold the reveal longer than this for slow art.
    static let timeout: Duration = .milliseconds(900)

    /// First-screen artwork paths, in display order, without blanks or repeats.
    ///
    /// - Parameters:
    ///   - offers: Offers in the order the list renders them.
    ///   - limit: Maximum number of covers to warm.
    /// - Returns: Up to `limit` distinct non-empty `albumArt` paths.
    static func paths(for offers: [ShopSong], limit: Int = count) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for offer in offers where result.count < limit {
            guard let raw = offer.albumArt, !raw.isEmpty, seen.insert(raw).inserted else {
                continue
            }
            result.append(raw)
        }
        return result
    }
}
