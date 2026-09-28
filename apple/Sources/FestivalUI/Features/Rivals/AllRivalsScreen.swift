import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - AllRivalsScreen

/// `/rivals/all?category=` — full rival list for one scope.
///
/// The web's `AllRivalsPage` additionally supports a "common rivals" (shared
/// across every visible instrument) and multi-instrument "combo" category; this
/// native pass covers the single-instrument song and leaderboard scopes that
/// `RivalsScreen`/`CompeteScreen` link to (see `RivalAllCategory`).
struct AllRivalsScreen: View {
    let session: FestivalSession
    let category: String
    @State private var state: RivalsLoadState<[AllRivalsRow]> = .loading
    @Environment(\.openProfile) private var openProfile

    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).
    ///   - category: Encoded scope from `RivalAllCategory.encoded`.
    init(session: FestivalSession, category: String) {
        self.session = session
        self.category = category
    }

    private var scope: RivalAllCategory? { RivalAllCategory.decode(category) }

    private var instrument: Instrument? {
        switch scope {
        case let .song(raw), let .leaderboard(raw, _): Instrument(rawValue: raw)
        case nil: nil
        }
    }

    var body: some View {
        Group {
            if session.selectedPlayer == nil {
                RivalsChooseProfileState { openProfile() }
            } else if instrument == nil {
                ContentUnavailableView(
                    "Unknown Category", systemImage: "questionmark.circle",
                    description: Text("This rivals list could not be identified.")
                )
            } else {
                content
            }
        }
        .navigationTitle(title)
        .festivalBackground(.carousel, session: session)
        .task(id: category) { await load() }
    }

    private var title: String {
        guard let instrument else { return "Rivals" }
        if case .leaderboard = scope {
            return "\(instrument.label) Leaderboard Rivals"
        }
        return "\(instrument.label) Rivals"
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ServiceUnavailableView(
                title: "Rivals Unavailable", message: message
            ) { Task { await load() } }
        case let .loaded(rows) where rows.isEmpty:
            ContentUnavailableView(
                "No Rivals Yet", systemImage: "person.2.slash",
                description: Text("No rivals have been found for this scope yet.")
            )
        case let .loaded(rows):
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let instrument {
                        FestivalGlassSection(instrument.label) {
                            ForEach(rows) { row in
                                NavigationLink(
                                    value: AppRoute.rivalDetail(
                                        rivalId: row.accountId, name: row.displayName
                                    )
                                ) {
                                    row.content
                                }
                                .simultaneousGesture(TapGesture().onEnded {
                                    guard let scope else { return }
                                    RivalNavigationBridge.shared.stash(
                                        row.context(for: scope), forRivalId: row.accountId
                                    )
                                })
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    @MainActor
    private func load() async {
        guard let scope, let instrument else {
            state = .loaded([])
            return
        }
        state = .loading
        do {
            switch scope {
            case .song:
                let response = try await session.rivalsList(instrument: instrument)
                state = .loaded(
                    response.above.map { AllRivalsRow($0, direction: .above) }
                        + response.below.map { AllRivalsRow($0, direction: .below) }
                )
            case let .leaderboard(_, rankBy):
                let response = try await session.leaderboardRivals(instrument: instrument, rankBy: rankBy)
                state = .loaded(
                    response.above.map { AllRivalsRow($0, direction: .above) }
                        + response.below.map { AllRivalsRow($0, direction: .below) }
                )
            }
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
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

    /// Rebuild the navigation context for this row under the page's active scope.
    ///
    /// - Parameter scope: The category this list was loaded for.
    /// - Returns: Context stashed for the destination `RivalDetailScreen`/`RivalryScreen`.
    func context(for scope: RivalAllCategory) -> RivalRouteContext {
        switch scope {
        case let .song(instrument):
            return .song(instruments: [instrument])
        case let .leaderboard(instrument, rankBy):
            return .leaderboard(instrument: instrument, rankBy: rankBy)
        }
    }
}
