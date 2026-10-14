import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - RivalsScreen

/// `/rivals` — selected player's rivals hub.
///
/// Ports the web's `RivalsPage`/`LeaderboardRivalsTab`: a Song/Leaderboard segmented
/// tab, a "Common Rivals" section (every visible instrument's rivals lists
/// intersected), a cross-instrument "Combo" section when Settings' visible
/// instruments derive one, one section per Settings-visible instrument, and a
/// "View All" push to `AllRivalsScreen`. Quick Links (`fst.quick-links.*`) lists
/// whichever of these sections are currently non-empty; sections register and
/// deregister themselves as their independent loads settle, so the menu rebuilds
/// automatically on tab change with no explicit array to maintain.
struct RivalsScreen: View {
    /// Find Rival's toolbar symbol. The Mac's one unified toolbar also shows the global
    /// Search magnifier, so Find Rival uses a distinct symbol there.
    #if os(macOS)
    static let findRivalSymbol = "person.crop.circle.badge.questionmark"
    #else
    static let findRivalSymbol = "magnifyingglass"
    #endif

    let session: FestivalSession
    /// True where Rivals is a root section (the iPad flyout, the Mac sidebar): its
    /// toolbar then ends with the bell and avatar so the avatar stays rightmost. False
    /// when pushed.
    let showsRootTrailingItems: Bool
    @State private var tab: Tab = .song
    /// The Leaderboard tab's picked metric; read through ``rankBy``.
    @State private var selectedRankBy: RivalRankMetric = .totalscore
    @AppStorage(ExperimentalRanks.storageKey) private var experimentalRanks = ExperimentalRanks.defaultValue
    @State private var quickLinks = QuickLinksController()
    @State private var findRivalPresented = false
    /// Rival shown in the dual-source bottom region (Duo inner display, portrait).
    @State private var dualSelection: AppRoute?
    @Environment(\.openProfile) private var openProfile
    @Environment(\.deviceLayout) private var layout
    /// Set where page tools float above the iPhone tab bar (issues #92, #632).
    @Environment(\.pageToolsRegistry) private var pageTools
    private var visible = VisibleInstrumentsReader()

