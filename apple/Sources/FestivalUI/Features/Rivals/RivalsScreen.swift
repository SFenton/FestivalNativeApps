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
    let session: FestivalSession
    @State private var tab: Tab = .song
    @State private var rankBy: RivalRankMetric = .totalscore
    @State private var quickLinks = QuickLinksController()
    @State private var findRivalPresented = false
    @Environment(\.openProfile) private var openProfile
    private var visible = VisibleInstrumentsReader()

    enum Tab: String, CaseIterable, Identifiable {
        case song = "Song"
        case leaderboard = "Leaderboard"
        var id: String { rawValue }
    }

    /// Create the screen.
    ///
    /// - Parameter session: Shared app session (API client, selected profile, caches).
    init(session: FestivalSession) {
        self.session = session
    }

    var body: some View {
        Group {
            if session.selectedPlayer == nil {
                RivalsChooseProfileState { openProfile() }
            } else {
                hub
            }
        }
        .navigationTitle("Rivals")
        .festivalBackground(.carousel, session: session)
        .toolbar {
            // Rivals is reached as a pushed page from the drawer (see
            // `.agents/controls/app-navigation/ios.md`'s "Pushed pages … don't show
            // the chrome"), so this adds only its own actions — no
            // `FestivalRootTrailingItems`/`.festivalProvidesRootTrailingItems()`.
            // The enclosing `festivalRootChrome` still supplies bell/avatar on the
            // rare root presentation (e.g. a future iPad/Mac sidebar destination).
            ToolbarItem(placement: .primaryAction) {
                Button {
                    findRivalPresented = true
                } label: {
                    Label("Find Rival", systemImage: "magnifyingglass")
                }
                .accessibilityIdentifier("fst.rivals.findRival")
            }
            QuickLinksToolbarItem(quickLinks)
        }
        .sheet(isPresented: $findRivalPresented) {
            FindRivalSheet(session: session)
                .festivalSheet()
        }
    }

    private var instruments: [Instrument] { visible.instruments }
    private var comboScope: RivalComboScope? { RivalCombo.deriveScope(visible: instruments) }

    @ViewBuilder private var hub: some View {
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
                        RivalInstrumentSongSection(session: session, instrument: instrument)
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
        // Every section below loads for `session.selectedPlayer` but keys its
        // `task(id:)` only on instrument/scope; this hub survives a profile switch
        // (tab root, or pushed on a stack the switch does not reset), so key the
        // sections' state by the selected account or they keep the old account's
        // rivals (`.agents/platforms/apple/architecture.md`, "Per-entity screens").
        .id(session.selectedPlayer?.accountId)
    }

    private var rankByPicker: some View {
        HStack {
            Spacer()
            Menu {
                ForEach(RivalRankMetric.allCases) { metric in
                    Button(metric.label) { rankBy = metric }
                }
            } label: {
                Label(rankBy.label, systemImage: "arrow.up.arrow.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BrandTokens.textPrimary)
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

    private let previewCount = 3

    var body: some View {
        content.task(id: instruments) { await load() }
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
            shell {
                ForEach(previewRows(result)) { row in
                    NavigationLink(value: AppRoute.rivalDetail(
                        rivalId: row.rival.accountId, name: row.rival.displayName,
                        scope: .song(instruments: instruments.map(\.rawValue))
                    )) {
                        RivalRowContent(rival: row.rival, direction: row.direction)
                    }
                    .accessibilityIdentifier("fst.rivals.row.\(row.rival.accountId)")
                }
                NavigationLink(
                    value: AppRoute.allRivals(scope: .song(instruments: instruments.map(\.rawValue)))
                ) {
                    RivalViewAllRow(title: "View All Rivals")
                }
            }
            .quickLinkSection(id: "common", title: "Common Rivals", symbol: "person.2.fill")
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

    @ViewBuilder private func shell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        FestivalGlassSection("Common Rivals") { content() }
            .padding(.horizontal, 16)
    }

    @MainActor
    private func load() async {
        state = .loading
        var lists: [RivalsListResponse] = []
        // Sequential rather than a `TaskGroup`, matching `combinedRivalDetail`: at
        // most a handful of instruments, and this keeps every read on the
        // session's own `@MainActor` isolation.
        for instrument in instruments {
            if let list = try? await session.rivalsList(instrument: instrument) {
                lists.append(list)
            }
        }
        state = .loaded(RivalCommonRivals.intersect(lists))
    }
}

// MARK: - Combo section

/// One cross-instrument "combo" (or Pro Drums family) scope, a server-computed
/// distinct rivals list rather than a client-side merge (native `RivalCombo.deriveScope`).
struct RivalComboSection: View {
    let session: FestivalSession
    let scope: RivalComboScope
    @State private var state: RivalsLoadState<RivalsListResponse> = .loading

    private let previewCount = 3

    var body: some View {
        content.task(id: scope.token) { await load() }
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
            shell {
                ForEach(previewRows(response)) { row in
                    NavigationLink(value: AppRoute.rivalDetail(
                        rivalId: row.rival.accountId, name: row.rival.displayName,
                        scope: .combo(token: scope.token, instruments: scope.instruments.map(\.rawValue))
                    )) {
                        RivalRowContent(rival: row.rival, direction: row.direction)
                    }
                    .accessibilityIdentifier("fst.rivals.row.\(row.rival.accountId)")
                }
                NavigationLink(value: AppRoute.allRivals(
                    scope: .combo(token: scope.token, instruments: scope.instruments.map(\.rawValue))
                )) {
                    RivalViewAllRow(title: "View All Rivals")
                }
            }
            .quickLinkSection(id: "combo", title: "\(scope.label) Rivals", symbol: "music.note")
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

    @ViewBuilder private func shell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        FestivalGlassSection("\(scope.label) Rivals") { content() }
            .padding(.horizontal, 16)
    }

    @MainActor
    private func load() async {
        state = .loading
        do {
            state = .loaded(try await session.rivalsComboList(token: scope.token))
        } catch is CancellationError {
        } catch {
            state = .failed(ServiceIssue(error))
        }
    }
}

// MARK: - Per-instrument song section

/// One instrument's "shared songs" rivals, loaded independently of its siblings.
///
/// Shared verbatim by `CompeteScreen`, which registers its own coarser "Rivals"
/// Quick Links section instead of one per instrument — pass
/// `registersQuickLink: false` there so this view's own per-instrument tag
/// doesn't also register into the enclosing page's controller.
struct RivalInstrumentSongSection: View {
    let session: FestivalSession
    let instrument: Instrument
    var registersQuickLink = true
    @State private var state: RivalsLoadState<RivalsListResponse> = .loading

    private let previewCount = 3

    var body: some View {
        content.task(id: instrument) { await load() }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            shell { FestivalLoadingView(accessibilityLabel: "Loading").frame(maxWidth: .infinity).padding(.vertical, 12) }
        case let .failed(issue):
            shell { ServiceStatusInline(issue, scope: "rivals.song.\(instrument.rawValue)") { Task { await load() } } }
        case let .loaded(response) where response.isEmpty:
            EmptyView()
        case let .loaded(response):
            taggedShell {
                ForEach(previewRows(response)) { row in
                    NavigationLink(
                        value: AppRoute.rivalDetail(
                            rivalId: row.rival.accountId, name: row.rival.displayName,
                            scope: .song(instruments: [instrument.rawValue])
                        )
                    ) {
                        RivalRowContent(rival: row.rival, direction: row.direction)
                    }
                    .accessibilityIdentifier("fst.rivals.row.\(row.rival.accountId)")
                }
                NavigationLink(
                    value: AppRoute.allRivals(scope: .song(instruments: [instrument.rawValue]))
                ) {
                    RivalViewAllRow(title: "View All Rivals")
                }
            }
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

    @ViewBuilder private func shell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        FestivalGlassSection(instrument.label) { content() }
            .padding(.horizontal, 16)
    }

    /// `shell(_:)`, additionally tagged as this instrument's own Quick Links
    /// section unless the enclosing page (`CompeteScreen`) opted out.
    @ViewBuilder private func taggedShell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if registersQuickLink {
            shell(content).quickLinkSection(QuickLinkSection(
                id: instrument.rawValue, title: "\(instrument.label) Rivals", icon: .instrument(instrument)
            ))
        } else {
            shell(content)
        }
    }

    @MainActor
    private func load() async {
        state = .loading
        do {
            state = .loaded(try await session.rivalsList(instrument: instrument))
        } catch is CancellationError {
        } catch {
            state = .failed(ServiceIssue(error))
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

    private let previewCount = 3

    var body: some View {
        content.task(id: TaskKey(instrument: instrument, rankBy: rankBy)) { await load() }
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
            shell {
                ForEach(previewRows(response)) { row in
                    NavigationLink(
                        value: AppRoute.rivalDetail(
                            rivalId: row.rival.accountId, name: row.rival.displayName,
                            scope: .leaderboard(instrument: instrument.rawValue, rankBy: rankBy)
                        )
                    ) {
                        RivalRowContent(rival: row.rival, direction: row.direction)
                    }
                    .accessibilityIdentifier("fst.rivals.row.\(row.rival.accountId)")
                }
                NavigationLink(
                    value: AppRoute.allRivals(
                        scope: .leaderboard(instrument: instrument.rawValue, rankBy: rankBy)
                    )
                ) {
                    RivalViewAllRow(title: "View All Rivals")
                }
            }
            .quickLinkSection(QuickLinkSection(
                id: instrument.rawValue, title: "\(instrument.label) Rivals", icon: .instrument(instrument)
            ))
        }
    }

    private struct TaskKey: Equatable {
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

    @ViewBuilder private func shell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        FestivalGlassSection(instrument.label) { content() }
            .padding(.horizontal, 16)
    }

    @MainActor
    private func load() async {
        state = .loading
        do {
            state = .loaded(try await session.leaderboardRivals(instrument: instrument, rankBy: rankBy))
        } catch is CancellationError {
        } catch {
            state = .failed(ServiceIssue(error))
        }
    }
}
