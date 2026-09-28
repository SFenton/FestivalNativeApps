#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Wrong-account regression tests

// Regression coverage for the "searched player's profile shows a different
// account" bug (Lane Z2, 2026-09-28). Root cause: `ProfileSelectionSheet` (and
// `FindRivalSheet`) put every search result inside one `LazyVStack`, i.e. one Form
// row. On iOS that row fired every result's default-style Button on a single tap,
// pushing one `AppRoute.player` per result with the last one on top. The iOS
// behavior itself is covered on-device by `ProfileJourneyTests`; these hosted tests
// pin the structural invariant (one List row per result) and the per-account
// render guard that stops a surviving view identity from drawing another account.

/// Counts the direct children a `List`/`Form` would split `content` into rows.
private struct ListRowCounter: _VariadicView_MultiViewRoot {
    let onCount: (Int) -> Void

    func body(children: _VariadicView.Children) -> some View {
        let count = children.count
        return Color.clear.onAppear { onCount(count) }
    }
}

/// Holds a count reported from a hosted SwiftUI body.
@MainActor
private final class CountBox {
    var value: Int?
}

/// Render `content` offscreen and report how many List rows it would produce.
///
/// - Parameter content: The exact view a sheet places inside one `Section`.
/// - Returns: Number of variadic children (List rows), once the body appears.
/// - Throws: The hosted body never appearing.
@MainActor
private func listRowCount<Content: View>(_ content: Content) async throws -> Int {
    let box = CountBox()
    let size = CGSize(width: 390, height: 400)
    let host = nativeHostedView(
        _VariadicView.Tree(ListRowCounter { box.value = $0 }) { content },
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.contentView = nil }
    for _ in 0..<20 where box.value == nil {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
    }
    return try #require(box.value)
}

/// Three synthetic, validated search results.
private func threeResults() throws -> [PlayerSearchResult] {
    try JSONDecoder().decode([PlayerSearchResult].self, from: Data("""
    [{"accountId":"fixture-player-1","displayName":"Fixture Player 1"},
     {"accountId":"fixture-player-2","displayName":"Fixture Player 2"},
     {"accountId":"fixture-cpp","displayName":"C++"}]
    """.utf8))
}

/// Each result must be its own List row: a single row holding several Buttons
/// fires all of them on iOS, which is what pushed the wrong account's profile.
@MainActor
@Test func playerSearchResultRowsGiveEachResultItsOwnListRow() async throws {
    let results = try threeResults()
    let rows = PlayerSearchResultRows(results) { Button($0.displayName) {} }
    #expect(try await listRowCount(rows) == results.count)

    // Control: the pre-fix shape (every result inside one stack) is one row, so
    // this test genuinely fails if the rows are ever re-wrapped.
    let wrapped = LazyVStack { PlayerSearchResultRows(results) { Button($0.displayName) {} } }
    #expect(try await listRowCount(wrapped) == 1)
}

// MARK: - Per-account render guard

/// Build a validated available payload for one synthetic account.
///
/// - Parameter accountId: Fixture account ID owning the payload.
/// - Returns: An available payload whose profile belongs to `accountId`.
private func payload(for accountId: String) throws -> PlayerProfilePayload {
    let profile = try JSONDecoder().decode(PlayerProfileResponse.self, from: Data("""
    {"accountId":"\(accountId)","displayName":"Name \(accountId)","totalScores":0,"scores":[]}
    """.utf8))
    return PlayerProfilePayload(
        profile: profile, state: .available, publicationId: 7, observedPublicationId: 7
    )
}

/// A view that survives an account change (Statistics root after a switch) must
/// never draw the previous account's payload under the new account's identity.
@Test func profilePhaseNeverShowsAnotherAccountsPayload() throws {
    let phase = PlayerProfilePhase.available(try payload(for: "fixture-player-1"))

    guard case .loading = phase.shown(for: "fixture-player-2") else {
        Issue.record("Another account's payload was shown instead of loading")
        return
    }
    guard case let .available(own) = phase.shown(for: "fixture-player-1") else {
        Issue.record("The matching account's payload was hidden")
        return
    }
    #expect(own.profile.accountId == "fixture-player-1")
    // Account keys compare case-insensitively, matching `validate(requestedAccountId:)`.
    guard case .available = phase.shown(for: "FIXTURE-PLAYER-1") else {
        Issue.record("A case-only difference hid the matching account")
        return
    }
    guard case .syncing = PlayerProfilePhase.syncing.shown(for: "fixture-player-2") else {
        Issue.record("Non-payload phases must pass through unchanged")
        return
    }
}
#endif
