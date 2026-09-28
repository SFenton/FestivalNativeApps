import SwiftUI
import FestivalCore

// MARK: - PlayerSearchResultRows

/// One `List`/`Form` row per player search result — shared by
/// `ProfileSelectionSheet` and `FindRivalSheet`.
///
/// **Why this exists (wrong-account bug, 2026-09-28):** both sheets used to wrap
/// every result in a single `LazyVStack` inside one `Form` row. On iOS a List row
/// whose Buttons/NavigationLinks use the default (`.automatic`) style makes the
/// *whole row* the hit target and fires **every** such control in it on one tap.
/// Tapping "Fixture Player 1" therefore pushed one `AppRoute.player` per result, and
/// the last result's profile ended up on top, so a searched player's page showed a
/// different account. Each result must be its own row, so this view's body is a
/// bare `ForEach`. Never wrap it (or its rows) in a stack; see
/// `.agents/platforms/apple/architecture.md`, "List rows hold one action".
struct PlayerSearchResultRows<Row: View>: View {
    let results: [PlayerSearchResult]
    let row: (PlayerSearchResult) -> Row

    /// Create one row per result.
    ///
    /// - Parameters:
    ///   - results: Validated search results, in service order.
    ///   - row: The single tappable control for one result (one Button or link).
    init(_ results: [PlayerSearchResult], @ViewBuilder row: @escaping (PlayerSearchResult) -> Row) {
        self.results = results
        self.row = row
    }

    var body: some View {
        ForEach(results) { player in
            row(player)
        }
    }
}
