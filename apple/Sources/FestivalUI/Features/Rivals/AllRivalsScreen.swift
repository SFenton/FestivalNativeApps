import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - AllRivalsScreen

/// `/rivals/all?category=&mode=&rankBy=` — full rival list for one scope.
///
/// The web's `AllRivalsPage` takes independent `category`/`mode`/`rankBy` query
/// parameters; native `AppRoute.allRivals(scope:)` carries the same information as
/// one typed, `Hashable` `RivalScope` instead (`song`, `leaderboard` or `combo`).
struct AllRivalsScreen: View {
    let session: FestivalSession
    let scope: RivalScope
    @State private var state: RivalsLoadState<[AllRivalsRow]> = .loading
    /// Rival shown in the dual-source bottom region (Duo inner display, portrait).
    @State private var dualSelection: AppRoute?
    /// The in-list title has scrolled under the bar: the bar shows the compact
    /// instrument icon and title instead (Full Rankings, issues #294, #557).
    @State private var titleHidden = false
    @Environment(\.openProfile) private var openProfile
    @Environment(\.deviceLayout) private var layout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).
    ///   - scope: Scope this list was reached under (`RivalsScreen`/`CompeteScreen`
    ///     pass the same scope they used to load their own preview section).
    init(session: FestivalSession, scope: RivalScope) {
        self.session = session
        self.scope = scope
    }

    // MARK: - Scope

    /// The scope's constituent instruments, resolved from their raw values.
    ///
    /// A `.song` scope with 2+ instruments is "Common Rivals" (an intersection,
    /// not a single list); everything else names exactly one queried scope.
    ///
    /// - Parameter scope: The list's scope.
    /// - Returns: The known instruments, in scope order.
    nonisolated static func instruments(for scope: RivalScope) -> [Instrument] {
        switch scope {
        case let .song(raw): raw.compactMap(Instrument.init(rawValue:))
        case let .leaderboard(raw, _): Instrument(rawValue: raw).map { [$0] } ?? []
        case let .combo(_, raw): raw.compactMap(Instrument.init(rawValue:))
        }
    }

    /// Whether a scope is "Common Rivals": a `.song` scope naming 2+ instruments.
    ///
    /// - Parameter scope: The list's scope.
    /// - Returns: True for the intersection of several per-instrument lists.
    nonisolated static func isCommon(_ scope: RivalScope) -> Bool {
        if case let .song(raw) = scope { return raw.count > 1 }
        return false
    }

    /// The page title: the navigation title (Back menus, the Mac window, VoiceOver)
    /// and the text of the in-list and bar titles.
    ///
    /// - Parameter scope: The list's scope.
    /// - Returns: e.g. "Lead Rivals", "Lead Leaderboard Rivals", "Common Rivals".
    nonisolated static func title(for scope: RivalScope) -> String {
        let first = instruments(for: scope).first?.label ?? ""
        switch scope {
        case .leaderboard:
            return "\(first) Leaderboard Rivals"
        case .song where isCommon(scope):
            return "Common Rivals"
        case .song:
            return "\(first) Rivals"
        case let .combo(token, _):
            let label = token == RivalCombo.proDrumsToken ? "Pro Drums Family" : "Combo"
            return "\(label) Rivals"
        }
    }

    /// The instrument whose icon leads the title: only a single-instrument list (song
    /// or leaderboard rivals). Common and Combo lists have no icon, like the web
    /// `AllRivalsPage` (`InstrumentHeader iconOnly` only when `isInstrument`).
    ///
    /// - Parameter scope: The list's scope.
    /// - Returns: The scope's one instrument, or nil.
    nonisolated static func titleInstrument(for scope: RivalScope) -> Instrument? {
        switch scope {
        case .song where isCommon(scope), .combo:
            nil
        case .song, .leaderboard:
            instruments(for: scope).first
        }
    }

    private var instruments: [Instrument] { Self.instruments(for: scope) }
    private var isCommon: Bool { Self.isCommon(scope) }
    private var title: String { Self.title(for: scope) }

    /// Whether the bar shows the compact title: once the in-list title has scrolled
    /// away, and in every state without an in-list title (loading, empty, failure,
    /// no profile), like Full Rankings.
    private var showsPinnedTitle: Bool {
        guard session.selectedPlayer != nil, !instruments.isEmpty,
              case let .loaded(rows) = state, !rows.isEmpty else { return true }
        return titleHidden
    }

    // MARK: - Body

    var body: some View {
        Group {
            if session.selectedPlayer == nil {
                RivalsChooseProfileState { openProfile() }
            } else if instruments.isEmpty {
                FestivalEmptyState(
                    "Unknown Category", systemImage: "questionmark.circle",
                    subtitle: "This rivals list could not be identified."
                )
            } else {
                content
            }
        }
        .festivalNavigationTitle(title)
        .festivalBackground(.carousel, session: session)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showsPinnedTitle)
        .toolbar {
            #if os(iOS)
            // The iPhone Duo vertical bar minimizes its top bar on scroll, so a custom
            // title would leave when due; the system title stays there (R14).
            if !layout.sectionChrome.isVerticalBar {
                InstrumentPageTitleToolbarItem(
                    instrument: Self.titleInstrument(for: scope), title: title,
                    isShown: showsPinnedTitle, identifier: "fst.all-rivals.pinned-title"
                )
            }
            #endif
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: scope) { await load() }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            FestivalLoadingView(accessibilityLabel: "Loading rivals")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(issue):
            ServiceStatusView(issue, title: "Rivals Unavailable") { Task { await load() } }
        case let .loaded(rows) where rows.isEmpty:
            FestivalEmptyState(
                "No Rivals Yet", systemImage: "person.2.slash",
                subtitle: "No rivals have been found for this scope yet."
            )
        case let .loaded(rows):
            // iPhone Duo inner display, portrait: the list on top, the selected
            // rival's rivalry below (`RivalsDualSource.swift`).
            DualSourceLayout {
                list(rows).dualSourceSelection($dualSelection, section: .rivals)
            } secondary: {
                RivalDualDetailPane(session: session, selection: dualSelection)
            }
        }
    }

    private func list(_ rows: [AllRivalsRow]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // The page's own title, icon first, like Full Rankings (#557); the
                // card below repeats no section title (web `AllRivalsPage`).
                InstrumentPageTitle(
                    instrument: Self.titleInstrument(for: scope), title: title, style: .header,
                    identifier: "fst.all-rivals.title"
                )
                .padding(.horizontal, 16)
                .festivalFadeInOnAppear()
                .onGeometryChange(for: Bool.self) { proxy in
                    SongDetailPinnedTitlePolicy.isHeroHidden(
                        titleMaxY: proxy.frame(in: .scrollView).maxY
                    )
                } action: { hidden in
                    titleHidden = hidden
                }
                FestivalGlassSection {
                    ForEach(rows) { row in
                        ListDetailLink(
                            value: AppRoute.rivalDetail(
                                rivalId: row.accountId, name: row.displayName, scope: scope
                            )
                        ) {
                            row.content
                        }
                        .accessibilityIdentifier("fst.all-rivals.row.\(row.accountId)")
                    }
                }
                .padding(.horizontal, 16)
                .festivalFadeIn(isLoaded: true)
            }
            .padding(.vertical, 12)
        }
    }

    @MainActor
    private func load() async {
        guard !instruments.isEmpty else {
            state = .loaded([])
            return
        }
        state = .loading
        do {
            switch scope {
            case .song where isCommon:
                var lists: [RivalsListResponse] = []
                for instrument in instruments {
                    if let list = try? await session.rivalsList(instrument: instrument) {
                        lists.append(list)
                    }
                }
                let result = RivalCommonRivals.intersect(lists)
                state = .loaded(
                    result.above.map { AllRivalsRow($0, direction: .above) }
                        + result.below.map { AllRivalsRow($0, direction: .below) }
                )
            case .song:
                guard let instrument = instruments.first else { state = .loaded([]); return }
                let response = try await session.rivalsList(instrument: instrument)
                state = .loaded(
                    response.above.map { AllRivalsRow($0, direction: .above) }
                        + response.below.map { AllRivalsRow($0, direction: .below) }
                )
            case let .leaderboard(_, rankBy):
                guard let instrument = instruments.first else { state = .loaded([]); return }
                let response = try await session.leaderboardRivals(instrument: instrument, rankBy: rankBy)
                state = .loaded(
                    response.above.map { AllRivalsRow($0, direction: .above) }
                        + response.below.map { AllRivalsRow($0, direction: .below) }
                )
            case let .combo(token, _):
                let response = try await session.rivalsComboList(token: token)
                state = .loaded(
                    response.above.map { AllRivalsRow($0, direction: .above) }
                        + response.below.map { AllRivalsRow($0, direction: .below) }
                )
            }
        } catch is CancellationError {
        } catch {
            state = .failed(ServiceIssue(error))
        }
    }
}

/// Type-erased row so one list can render either `RivalSummary` or
/// `LeaderboardRivalSummary` rows without duplicating the screen body.
struct AllRivalsRow: Identifiable {
    let accountId: String
    let displayName: String?
    let direction: RivalDirection
    let content: AnyView

    init(_ rival: RivalSummary, direction: RivalDirection) {
        accountId = rival.accountId
        displayName = rival.displayName
        self.direction = direction
        content = AnyView(RivalRowContent(rival: rival, direction: direction))
    }

    init(_ rival: LeaderboardRivalSummary, direction: RivalDirection) {
        accountId = rival.accountId
        displayName = rival.displayName
        self.direction = direction
        content = AnyView(RivalRowContent(rival: rival, direction: direction))
    }

    var id: String { accountId }
}
