#if os(macOS)
import SwiftUI
import FestivalCore

// MARK: - Row context menus

/// Secondary-click menu for a Songs row (HIG Pointing devices › macOS: "Secondary click
/// — Reveal contextual menus"). Every item is also reachable in the main interface
/// (row click, Song Detail's leaderboard and history links, Edit › Copy on the selected
/// row), per HIG Context menus.
struct MacSongRowMenu: View {
    let song: Song
    /// The row's chart (filtered instrument, else the first visible one).
    let chart: Instrument?
    let hasPlayer: Bool
    @Environment(\.listDetailSelect) private var select
    @Environment(\.pushRoute) private var push

    var body: some View {
        Button("Open Song") { open(.songDetail(song)) }
        Button("Copy Title") { MacCopyPolicy.copy(song.title) }
        if let chart {
            Divider()
            Button("\(chart.label) Leaderboard") { open(.songLeaderboard(song, chart, 1)) }
            if hasPlayer {
                Button("\(chart.label) Score History") { open(.playerHistory(song, chart)) }
            }
        }
    }

    /// Show a route: into the detail column when two columns show, else pushed.
    private func open(_ route: AppRoute) {
        if case .songDetail = route, let select {
            select(route)
        } else {
            push?(route)
        }
    }
}

/// Secondary-click menu for a player row on leaderboards and rankings.
struct MacPlayerRowMenu: View {
    let accountId: String
    let displayName: String?
    @Environment(\.listDetailSelect) private var select
    @Environment(\.pushRoute) private var push

    var body: some View {
        Button("View Profile") {
            let route = AppRoute.player(accountId: accountId, displayName: displayName)
            if let select { select(route) } else { push?(route) }
        }
        Button("View Bands") { push?(.playerBands(accountId: accountId, displayName: displayName)) }
        if let displayName, !displayName.isEmpty {
            Button("Copy Name") { MacCopyPolicy.copy(displayName) }
        }
    }
}
#endif