    enum Tab: String, CaseIterable, Identifiable {
        case song = "Song"
        case leaderboard = "Leaderboard"
        var id: String { rawValue }
    }

    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).
    ///   - showsRootTrailingItems: Pass `true` only from the Rivals tab root.
    ///   - tab: The opening tab (web route state `?tab=leaderboard`).
    ///   - rankBy: The Leaderboard tab's opening metric (web `?rankBy=`); read as Total
    ///     Score while Settings › Experimental Ranks is off (pattern `experimental-ranks`).
    init(
        session: FestivalSession, showsRootTrailingItems: Bool = false,
        tab: Tab = .song, rankBy: RivalRankMetric = .totalscore
    ) {
        self.session = session
        self.showsRootTrailingItems = showsRootTrailingItems
        _tab = State(initialValue: tab)
        _selectedRankBy = State(initialValue: rankBy)
    }

    /// Opens the Find Rival sheet.
    private var findRivalButton: some View {
        Button {
            findRivalPresented = true
        } label: {
            Label("Find Rival", systemImage: Self.findRivalSymbol)
        }
        .help("Find Rival")
        .accessibilityIdentifier("fst.rivals.findRival")
    }

    var body: some View {
        Group {
            if session.selectedPlayer == nil {
                RivalsChooseProfileState { openProfile() }
            } else {
                hub
            }
        }
        .festivalNavigationTitle("Rivals")
        .festivalBackground(.carousel, session: session)
        .toolbar {
            // Pushed from the iPhone drawer: page actions only (the pushed-page avatar
            // comes from `.pageTrailingItems()`). As a tab root (iPad, Duo
            // unfolded) the toolbar ends with `FestivalRootTrailingItems`. Either way
            // Find Rival precedes the avatar (`.agents/controls/app-navigation/ios.md`).
            if pageTools == nil {
                ToolbarItem(placement: .festivalPageAction) {
                    findRivalButton
                }
                // `/duo` R1 (operator, 2026-10-02): the page's own action stays in the
                // iPhone Duo rail and global Search overflows into "…" (HIG Designing for
                // iPhone Duo: "Set visibility priority … to preserve frequent actions").
                .rivalsRailPriority(isVerticalBar: layout.sectionChrome.isVerticalBar)
            }
            QuickLinksToolbarItem(quickLinks)
            if showsRootTrailingItems {
                FestivalRootTrailingItems(session: session)
            }
        }
        .preference(key: FestivalRootTrailingProvidedKey.self, value: showsRootTrailingItems)
        // iPhone floating page tools (issues #92, #632): Find Rival before Quick Links.
        .festivalPageTool(token: "findRival", order: PageToolOrder.primary) {
            findRivalButton
        }
        .macPageCommands(MacPageCommands(findRival: { findRivalPresented = true }))
        .sheet(isPresented: $findRivalPresented) {
            FindRivalSheet(session: session)
                .festivalSheet()
        }
    }

    private var instruments: [Instrument] { visible.instruments }
    private var comboScope: RivalComboScope? { RivalCombo.deriveScope(visible: instruments) }

    @ViewBuilder private var hub: some View {
        // iPhone Duo inner display, portrait: the hub on top, the selected rival's
        // rivalry below; rows select instead of pushing (`RivalsDualSource.swift`).
        DualSourceLayout {
            hubList.dualSourceSelection($dualSelection, section: .rivals)
        } secondary: {
            RivalDualDetailPane(session: session, selection: dualSelection)
        }
        // Every section below loads for `session.selectedPlayer` but keys its
        // `task(id:)` only on instrument/scope; this hub survives a profile switch
        // (tab root, or pushed on a stack the switch does not reset), so key the
        // sections' state by the selected account or they keep the old account's
        // rivals (`.agents/platforms/apple/architecture.md`, "Per-entity screens").
        .id(session.selectedPlayer?.accountId)
    }

    private var hubList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .accessibilityIdentifier("fst.rivals.tab")

                if instruments.isEmpty {
                    FestivalFootnote(
                        "Enable at least one instrument in Settings to see rivals."
                    )
                    .padding(.horizontal, 16)
                } else if tab == .song {
                    if instruments.count >= 2 {
                        RivalCommonSection(session: session, instruments: instruments)
                    }
                    if let comboScope {
                        RivalComboSection(session: session, scope: comboScope)
                    }
                    ForEach(instruments) { instrument in
                        RivalInstrumentSongSection(
                            session: session, instrument: instrument,
                            detailScope: RivalDetailScopes.hubScope(visible: instruments)
                        )
                    }
                } else {
                    rankByPicker
                    ForEach(instruments) { instrument in
                        RivalInstrumentLeaderboardSection(
                            session: session, instrument: instrument, rankBy: rankBy
                        )
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .quickLinks(quickLinks, title: "Quick Links")
    }

    /// The Leaderboard tab's metric in effect: Total Score while Settings ›
    /// Experimental Ranks is off (pattern `experimental-ranks`, web `RivalsPage`).
    private var rankBy: RivalRankMetric {
        selectedRankBy.coerced(experimentalRanks: experimentalRanks)
    }

    /// The Leaderboard tab's Rank By menu; shown only with experimental ranks, as on the
    /// web (only Total Score is offered otherwise).
    @ViewBuilder private var rankByPicker: some View {
        if experimentalRanks {
            rankByMenu
        }
    }

    private var rankByMenu: some View {
        HStack {
            Spacer()
            Menu {
                ForEach(RivalRankMetric.enabled(experimentalRanks: experimentalRanks)) { metric in
                    Button(metric.label) { selectedRankBy = metric }
                }
            } label: {
                // `/duo` R2: stays beside the boards it sorts, with a 44 pt target
                // (HIG Accessibility: 44×44 pt default control size).
                Label(rankBy.label, systemImage: "arrow.up.arrow.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BrandTokens.textPrimary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("fst.rivals.rankBy")
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Common Rivals section

/// Rivals present in every visible instrument's own "shared songs" list, loaded
/// independently of the per-instrument sections (native `RivalCommonRivals.intersect`).
struct RivalCommonSection: View {
    let session: FestivalSession
    let instruments: [Instrument]
    @State private var state: RivalsLoadState<(above: [RivalSummary], below: [RivalSummary])> = .loading
    /// Skips the reload `.task(id:)` starts on every reappearance (#39, #410).
    @State private var gate = ReappearanceLoadGate<RivalsSectionLoadKey<[Instrument]>>()

    private let previewCount = 3

    private var loadKey: RivalsSectionLoadKey<[Instrument]> {
        RivalsSectionLoadKey(instruments, session: session)
    }

    var body: some View {
        content.task(id: loadKey) {
            guard gate.needsLoad(for: loadKey) else { return }
            await load()
        }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            shell { FestivalLoadingView(accessibilityLabel: "Loading").frame(maxWidth: .infinity).padding(.vertical, 12) }
        case let .failed(issue):
            shell { ServiceStatusInline(issue, scope: "rivals.common") { Task { await load() } } }
        case let .loaded(result) where result.above.isEmpty && result.below.isEmpty:
            EmptyView()
        case let .loaded(result):
            shell(viewAll: RivalsViewAllButton(
                route: AppRoute.allRivals(scope: .song(instruments: instruments.map(\.rawValue))),
                identifier: "fst.rivals.common.view-all", card: "Common Rivals"
            )) {
                ForEach(previewRows(result)) { row in
                    ListDetailLink(value: AppRoute.rivalDetail(
                        rivalId: row.rival.accountId, name: row.rival.displayName,
                        scope: .song(instruments: instruments.map(\.rawValue))
                    )) {
                        RivalRowContent(rival: row.rival, direction: row.direction)
                    }
                    .accessibilityIdentifier("fst.rivals.row.\(row.rival.accountId)")
                    .macKeyboardRow("common|\(row.rival.accountId)")
                }
            }
            .macKeyboardRows(order: 0, previewRows(result).map { row in
                MacKeyRow(
                    id: "common|\(row.rival.accountId)",
                    action: .route(.rivalDetail(
                        rivalId: row.rival.accountId, name: row.rival.displayName,
                        scope: .song(instruments: instruments.map(\.rawValue))
                    ))
                )
            })
            .quickLinkSection(id: "common", title: "Common Rivals", symbol: "person.2.fill")
            .festivalFadeIn(isLoaded: true)
        }
    }

    private struct Row: Identifiable {
        let rival: RivalSummary
        let direction: RivalDirection
        var id: String { rival.accountId }
    }

    private func previewRows(_ result: (above: [RivalSummary], below: [RivalSummary])) -> [Row] {
        result.above.prefix(previewCount).map { Row(rival: $0, direction: .above) }
            + result.below.prefix(previewCount).map { Row(rival: $0, direction: .below) }
    }

    /// The section's material card, ending with its optional "View All Rivals" button
    /// inside the card below the rows, like "View Full Leaderboard" (#41, #382).
    ///
    /// - Parameters:
    ///   - viewAll: Button that ends the card once rivals loaded; nil while loading or failed.
    ///   - content: The card's rows.
    /// - Returns: The padded section.
    @ViewBuilder private func shell<Content: View>(
        viewAll: RivalsViewAllButton? = nil, @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FestivalGlassSection("Common Rivals") { content() } action: { viewAll }
        }
        .padding(.horizontal, 16)
    }

    @MainActor
    private func load() async {
        let key = loadKey
        state = .loading
        var lists: [RivalsListResponse] = []
        // Sequential rather than a `TaskGroup`, matching `combinedRivalDetail`: at
        // most a handful of instruments, and this keeps every read on the
        // session's own `@MainActor` isolation.
        //
        // Every read must succeed before intersecting: `try?` here used to
        // swallow a real failure (e.g. a scrape-freeze 503) into an empty
        // `lists` array, so the section silently disappeared (`.loaded` with
        // an empty intersection renders `EmptyView()`) instead of showing its
        // `ServiceStatusInline` error like every sibling section.
        do {
            for instrument in instruments {
                lists.append(try await session.rivalsList(instrument: instrument))
            }
        } catch is CancellationError {
            return
        } catch {
            state = .failed(ServiceIssue(error))
            return
        }
        state = .loaded(RivalCommonRivals.intersect(lists))
        gate.markLoaded(key)
    }
}

// MARK: - Combo section

/// One cross-instrument "combo" (or Pro Drums family) scope, a server-computed
/// distinct rivals list rather than a client-side merge (native `RivalCombo.deriveScope`).
struct RivalComboSection: View {
    let session: FestivalSession
    let scope: RivalComboScope
    @State private var state: RivalsLoadState<RivalsListResponse> = .loading
    /// Skips the reload `.task(id:)` starts on every reappearance (#39, #410).
    @State private var gate = ReappearanceLoadGate<RivalsSectionLoadKey<String>>()

    private let previewCount = 3

    private var loadKey: RivalsSectionLoadKey<String> {
        RivalsSectionLoadKey(scope.token, session: session)
    }

    var body: some View {
        content.task(id: loadKey) {
            guard gate.needsLoad(for: loadKey) else { return }
            await load()
        }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            shell { FestivalLoadingView(accessibilityLabel: "Loading").frame(maxWidth: .infinity).padding(.vertical, 12) }
        case let .failed(issue):
            shell { ServiceStatusInline(issue, scope: "rivals.combo.\(scope.token)") { Task { await load() } } }
        case let .loaded(response) where response.isEmpty:
            EmptyView()
        case let .loaded(response):
            shell(viewAll: RivalsViewAllButton(
                route: AppRoute.allRivals(
                    scope: .combo(token: scope.token, instruments: scope.instruments.map(\.rawValue))
                ),
                identifier: "fst.rivals.combo.view-all", card: "\(scope.label) Rivals"
            )) {
                ForEach(previewRows(response)) { row in
                    ListDetailLink(value: AppRoute.rivalDetail(
                        rivalId: row.rival.accountId, name: row.rival.displayName,
                        scope: .combo(token: scope.token, instruments: scope.instruments.map(\.rawValue))
                    )) {
                        RivalRowContent(rival: row.rival, direction: row.direction)
                    }
                    .accessibilityIdentifier("fst.rivals.row.\(row.rival.accountId)")
                    .macKeyboardRow("combo|\(row.rival.accountId)")
                }
            }
            .macKeyboardRows(order: 1, previewRows(response).map { row in
                MacKeyRow(
                    id: "combo|\(row.rival.accountId)",
                    action: .route(.rivalDetail(
                        rivalId: row.rival.accountId, name: row.rival.displayName,
                        scope: .combo(token: scope.token, instruments: scope.instruments.map(\.rawValue))
                    ))
                )
            })
            .quickLinkSection(id: "combo", title: "\(scope.label) Rivals", symbol: "music.note")
            .festivalFadeIn(isLoaded: true)
        }
    }

    private struct Row: Identifiable {
        let rival: RivalSummary
        let direction: RivalDirection
        var id: String { rival.accountId }
    }

    private func previewRows(_ response: RivalsListResponse) -> [Row] {
        response.above.prefix(previewCount).map { Row(rival: $0, direction: .above) }
            + response.below.prefix(previewCount).map { Row(rival: $0, direction: .below) }
    }

    /// The section's material card, ending with its optional "View All Rivals" button
    /// inside the card below the rows, like "View Full Leaderboard" (#41, #382).
    ///
    /// - Parameters:
    ///   - viewAll: Button that ends the card once rivals loaded; nil while loading or failed.
    ///   - content: The card's rows.
    /// - Returns: The padded section.
    @ViewBuilder private func shell<Content: View>(
        viewAll: RivalsViewAllButton? = nil, @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FestivalGlassSection("\(scope.label) Rivals") { content() } action: { viewAll }
        }
        .padding(.horizontal, 16)
    }

    @MainActor
    private func load() async {
        let key = loadKey
        state = .loading
        do {
            state = .loaded(try await session.rivalsComboList(token: scope.token))
            gate.markLoaded(key)
        } catch is CancellationError {
        } catch {
            state = .failed(ServiceIssue(error))
        }
    }
}

// MARK: - Per-instrument song section

/// One instrument's "shared songs" rivals on the Rivals hub, loaded independently of its
/// siblings; it renders ``RivalInstrumentSongCard``. Compete reads its rivals for the
/// whole page instead (``CompeteHubModel``, #354) and uses the card directly.
struct RivalInstrumentSongSection: View {
    let session: FestivalSession
    let instrument: Instrument
    /// Scope a tapped rival opens with. `RivalsScreen` passes the Settings scope,
    /// as the web's `RivalsPage.navigateToRival` does for every hub section.
    var detailScope: RivalScope? = nil
    @State private var state: RivalsLoadState<RivalsListResponse> = .loading
    /// Skips the reload `.task(id:)` starts on every reappearance (Back from a pushed
    /// page), which flashed the rows to a spinner and shifted the page (#39).
    @State private var gate = ReappearanceLoadGate<RivalsSectionLoadKey<Instrument>>()

    private var loadKey: RivalsSectionLoadKey<Instrument> {
        RivalsSectionLoadKey(instrument, session: session)
    }

    var body: some View {
        RivalInstrumentSongCard(
            instrument: instrument, state: state, detailScope: detailScope
        ) { Task { await load() } }
        .task(id: loadKey) {
            guard gate.needsLoad(for: loadKey) else { return }
            await load()
        }
    }

    @MainActor
    private func load() async {
        let key = loadKey
        state = .loading
        do {
            state = .loaded(try await session.rivalsList(instrument: instrument))
            gate.markLoaded(key)
        } catch is CancellationError {
        } catch {
            state = .failed(ServiceIssue(error))
        }
    }
}

// MARK: - Per-instrument song card

/// One instrument's "shared songs" rivals card: its instrument header, the material card
/// of rows (or its spinner, empty copy or error), and "View All Rivals" below it.
///
/// Shared by the Rivals hub (``RivalInstrumentSongSection``, which loads it) and Compete
/// (which passes the page's state and its stagger position). On Compete a card may also
/// title a combo's server-computed rivals (web `CompetePage` rivals per ranking scope,
/// issue #602): its header draws the combo, View All Rivals and a tapped rival open the
/// combo scope.
struct RivalInstrumentSongCard: View {
    /// The card's board: one instrument's shared-song rivals, or a combo's rivals.
    let scope: RankingScope
    let state: RivalsLoadState<RivalsListResponse>
    /// Scope a tapped rival opens with; nil opens this instrument's comparison
    /// (web `CompetePage`: `combo: scope.queryValue`).
    var detailScope: RivalScope? = nil
    /// Whether the card registers its own Quick Links section. Compete passes false: it
    /// registers one coarser "Rivals" section instead.
    var registersQuickLink = true
    /// When set, an empty result renders this sentence instead of hiding the
    /// section entirely. `RivalsScreen` leaves this nil — its per-instrument
    /// sections are meant to be skipped when empty (`.agents/pages/rivals/ios.md`).
    /// `CompeteScreen` sets it: its coarse "Rivals" header must never show
    /// nothing underneath, matching the web's `compete.noRivalsSubtitle` copy and how its
    /// own Leaderboards section always renders a per-instrument card even when empty.
    var emptyMessage: String? = nil
    /// The card's place in the page's first-load stagger (Compete, #354); nil fades only
    /// loaded rows in as they arrive (the Rivals hub's independent sections).
    var entranceIndex: Int? = nil
    /// Reads the rivals again after a failure.
    let retry: () -> Void

    private let previewCount = 3

    /// Create a card for one instrument's or a combo's rivals.
    ///
    /// - Parameters:
    ///   - scope: The instrument or within-group combo.
    ///   - state: The rivals read.
    ///   - detailScope: Scope a tapped rival opens with; nil opens the card's own.
    ///   - registersQuickLink: Whether the card registers its own Quick Links section.
    ///   - emptyMessage: Copy for an empty result; nil hides the card.
    ///   - entranceIndex: The card's place in the page's first-load stagger.
    ///   - retry: Reads the rivals again after a failure.
    init(
        scope: RankingScope, state: RivalsLoadState<RivalsListResponse>, detailScope: RivalScope? = nil,
        registersQuickLink: Bool = true, emptyMessage: String? = nil, entranceIndex: Int? = nil,
        retry: @escaping () -> Void
    ) {
        self.scope = scope
        self.state = state
        self.detailScope = detailScope
        self.registersQuickLink = registersQuickLink
        self.emptyMessage = emptyMessage
        self.entranceIndex = entranceIndex
        self.retry = retry
    }

    /// Create a card for one instrument's shared-song rivals.
    ///
    /// - Parameters:
    ///   - instrument: The card's instrument.
    ///   - state: The rivals read.
    ///   - detailScope: Scope a tapped rival opens with; nil opens this instrument's.
    ///   - registersQuickLink: Whether the card registers its own Quick Links section.
    ///   - emptyMessage: Copy for an empty result; nil hides the card.
    ///   - entranceIndex: The card's place in the page's first-load stagger.
    ///   - retry: Reads the rivals again after a failure.
    init(
        instrument: Instrument, state: RivalsLoadState<RivalsListResponse>, detailScope: RivalScope? = nil,
        registersQuickLink: Bool = true, emptyMessage: String? = nil, entranceIndex: Int? = nil,
        retry: @escaping () -> Void
    ) {
        self.init(
            scope: .instrument(instrument), state: state, detailScope: detailScope,
            registersQuickLink: registersQuickLink, emptyMessage: emptyMessage,
            entranceIndex: entranceIndex, retry: retry
        )
    }

    /// The rivals scope of this card's own board: the instrument's shared songs, or the
    /// combo's server-computed list (web `Routes.allRivals(scope.queryValue)`).
    private var ownScope: RivalScope {
        switch scope {
        case let .instrument(instrument): .song(instruments: [instrument.rawValue])
        case let .combo(combo): .combo(token: combo.comboId, instruments: combo.instruments.map(\.rawValue))
        }
    }

    private var rowDetailScope: RivalScope {
        detailScope ?? ownScope
    }

    /// Identifier stem: `fst.rivals.song.<instrument>`, or `fst.rivals.combo.<comboId>`.
    private var identifierStem: String {
        switch scope {
        case let .instrument(instrument): "fst.rivals.song.\(instrument.rawValue)"
        case let .combo(combo): "fst.rivals.combo.\(combo.comboId)"
        }
    }

    /// The card's title, e.g. "Lead Rivals" or "Lead + Bass Rivals".
    private var title: String { "\(scope.label) Rivals" }

    /// The Mac keyboard group order of a rivals card: a combo's card sits just before its
    /// first instrument's, as Compete draws it (instrument order otherwise).
    ///
    /// - Parameter scope: The card's board.
    /// - Returns: The group order.
    static func keyboardOrder(for scope: RankingScope) -> Int {
        let first = scope.instruments.first.flatMap { Instrument.allCases.firstIndex(of: $0) } ?? 0
        if case .combo = scope { return 10 + 2 * first }
        return 11 + 2 * first
    }

    var body: some View {
        switch state {
        case .loading:
            shell { FestivalLoadingView(accessibilityLabel: "Loading").frame(maxWidth: .infinity).padding(.vertical, 12) }
        case let .failed(issue):
            entrance(shell { ServiceStatusInline(issue, scope: "rivals.song.\(scope.id)", retry: retry) })
        case let .loaded(response) where response.isEmpty:
            if let emptyMessage {
                entrance(shell { FestivalFootnote(emptyMessage) })
            } else {
                EmptyView()
            }
        case let .loaded(response):
            entrance(taggedShell(viewAll: RivalsViewAllButton(
                route: AppRoute.allRivals(scope: ownScope),
                identifier: "\(identifierStem).view-all",
                card: title
            )) {
                ForEach(previewRows(response)) { row in
                    ListDetailLink(
                        value: AppRoute.rivalDetail(
                            rivalId: row.rival.accountId, name: row.rival.displayName,
                            scope: rowDetailScope
                        )
                    ) {
                        RivalRowContent(rival: row.rival, direction: row.direction)
                    }
                    .accessibilityIdentifier("fst.rivals.row.\(row.rival.accountId)")
                    .macKeyboardRow("song.\(scope.id)|\(row.rival.accountId)")
                }
            }
            .macKeyboardRows(order: Self.keyboardOrder(for: scope), previewRows(response).map { row in
                MacKeyRow(
                    id: "song.\(scope.id)|\(row.rival.accountId)",
                    action: .route(.rivalDetail(
                        rivalId: row.rival.accountId, name: row.rival.displayName,
                        scope: rowDetailScope
                    ))
                )
            }), loadedOnly: true)
        }
    }

    /// The card's entrance: its place in the page stagger when it has one; otherwise
    /// loaded rows fade in as they arrive and messages appear at once.
    ///
    /// - Parameters:
    ///   - content: The settled card.
    ///   - loadedOnly: Whether this is the loaded rows (faded without a page stagger).
    /// - Returns: The card with its entrance fade.
    @ViewBuilder private func entrance<Content: View>(_ content: Content, loadedOnly: Bool = false) -> some View {
        if let entranceIndex {
            content.festivalFadeIn(isLoaded: true, index: entranceIndex)
        } else if loadedOnly {
            content.festivalFadeIn(isLoaded: true)
        } else {
            content
        }
    }

    private struct Row: Identifiable {
        let rival: RivalSummary
        let direction: RivalDirection
        var id: String { rival.accountId }
    }

    private func previewRows(_ response: RivalsListResponse) -> [Row] {
        response.above.prefix(previewCount).map { Row(rival: $0, direction: .above) }
            + response.below.prefix(previewCount).map { Row(rival: $0, direction: .below) }
    }

    /// The section's material card, ending with its optional "View All Rivals" button
    /// inside the card below the rows, like "View Full Leaderboard" (#41, #382).
    ///
    /// - Parameters:
    ///   - viewAll: Button that ends the card once rivals loaded; nil while loading or failed.
    ///   - content: The card's rows.
    /// - Returns: The padded section.
    @ViewBuilder private func shell<Content: View>(
        viewAll: RivalsViewAllButton? = nil, @ViewBuilder _ content: () -> Content
    ) -> some View {
        // Web `InstrumentHeader` SM (a combo: `CompeteScopeHeader`) above the card, never inside it.
        VStack(alignment: .leading, spacing: 8) {
            InstrumentSectionHeader(scope: scope, title: title)
            FestivalGlassSection { content() } action: { viewAll }
        }
        .padding(.horizontal, 16)
    }

    /// `shell(_:)`, additionally tagged as this instrument's own Quick Links
    /// section unless the enclosing page (`CompeteScreen`) opted out.
    @ViewBuilder private func taggedShell<Content: View>(
        viewAll: RivalsViewAllButton? = nil, @ViewBuilder _ content: () -> Content
    ) -> some View {
        if registersQuickLink, case let .instrument(instrument) = scope {
            shell(viewAll: viewAll, content).quickLinkSection(QuickLinkSection(
                id: instrument.rawValue, title: title, icon: .instrument(instrument)
            ))
        } else {
            shell(viewAll: viewAll, content)
        }
    }
}

// MARK: - Per-instrument leaderboard section

/// One instrument's global-leaderboard rivals, loaded independently of its siblings.
struct RivalInstrumentLeaderboardSection: View {
    let session: FestivalSession
    let instrument: Instrument
    let rankBy: RivalRankMetric
    @State private var state: RivalsLoadState<LeaderboardRivalsListResponse> = .loading
    /// Skips the reload `.task(id:)` starts on every reappearance (#39, #410).
    @State private var gate = ReappearanceLoadGate<RivalsSectionLoadKey<TaskKey>>()

    private let previewCount = 3

    private var loadKey: RivalsSectionLoadKey<TaskKey> {
        RivalsSectionLoadKey(TaskKey(instrument: instrument, rankBy: rankBy), session: session)
    }

    var body: some View {
        content.task(id: loadKey) {
            guard gate.needsLoad(for: loadKey) else { return }
            await load()
        }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            shell { FestivalLoadingView(accessibilityLabel: "Loading").frame(maxWidth: .infinity).padding(.vertical, 12) }
        case let .failed(issue):
            shell { ServiceStatusInline(issue, scope: "rivals.leaderboard.\(instrument.rawValue)") { Task { await load() } } }
        case let .loaded(response) where response.isEmpty:
            EmptyView()
        case let .loaded(response):
            shell(viewAll: RivalsViewAllButton(
                route: AppRoute.allRivals(
                    scope: .leaderboard(instrument: instrument.rawValue, rankBy: rankBy)
                ),
                identifier: "fst.rivals.leaderboard.\(instrument.rawValue).view-all",
                card: "\(instrument.label) Rivals"
            )) {
                ForEach(previewRows(response)) { row in
                    ListDetailLink(
                        value: AppRoute.rivalDetail(
                            rivalId: row.rival.accountId, name: row.rival.displayName,
                            scope: .leaderboard(instrument: instrument.rawValue, rankBy: rankBy)
                        )
                    ) {
                        RivalRowContent(rival: row.rival, direction: row.direction)
                    }
                    .accessibilityIdentifier("fst.rivals.row.\(row.rival.accountId)")
                    .macKeyboardRow("leaderboard.\(instrument.rawValue)|\(row.rival.accountId)")
                }
            }
            .macKeyboardRows(order: RivalInstrumentSongCard.keyboardOrder(for: .instrument(instrument)), previewRows(response).map { row in
                MacKeyRow(
                    id: "leaderboard.\(instrument.rawValue)|\(row.rival.accountId)",
                    action: .route(.rivalDetail(
                        rivalId: row.rival.accountId, name: row.rival.displayName,
                        scope: .leaderboard(instrument: instrument.rawValue, rankBy: rankBy)
                    ))
                )
            })
            .quickLinkSection(QuickLinkSection(
                id: instrument.rawValue, title: "\(instrument.label) Rivals", icon: .instrument(instrument)
            ))
            .festivalFadeIn(isLoaded: true)
        }
    }

    /// What the section reads: its instrument's board ranked by `rankBy`.
    struct TaskKey: Hashable, Sendable {
        let instrument: Instrument
        let rankBy: RivalRankMetric
    }

    private struct Row: Identifiable {
        let rival: LeaderboardRivalSummary
        let direction: RivalDirection
        var id: String { rival.accountId }
    }

    private func previewRows(_ response: LeaderboardRivalsListResponse) -> [Row] {
        response.above.prefix(previewCount).map { Row(rival: $0, direction: .above) }
            + response.below.prefix(previewCount).map { Row(rival: $0, direction: .below) }
    }

    /// The section's material card, ending with its optional "View All Rivals" button
    /// inside the card below the rows, like "View Full Leaderboard" (#41, #382).
    ///
    /// - Parameters:
    ///   - viewAll: Button that ends the card once rivals loaded; nil while loading or failed.
    ///   - content: The card's rows.
    /// - Returns: The padded section.
    @ViewBuilder private func shell<Content: View>(
        viewAll: RivalsViewAllButton? = nil, @ViewBuilder _ content: () -> Content
    ) -> some View {
        // Web `InstrumentHeader` SM above the card, never inside it.
        VStack(alignment: .leading, spacing: 8) {
            InstrumentSectionHeader(instrument, title: "\(instrument.label) Rivals")
            FestivalGlassSection { content() } action: { viewAll }
        }
        .padding(.horizontal, 16)
    }

    @MainActor
    private func load() async {
        let key = loadKey
        state = .loading
        do {
            state = .loaded(try await session.leaderboardRivals(instrument: instrument, rankBy: rankBy))
            gate.markLoaded(key)
        } catch is CancellationError {
        } catch {
            state = .failed(ServiceIssue(error))
        }
    }
}

