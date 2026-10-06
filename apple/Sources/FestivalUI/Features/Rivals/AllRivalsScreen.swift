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
    @Environment(\.openProfile) private var openProfile

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

    /// The scope's constituent instruments, resolved from their raw values.
    ///
    /// A `.song` scope with 2+ instruments is "Common Rivals" (an intersection,
    /// not a single list); everything else names exactly one queried scope.
    private var instruments: [Instrument] {
        switch scope {
        case let .song(raw): raw.compactMap(Instrument.init(rawValue:))
        case let .leaderboard(raw, _): Instrument(rawValue: raw).map { [$0] } ?? []
        case let .combo(_, raw): raw.compactMap(Instrument.init(rawValue:))
        }
    }

    private var isCommon: Bool {
        if case let .song(raw) = scope { return raw.count > 1 }
        return false
    }

    var body: some View {
        Group {
            if session.selectedPlayer == nil {
                RivalsChooseProfileState { openProfile() }
            } else if instruments.isEmpty {
                ContentUnavailableView(
                    "Unknown Category", systemImage: "questionmark.circle",
                    description: Text("This rivals list could not be identified.")
                )
            } else {
                content
            }
        }
        .festivalNavigationTitle(title)
        .festivalBackground(.carousel, session: session)
        .task(id: scope) { await load() }
    }

    private var title: String {
        switch scope {
        case .leaderboard:
            return "\(instruments.first?.label ?? "") Leaderboard Rivals"
        case .song where isCommon:
            return "Common Rivals"
        case .song:
            return "\(instruments.first?.label ?? "") Rivals"
        case let .combo(token, _):
            let label = token == RivalCombo.proDrumsToken ? "Pro Drums Family" : "Combo"
            return "\(label) Rivals"
        }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            FestivalLoadingView(accessibilityLabel: "Loading rivals")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(issue):
            ServiceStatusView(issue, title: "Rivals Unavailable") { Task { await load() } }
        case let .loaded(rows) where rows.isEmpty:
            ContentUnavailableView(
                "No Rivals Yet", systemImage: "person.2.slash",
                description: Text("No rivals have been found for this scope yet.")
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
            VStack(alignment: .leading, spacing: 20) {
                FestivalGlassSection(title) {
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
