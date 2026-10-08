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
    /// Publication observed with the catalogue bytes (nil when it did not load).
    var catalogueObservation: Int? = nil
}

/// Native, keyless Shop page inside Songs navigation, not a fourth compact tab.
struct ShopScreen: View {
    let session: FestivalSession
    let isVisible: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.deviceLayout) private var layout
    /// Set where page tools sit in the iPhone tab-bar accessory (issue #92).
    @Environment(\.pageToolsRegistry) private var pageTools
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.playerStatNavigator) private var navigator
    @AppStorage("fst.shop.viewMode") private var preferredMode = ShopViewMode.grid
    @AppStorage(ShopOfferFilter.storageKey) private var savedFilter = ""
    /// Older "show only" switches (issue #19), read only to migrate into ``savedFilter``.
    @AppStorage(ShopOfferFilter.legacyNewKey) private var legacyFilterNew = false
    @AppStorage(ShopOfferFilter.legacyAvailableKey) private var legacyFilterAvailable = false
    @AppStorage(ShopOfferFilter.legacyLeavingTomorrowKey)
    private var legacyFilterLeavingTomorrow = false
    @State private var filterPresented = false
    /// The saved Item Shop sort (issue #379), apart from the Songs sort.
    @AppStorage(ShopSortChoice.modeKey) private var sortMode = SongSortMode.title
    @AppStorage(ShopSortChoice.ascendingKey) private var sortAscending = true
    @State private var sortPresented = false
    @AppStorage("fst.settings.hideShop") private var hideShop = false
    @AppStorage("fst.settings.disableShopHighlighting") private var disableHighlights = false
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false
    @Environment(\.colorSchemeContrast) private var systemContrast
    @State private var state = LoadState.loading
    @State private var retryRevision = 0
    @State private var loadedKey: RequestKey?
    /// First staggered reveal finished; recycled rows then appear without fading.
    @State private var staggerSettled = false
    /// Artwork grid width (Mac ↑/↓ step one grid row).
    @State private var gridWidth: CGFloat = 0

    private enum LoadState {
        case loading
        case loaded(ShopSnapshot)
        case failed(ServiceIssue)

        /// Whether the shop is still loading (drives ``FestivalReloadGate``).
        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
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

    /// The saved New / Available / Leaving Tomorrow filter (issues #19, #376).
    private var appliedFilter: ShopOfferFilter {
        ShopOfferFilter.decodeSaved(
            savedFilter, legacyNew: legacyFilterNew, legacyAvailable: legacyFilterAvailable,
            legacyLeavingTomorrow: legacyFilterLeavingTomorrow
        )
    }

    /// The saved sort, normalized to the Item Shop's modes.
    private var appliedSort: ShopSortChoice {
        ShopSortChoice(mode: sortMode, ascending: sortAscending)
    }

    /// Filter, then sort, a loaded Shop's offers (pattern `catalogue-sort` R2, R7).
    ///
    /// - Parameter snapshot: The loaded Shop and its catalogue.
    /// - Returns: The offers every layout renders, and whether Duration paused.
    private func displayedOffers(_ snapshot: ShopSnapshot) -> ShopOfferSort.Result {
        ShopOfferSort.sorted(
            appliedFilter.filtered(snapshot.payload.sortedSongs), by: appliedSort,
            durations: ShopOfferSort.durations(
                catalogue: snapshot.songDetailsError == nil ? snapshot.songsById : nil,
                catalogueObservation: snapshot.catalogueObservation,
                shopObservation: snapshot.payload.observedPublicationId,
                currentObservation: session.publicationId
            )
        )
    }

    /// Whether the saved sort is paused for the loaded Shop (drives the Sort button).
    private var sortPaused: Bool {
        guard case let .loaded(snapshot) = state else { return false }
        return displayedOffers(snapshot).paused
    }

    /// Save a filter from the sheet or a Reset action and retire the migrated older switches.
    ///
    /// - Parameter filter: The filter to apply.
    private func applyFilter(_ filter: ShopOfferFilter) {
        savedFilter = filter.encoded()
        legacyFilterNew = false
        legacyFilterAvailable = false
        legacyFilterLeavingTomorrow = false
    }

    private var offerActionsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    var body: some View {
        // A List ↔ Grid switch, a retry or a new publication fades the shop out, shows
        // the spinner and fades the new layout in (web `useViewTransition`, issue #71).
        FestivalReloadGate(key: viewMode, isLoading: state.isLoading, spinnerLabel: "Loading Item Shop") {
            switch state {
            case .loading:
                EmptyView()
            case let .failed(issue):
                ServiceStatusView(issue, title: "Item Shop unavailable") {
                    retryRevision += 1
                }
            case let .loaded(snapshot):
                shopContent(snapshot)
                    // The settle timer starts at the gate's reveal, not at the load.
                    .task {
                        await FadeStagger.settle(
                            afterRevealing: appliedFilter.filtered(snapshot.payload.sortedSongs).count
                        ) {
                            staggerSettled = true
                        }
                    }
            }
        }
        // A new load or a List ↔ Grid switch re-runs the staggered reveal for the new
        // layout (web `toggleView`: `setStaggerGen`, batch 6.10).
        .onChange(of: StaggerKey(load: loadedKey, mode: viewMode)) { _, _ in
            staggerSettled = false
        }
        .detailFadeTestSafe()
        .festivalBackground(.carousel, session: session, visible: isVisible)
        .festivalNavigationTitle("Item Shop")
        .toolbar {
            if pageTools == nil {
                ToolbarItem(placement: .festivalPageAction) { sortButton }
                ToolbarItem(placement: .festivalPageAction) { filterButton }
                if showsViewToggle {
                    ToolbarItem(placement: .festivalPageAction) { viewToggle }
                }
            }
        }
        // iPhone tab-bar accessory (issue #92): Sort and Filter like Songs (issue #379),
        // then List/Grid where offered.
        .festivalPageTool(
            token: [appliedSort.accessibilityValue(paused: sortPaused), String(appliedSort.isDefault)],
            order: PageToolOrder.primary
        ) {
            sortButton
        }
        .festivalPageTool(
            token: [Self.filterAccessibilityValue(appliedFilter), String(appliedFilter.isActive)],
            order: PageToolOrder.secondary
        ) {
            filterButton
        }
        .festivalPageTool(
            token: viewMode == .grid, order: PageToolOrder.tertiary, isEnabled: showsViewToggle
        ) {
            viewToggle
        }
        #if os(iOS)
        // iPhone and iPad: the Songs Sort sheet; the Mac shows it as a popover from the
        // Sort button (``catalogueSortPopover``), like Songs.
        .sheet(isPresented: $sortPresented) { sortSheet }
        #endif
        .sheet(isPresented: $filterPresented) {
            ShopFilterSheet(applied: appliedFilter, onApply: applyFilter)
                .macSheetFrame(width: 420, height: 360)
        }
        // HIG Toolbars › macOS: "Every toolbar item must also be a menu-bar command"
        // (also the iPadOS menu bar).
        .macPageCommands(MacPageCommands(
            sort: { sortPresented = true }, filter: { filterPresented = true }
        ))
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
            // Duration needs the catalogue, so its first screen is primed in title order.
            let firstOffers = ShopOfferSort.sorted(
                appliedFilter.filtered(feed.sortedSongs), by: appliedSort, durations: nil
            ).offers
            let primePaths = viewMode == .list ? ShopArtworkPrimePolicy.paths(for: firstOffers) : []
            async let primed: Void = primeArtwork(primePaths)
            var songsById: [String: Song] = [:]
            var detailsError: String?
            var catalogueObservation: Int?
            do {
                let catalog = try await session.catalog()
                try Task.checkCancellation()
                catalogueObservation = catalog.observedPublicationId
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
                payload: feed, songsById: songsById, songDetailsError: detailsError,
                catalogueObservation: catalogueObservation
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
    /// - Returns: Readable list, adaptive grid, genuine empty message, or the no-match
    ///   empty state when the Shop filter hides every offer.
    @ViewBuilder
    private func shopContent(_ snapshot: ShopSnapshot) -> some View {
        let offers = displayedOffers(snapshot).offers
        if snapshot.payload.sortedSongs.isEmpty {
            FestivalEmptyState(
                ShopEmptyCopy.emptyTitle, systemImage: "bag",
                subtitle: ShopEmptyCopy.emptySubtitle,
                accessibilityIdentifier: "fst.shop.empty"
            )
        } else if offers.isEmpty {
            filteredEmpty(snapshot)
        } else if viewMode == .list {
            // A plain ScrollView, not a List: each row holds two sibling actions (Detail
            // and the official bag), and a List would add its own disclosure chevron
            // before the bag instead of after it.
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        topAnchor
                        LazyVStack(alignment: .leading, spacing: 6) {
                            shopDisclosures(snapshot)
                            ForEach(Array(offers.enumerated()), id: \.element.id) { index, offer in
                                offerCard(offer, snapshot: snapshot, grid: false)
                                    .detailStaggeredFadeIn(index: index, settled: staggerSettled)
                                    .macKeyboardRow(offer.id)
                            }
                        }
                        .macKeyboardRows(Self.keyRows(offers, catalogue: snapshot.songsById, grid: false))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .festivalFadeInScope()
                    }
                }
                .onChange(of: appliedSort) { _, _ in scrollToTop(proxy) }
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        topAnchor
                        VStack(alignment: .leading, spacing: 12) {
                            shopDisclosures(snapshot)
                            HingeGrid(
                                columns: gridColumns, spacing: ShopGridPolicy.spacing,
                                perSide: .fit(minimum: ShopGridPolicy.minimumFoldCardWidth)
                            ) {
                                ForEach(Array(offers.enumerated()), id: \.element.id) { index, offer in
                                    offerCard(offer, snapshot: snapshot, grid: true)
                                        .detailStaggeredFadeIn(index: index, settled: staggerSettled)
                                        .macKeyboardRow(offer.id, ring: true)
                                }
                            }
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
                            .macKeyboardRows(
                                columns: ShopGridPolicy.columnCount(width: gridWidth, layout: layout),
                                Self.keyRows(offers, catalogue: snapshot.songsById, grid: true)
                            )
                        }
                        .padding(16)
                        .festivalFadeInScope()
                    }
                }
                .onChange(of: appliedSort) { _, _ in scrollToTop(proxy) }
            }
        }
    }

    /// Zero-height scroll target above the Shop's first row.
    private var topAnchor: some View {
        Color.clear.frame(height: 0).id(Self.topAnchorID).accessibilityHidden(true)
    }

    private static let topAnchorID = "fst.shop.top"

    /// A changed sort starts at the top of the new order (pattern `catalogue-sort` R6),
    /// instantly, like Songs: an animated scroll back would build every row it passes.
    ///
    /// - Parameter proxy: The Shop list's or grid's scroll proxy.
    private func scrollToTop(_ proxy: ScrollViewProxy) {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { proxy.scrollTo(Self.topAnchorID, anchor: .top) }
    }

    /// The grid's columns: an even count on the iPhone Duo inner display
    /// (``ShopGridPolicy``), otherwise adaptive 210 pt cards.
    private var gridColumns: [GridItem] {
        if let count = ShopGridPolicy.evenColumnCount(width: gridWidth, layout: layout) {
            return Array(repeating: GridItem(.flexible(), spacing: ShopGridPolicy.spacing), count: count)
        }
        return [GridItem(.adaptive(minimum: ShopGridPolicy.minimumCardWidth), spacing: ShopGridPolicy.spacing)]
    }

    /// Mac arrow-key rows: Return does what a click does, so a list row opens Song
    /// Detail (or the official Item Shop without a catalogue song) and a grid card opens
    /// the official Item Shop.
    ///
    /// - Parameters:
    ///   - offers: Offers in display order.
    ///   - catalogue: Current catalogue songs by ID.
    ///   - grid: Whether the artwork grid is showing.
    /// - Returns: One row per offer.
    static func keyRows(_ offers: [ShopSong], catalogue: [String: Song], grid: Bool) -> [MacKeyRow] {
        offers.map { offer in
            if !grid, let song = catalogue[offer.songId] {
                return MacKeyRow(id: offer.id, action: .route(.songDetail(song)))
            }
            return MacKeyRow(id: offer.id, action: .url(offer.shopUrl))
        }
    }

    // MARK: - Sort

    /// The Songs Sort sheet with the Item Shop's modes (issue #379, `catalogue-sort` R1).
    private var sortSheet: some View {
        SongsSortSheet(
            mode: appliedSort.mode, ascending: appliedSort.ascending,
            modes: ShopSortChoice.modes, identifier: "fst.shop.sort"
        ) { mode, ascending in
            sortMode = mode
            sortAscending = ascending
        }
    }

    /// The toolbar Sort button: Songs' icon and label, gold while the sort isn't Title
    /// ascending, announcing the applied sort (`catalogue-sort` R4).
    private var sortButton: some View {
        Button {
            sortPresented = true
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .catalogueSortPopover(isPresented: $sortPresented) { sortSheet }
        .accessibilityLabel("Sort Item Shop")
        #if os(macOS)
        .help("Sort Item Shop")
        #endif
        .accessibilityValue(appliedSort.accessibilityValue(paused: sortPaused))
        .accessibilityIdentifier("fst.shop.sort")
        .tint(appliedSort.isDefault ? BrandTokens.accentBlue : BrandTokens.gold)
    }

    // MARK: - Filter

    /// The toolbar Filter button: Songs' icon, gold while a filter is on.
    /// The List/Grid switch is offered only where both layouts fit (not compact width or
    /// accessibility text sizes).
    private var showsViewToggle: Bool {
        sizeClass != .compact && !dynamicTypeSize.isAccessibilitySize
    }

    /// Switches between the List and Grid layouts.
    private var viewToggle: some View {
        Button {
            staggerSettled = false
            preferredMode = viewMode == .grid ? .list : .grid
        } label: {
            Label(
                viewMode == .grid ? "List View" : "Grid View",
                systemImage: viewMode == .grid ? "list.bullet" : "square.grid.2x2"
            )
        }
        .accessibilityIdentifier("fst.shop.view-toggle")
    }

    private var filterButton: some View {
        Button {
            filterPresented = true
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease")
        }
        .accessibilityLabel("Filter Item Shop")
        #if os(macOS)
        .help("Filter Item Shop")
        #endif
        .accessibilityValue(Self.filterAccessibilityValue(appliedFilter))
        .accessibilityIdentifier("fst.shop.filter")
        .tint(appliedFilter.isActive ? BrandTokens.gold : BrandTokens.accentBlue)
    }

    /// Why a saved Duration sort shows title order (`catalogue-sort` R7).
    static let sortPausedMessage = "Duration sort paused until song lengths for this "
        + "Item Shop load. Showing title order; your preference is saved."

    /// What the Filter button announces after its label.
    ///
    /// - Parameter filter: The applied Shop filter.
    /// - Returns: "No filters", or "Hiding" and the switched-off groups in display order.
    static func filterAccessibilityValue(_ filter: ShopOfferFilter) -> String {
        filter.isActive
            ? "Hiding " + filter.hidden.map(\.label).joined(separator: ", ")
            : "No filters"
    }

    /// A loaded Shop whose offers the filter hides: the shared centred empty state
    /// (empty-error-states R2, issue #377), distinct from a genuinely empty Shop. No
    /// card and no Reset: the Filter button stays in the page tools.
    ///
    /// - Parameter snapshot: The loaded Shop, for its disclosures.
    /// - Returns: Any disclosures, then the empty state centred in the rest of the page.
    private func filteredEmpty(_ snapshot: ShopSnapshot) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) { shopDisclosures(snapshot) }
                .padding(.horizontal, 16)
            FestivalEmptyState(
                ShopEmptyCopy.filteredTitle, systemImage: "line.3.horizontal.decrease",
                subtitle: ShopEmptyCopy.filteredSubtitle,
                accessibilityIdentifier: "fst.shop.filter-empty"
            )
        }
    }

    /// Announce true Shop freshness and any separately failed song-detail links.
    ///
    /// - Parameter snapshot: Valid Shop response and optional catalogue failure.
    /// - Returns: Visible warnings without replacing a usable Shop feed.
    @ViewBuilder
    private func shopDisclosures(_ snapshot: ShopSnapshot) -> some View {
        if displayedOffers(snapshot).paused {
            // Like Songs' paused sorts (`fst.songs.sort-paused`): visible, choice kept.
            FreshnessDisclosure(message: Self.sortPausedMessage, symbol: "arrow.up.arrow.down")
                .accessibilityIdentifier("fst.shop.sort-paused")
        }
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

    /// The shared Songs ``SongRowView`` (surface, art, marquee title/artist line and
    /// Item Shop pulse border), decorated for the Shop: New / Leaving Tomorrow badge,
    /// then the official bag and the Detail chevron (web `ShopPage` list renders the
    /// Songs `SongRow`; PWA gap #17 order).
    ///
    /// The Detail link spans the whole row; the bag is a sibling `Link` drawn over
    /// the slot the row reserves for it, so the two actions never nest. At
    /// accessibility sizes the bag becomes a labelled action below the row.
    ///
    /// - Parameters:
    ///   - offer: Public item with separate official outbound URL.
    ///   - snapshot: Catalogue lookup for safe native Detail navigation.
    /// - Returns: Shared Song row with two independent actions.
    private func listOffer(_ offer: ShopSong, snapshot: ShopSnapshot) -> some View {
        let large = dynamicTypeSize.isAccessibilitySize
        let row = ShopRowPolicy.row(
            for: offer, catalogue: snapshot.songsById,
            hidden: hideShop, highlightingDisabled: disableHighlights,
            reservesBag: !large
        )
        let summary = SongRowView(
            song: row.song, instrument: nil, session: session,
            highContrast: moreContrast || systemContrast == .increased,
            shopOffer: row.decoration
        )
        return VStack(alignment: .leading, spacing: 4) {
            if let detail = row.detailSong {
                // One combined button element (like the Songs `songLink`), so the
                // marquee lines are read and audited as the row, not as clipped text.
                NavigationLink(value: AppRoute.songDetail(detail)) {
                    summary.contentShape(Rectangle())
                }
                .festivalRowButtonStyle()
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("fst.shop.song.\(offer.songId)")
            } else {
                summary
            }
            if large {
                Link(destination: offer.shopUrl) {
                    Label("Open Official Item Shop", systemImage: "bag")
                        .font(.body)
                        .foregroundStyle(FestivalText.primary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 12)
                        .background(
                            BrandTokens.cardBackground,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                }
                .accessibilityLabel("\(offer.title), Open Official Item Shop")
                .accessibilityIdentifier("fst.shop.external.\(offer.songId)")
            }
        }
        .overlay(alignment: .trailing) {
            if !large {
                bagLink(offer)
                    .padding(
                        .trailing,
                        ShopRowMetrics.bagTrailingInset(navigable: row.detailSong != nil)
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    offerBadge(offer).padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(borderColor(for: offer), lineWidth: 2)
                }
            }
            .festivalRowButtonStyle()
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

    /// The grid card's labelled New / Leaving Tomorrow pill (list rows use the shared
    /// Song row's badge).
    ///
    /// - Parameter offer: Upstream New or Leaving Tomorrow state.
    /// - Returns: Optional visible and accessible Shop badge.
    @ViewBuilder
    private func offerBadge(_ offer: ShopSong) -> some View {
        if let highlight = ShopPresentationPolicy.highlight(
            for: offer, hidden: hideShop, highlightingDisabled: disableHighlights
        ) {
            let leaving = highlight == .leavingTomorrow
            let title = highlight.label
            HStack(spacing: 4) {
                Image(systemName: leaving ? "clock" : "sparkles")
                Text(title)
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

/// Fixed geometry shared by the Song row's Item Shop decoration and the Shop's
/// overlaid bag link.
enum ShopRowMetrics {
    /// Album art edge in points: the shared Song row's art (the PWA's rows use ~44pt).
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
    /// Trailing inset inside the row card (the Song row's horizontal padding).
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

// MARK: - Grid columns

/// Column count for the Item Shop grid.
///
/// `/duo` S1 (operator, 2026-10-02): on the iPhone Duo inner display the grid uses an
/// even column count, so a book-pose fold falls between columns instead of across a
/// card (HIG Designing for iPhone Duo: "Prefer … even grid column counts"; Apple's
/// Duo layout talk: use even columns even when flat). About 835 pt in landscape gives
/// 4 columns of ~200 pt; ~637 pt in portrait gives 2. Every other window keeps the
/// adaptive 210 pt grid.
enum ShopGridPolicy {
    /// Narrowest card in the adaptive grid.
    static let minimumCardWidth: CGFloat = 210
    /// Narrowest card when the inner display rounds to an even count.
    static let minimumEvenCardWidth: CGFloat = 190
    /// Narrowest card on each side of a book-pose fold (``HingeGrid``): the trailing
    /// side, narrowed by the vertical bar, keeps two cards (pattern `hinge-columns`).
    static let minimumFoldCardWidth: CGFloat = 160
    /// Spacing between cards and rows.
    static let spacing: CGFloat = 12

    /// The even column count on the iPhone Duo inner display.
    ///
    /// - Parameters:
    ///   - width: The grid's measured width (0 before the first layout pass).
    ///   - layout: Current `\.deviceLayout`.
    /// - Returns: 2, 4, … on the Duo inner display (flat or partially folded), or nil
    ///   for the adaptive grid (other windows, unmeasured, or room for one column only).
    static func evenColumnCount(width: CGFloat, layout: DeviceLayout) -> Int? {
        guard layout.pose == .unfolded || layout.pose == .partiallyFolded, width > 0 else { return nil }
        let fit = MacKeyboardPolicy.adaptiveColumns(width: width, minimum: minimumEvenCardWidth, spacing: spacing)
        guard fit >= 2 else { return nil }
        return fit - fit % 2
    }

    /// The number of columns the grid draws (for arrow-key navigation too).
    ///
    /// - Parameters:
    ///   - width: The grid's measured width.
    ///   - layout: Current `\.deviceLayout`.
    /// - Returns: The even count on the Duo inner display, else the adaptive count.
    static func columnCount(width: CGFloat, layout: DeviceLayout) -> Int {
        evenColumnCount(width: width, layout: layout)
            ?? MacKeyboardPolicy.adaptiveColumns(width: width, minimum: minimumCardWidth, spacing: spacing)
    }
}

// MARK: - Empty copy

/// Item Shop empty-state copy (issue #377).
///
/// The genuine empty Shop is the web `ShopPage` `EmptyState` (`shop.empty` /
/// `shop.emptyHint`). The web Shop has no filters, so the filtered state follows the web's
/// filtered-empty copy instead, scoped to the Item Shop and worded like Android's
/// filtered Shop state (empty-error-states R8).
enum ShopEmptyCopy {
    /// Web `shop.empty`.
    static let emptyTitle = "No songs in the Item Shop"
    /// Web `shop.emptyHint`.
    static let emptySubtitle = "Check back later \u{2014} the shop updates regularly."
    /// Web `songs.noResults` scoped to the Item Shop, without a sentence period as a title.
    static let filteredTitle = "No Item Shop songs match your filters"
    /// Web filtered-empty next step.
    static let filteredSubtitle = "Try changing your filters to see more songs."
}