// MARK: - Section load key

/// What a Rivals hub section's read depends on: its `scope` (instrument, visible
/// instruments, combo token or leaderboard metric), the selected account and the
/// publication. A change to any part reloads the section, while a plain reappearance
/// (Back from a pushed page) keeps its loaded rows (``ReappearanceLoadGate``, #39, #410).
/// Compete keys its whole page with ``CompetePageLoadKey`` instead.
struct RivalsSectionLoadKey<Scope: Hashable & Sendable>: Hashable, Sendable {
    let scope: Scope
    let accountId: String?
    let publicationRevision: Int

    /// Build the key from the section's scope and the session's current state.
    ///
    /// - Parameters:
    ///   - scope: What the section reads.
    ///   - session: Shared session; its selected account and publication revision.
    @MainActor
    init(_ scope: Scope, session: FestivalSession) {
        self.scope = scope
        accountId = session.selectedPlayer?.accountId
        publicationRevision = session.publicationRevision
    }
}

// MARK: - Rail priority

private extension ToolbarContent {
    /// High visibility priority for Find Rival while the chrome is the iPhone Duo
    /// vertical bar (iOS 27+); horizontal bars keep the default ordering.
    ///
    /// - Parameter isVerticalBar: Whether the section chrome is the vertical bar.
    /// - Returns: The toolbar content with its rail priority.
    @ToolbarContentBuilder
    func rivalsRailPriority(isVerticalBar: Bool) -> some ToolbarContent {
        #if os(iOS)
        if #available(iOS 27.0, *) {
            visibilityPriority(isVerticalBar ? .high : .automatic)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
