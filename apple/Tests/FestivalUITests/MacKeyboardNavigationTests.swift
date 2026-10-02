import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Fixtures

private func row(_ id: String) -> MacKeyRow {
    MacKeyRow(id: id, action: .url(URL(string: "https://example.com/\(id)")!))
}

private func group(_ ids: [String], order: Int = 0, columns: Int = 1) -> MacKeyRowGroup {
    MacKeyRowGroup(order: order, columns: columns, rows: ids.map(row))
}

private func offer(_ id: String) -> ShopSong {
    ShopSong(
        songId: id, title: id.capitalized, artist: "Synthetic Quartet", year: nil, albumArt: nil,
        shopUrl: URL(string: "https://www.fortnite.com/item-shop/jam-tracks/\(id)")!,
        leavingTomorrow: false, isNew: false
    )
}

private func rankingRow(_ accountId: String, rank: Int) throws -> AccountRankingEntry {
    let data = Data("""
    {"accountId":"\(accountId)","displayName":"Player \(rank)","songsPlayed":10,
     "totalChartedSongs":729,"coverage":0.5,"rawSkillRating":0.01,
     "adjustedSkillRating":0.01,"adjustedSkillRank":\(rank),"weightedRating":0.02,
     "weightedRank":\(rank),"fcRate":0.4,"fcRateRank":\(rank),"totalScore":1000,
     "totalScoreRank":\(rank),"maxScorePercent":0.9,"maxScorePercentRank":\(rank),
     "avgAccuracy":950000,"fullComboCount":5,"avgStars":4.0,"bestRank":1,"avgRank":2.0}
    """.utf8)
    return try JSONDecoder().decode(AccountRankingEntry.self, from: data)
}

// MARK: - List moves

/// ↓/↑ step one row; with nothing highlighted ↓ starts at the top and ↑ at the bottom;
/// the ends do nothing (the key passes on); Home/End jump.
@Test func macKeyboardListMoves() {
    let list = [group(["a", "b", "c"])]
    #expect(MacKeyboardPolicy.target(from: nil, move: .down, in: list)?.id == "a")
    #expect(MacKeyboardPolicy.target(from: nil, move: .up, in: list)?.id == "c")
    #expect(MacKeyboardPolicy.target(from: "a", move: .down, in: list)?.id == "b")
    #expect(MacKeyboardPolicy.target(from: "b", move: .up, in: list)?.id == "a")
    #expect(MacKeyboardPolicy.target(from: "c", move: .down, in: list) == nil)
    #expect(MacKeyboardPolicy.target(from: "a", move: .up, in: list) == nil)
    #expect(MacKeyboardPolicy.target(from: "b", move: .first, in: list)?.id == "a")
    #expect(MacKeyboardPolicy.target(from: "b", move: .last, in: list)?.id == "c")
    #expect(MacKeyboardPolicy.target(from: "a", move: .first, in: list) == nil)
    // ←/→ belong to grids only.
    #expect(MacKeyboardPolicy.target(from: "b", move: .right, in: list) == nil)
    #expect(MacKeyboardPolicy.target(from: "b", move: .left, in: list) == nil)
    // A stale id (row gone after a filter) starts over like no highlight.
    #expect(MacKeyboardPolicy.target(from: "gone", move: .down, in: list)?.id == "a")
    #expect(MacKeyboardPolicy.target(from: nil, move: .down, in: []) == nil)
}

/// Groups (Rivals sections, Leaderboards cards) chain in order; empty groups are skipped.
@Test func macKeyboardCrossesGroups() {
    let groups = [group(["a1", "a2"]), group([]), group(["b1"])]
    #expect(MacKeyboardPolicy.target(from: "a2", move: .down, in: groups)?.id == "b1")
    #expect(MacKeyboardPolicy.target(from: "b1", move: .up, in: groups)?.id == "a2")
}

/// A 4-column grid of 10: ↓/↑ move one grid row, a short last row lands on its last
/// item, the last row moves on to the next group, ←/→ step one item.
@Test func macKeyboardGridMoves() {
    let ids = (0..<10).map { "g\($0)" }
    let groups = [group(["top"]), group(ids, columns: 4), group(["after"])]
    #expect(MacKeyboardPolicy.target(from: "g1", move: .down, in: groups)?.id == "g5")
    #expect(MacKeyboardPolicy.target(from: "g6", move: .down, in: groups)?.id == "g9")
    #expect(MacKeyboardPolicy.target(from: "g9", move: .down, in: groups)?.id == "after")
    #expect(MacKeyboardPolicy.target(from: "g8", move: .down, in: groups)?.id == "after")
    #expect(MacKeyboardPolicy.target(from: "g5", move: .up, in: groups)?.id == "g1")
    #expect(MacKeyboardPolicy.target(from: "g2", move: .up, in: groups)?.id == "top")
    #expect(MacKeyboardPolicy.target(from: "g3", move: .right, in: groups)?.id == "g4")
    #expect(MacKeyboardPolicy.target(from: "g4", move: .left, in: groups)?.id == "g3")
}

/// Adaptive grid columns follow `GridItem(.adaptive(minimum: 210), spacing: 12)`.
@Test func macKeyboardAdaptiveColumns() {
    #expect(MacKeyboardPolicy.adaptiveColumns(width: 0, minimum: 210, spacing: 12) == 1)
    #expect(MacKeyboardPolicy.adaptiveColumns(width: 209, minimum: 210, spacing: 12) == 1)
    #expect(MacKeyboardPolicy.adaptiveColumns(width: 432, minimum: 210, spacing: 12) == 2)
    #expect(MacKeyboardPolicy.adaptiveColumns(width: 876, minimum: 210, spacing: 12) == 4)
}

// MARK: - Page rows

/// Item Shop: Return does what a click does (list row → Song Detail when the catalogue
/// has the song, otherwise and in the grid → the official Item Shop).
@MainActor
@Test func shopKeyRowsFollowClickActions() {
    let offers = [offer("alpha"), offer("bravo")]
    let catalogue = ["alpha": Song(shopOffer: offers[0])]
    let list = ShopScreen.keyRows(offers, catalogue: catalogue, grid: false)
    #expect(list.map(\.id) == ["alpha", "bravo"])
    #expect(list[0].route == .songDetail(catalogue["alpha"]!))
    #expect(list[1].action == .url(offers[1].shopUrl))
    let grid = ShopScreen.keyRows(offers, catalogue: catalogue, grid: true)
    #expect(grid.allSatisfy { $0.route == nil })
}

/// Rankings rows skip anonymous entries and keep ids unique per card.
@MainActor
@Test func rankingKeyRowsSkipAnonymousAndPrefix() throws {
    let entries = [try rankingRow("abc", rank: 1), try rankingRow("", rank: 2), try rankingRow("def", rank: 3)]
    let rows = AccountRankingRow.keyRows(entries, prefix: "Solo_Guitar|", container: "instrument:Solo_Guitar")
    #expect(rows.map(\.id) == ["Solo_Guitar|abc", "Solo_Guitar|def"])
    #expect(rows.allSatisfy { $0.container == "instrument:Solo_Guitar" })
    #expect(rows[0].route == .player(accountId: "abc", displayName: "Player 1"))
}

// MARK: - Menus

/// Next/Previous Section step through the page's sections and stop at the ends.
@Test func macQuickLinksNeighbors() {
    let ids = ["a", "b", "c"]
    #expect(MacQuickLinksCommand.neighbor(of: nil, in: ids, offset: 1) == "a")
    #expect(MacQuickLinksCommand.neighbor(of: nil, in: ids, offset: -1) == nil)
    #expect(MacQuickLinksCommand.neighbor(of: "a", in: ids, offset: 1) == "b")
    #expect(MacQuickLinksCommand.neighbor(of: "c", in: ids, offset: 1) == nil)
    #expect(MacQuickLinksCommand.neighbor(of: "b", in: ids, offset: -1) == "a")
    #expect(MacQuickLinksCommand.neighbor(of: "a", in: [], offset: 1) == nil)
}

/// View › Rank By lists every account metric when no rankings page is in front.
@Test func macRankByAccountOptions() {
    #expect(MacRankByCommands.accountOptions.map(\.id) == RankingMetric.allCases.map(\.rawValue))
    #expect(MacRankByCommands.accountOptions.first?.label == RankingMetric.adjusted.label)
}

// MARK: - Animation gate

/// Continuous decoration runs only in an active scene whose window can be seen.
@Test func animationActivityNeedsActiveVisibleScene() {
    #expect(AnimationActivity.sceneActive(.active, windowVisible: true))
    #expect(!AnimationActivity.sceneActive(.active, windowVisible: false))
    #expect(!AnimationActivity.sceneActive(.inactive, windowVisible: true))
    #expect(!AnimationActivity.sceneActive(.background, windowVisible: true))
}

#if os(macOS)
// MARK: - Navigator

/// Groups sort by order, then registration; removing the last group clears `hasRows`.
@MainActor
@Test func macKeyboardNavigatorOrdersGroups() {
    let navigator = MacKeyboardNavigator()
    let late = UUID(), early = UUID(), tie = UUID()
    navigator.set(group(["c1"], order: 5), token: late)
    navigator.set(group(["a1"], order: 0), token: early)
    navigator.set(group(["c2"], order: 5), token: tie)
    #expect(navigator.hasRows)
    #expect(navigator.orderedGroups.flatMap(\.rows).map(\.id) == ["a1", "c1", "c2"])
    // Replacing a group keeps its place among equal orders.
    navigator.set(group(["c1", "c1b"], order: 5), token: late)
    #expect(navigator.orderedGroups.flatMap(\.rows).map(\.id) == ["a1", "c1", "c1b", "c2"])
    #expect(navigator.row(id: "c2")?.id == "c2")
    for token in [late, early, tie] { navigator.remove(token: token) }
    #expect(!navigator.hasRows)
}

/// The split's selection maps back to its row; scroll and focus requests count up.
@MainActor
@Test func macKeyboardNavigatorFindsRouteAndRequests() {
    let navigator = MacKeyboardNavigator()
    let route = AppRoute.player(accountId: "abc", displayName: "Player")
    navigator.set(MacKeyRowGroup(order: 0, rows: [MacKeyRow(id: "abc", action: .route(route))]), token: UUID())
    #expect(navigator.row(for: route)?.id == "abc")
    #expect(navigator.row(for: .player(accountId: "zzz", displayName: nil)) == nil)
    navigator.scroll(to: navigator.row(id: "abc")!)
    navigator.scroll(to: navigator.row(id: "abc")!)
    #expect(navigator.scrollTarget?.serial == 2)
    navigator.requestFocus()
    #expect(navigator.focusRequest == 1)
}

// MARK: - Debug driver

/// `key:` and `minimize`/`restore` parse; unknown keys are rejected.
@Test func macDebugKeyCommandsParse() {
    #expect(MacDebugCommand("key:down") == .key("down", modifiers: ""))
    #expect(MacDebugCommand("key:j:cmd") == .key("j", modifiers: "cmd"))
    #expect(MacDebugCommand("key:launch") == nil)
    #expect(MacDebugCommand("minimize") == .minimize)
    #expect(MacDebugCommand("restore") == .restore)
    #expect(MacDebugHooks.keyEvent(named: "return")?.keyCode == 36)
    #expect(MacDebugHooks.modifierFlags("opt+cmd") == [.option, .command])
}
#endif

#if os(macOS)
// MARK: - Hosted key handling

@MainActor
private final class MacKeyPushRecorder {
    var pushed: [AppRoute] = []
    var selected: [AppRoute] = []
}

/// Three rows offering player routes, inside the column modifier.
private struct MacKeyProbe: View {
    let recorder: MacKeyPushRecorder
    /// Split mode: arrows select into the detail column instead of highlighting.
    var split = false
    let ids = ["one", "two", "three"]

    var body: some View {
        VStack {
            ForEach(ids, id: \.self) { id in
                Text("Row \(id)").frame(maxWidth: .infinity, minHeight: 40).macKeyboardRow(id)
            }
        }
        .macKeyboardRows(ids.map { MacKeyRow(id: $0, action: .route(.player(accountId: $0, displayName: nil))) })
        .modifier(MacKeyboardNavigation(
            selection: nil,
            select: split ? ListDetailSelectAction(section: .leaderboards) { recorder.selected.append($0) } : nil,
            push: { recorder.pushed.append($0) }, isTop: true
        ))
    }
}

/// Deliver a key press through the window, as AppKit does.
@MainActor
private func sendKey(_ name: String, to window: NSWindow) {
    guard let key = MacDebugHooks.keyEvent(named: name) else { return }
    let flags: NSEvent.ModifierFlags = key.keyCode >= 115 ? [.function, .numericPad] : []
    for type in [NSEvent.EventType.keyDown, .keyUp] {
        if let event = NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: key.characters,
            charactersIgnoringModifiers: key.characters, isARepeat: false, keyCode: key.keyCode
        ) {
            window.sendEvent(event)
        }
    }
}

/// The column takes focus when its rows arrive; ↓ ↓ highlights the second row and
/// Return pushes its route (one-column arrangement).
@MainActor
@Test func macKeyboardArrowsHighlightAndReturnPushes() async throws {
    let recorder = MacKeyPushRecorder()
    let size = CGSize(width: 400, height: 240)
    let host = NSHostingView(rootView: MacKeyProbe(recorder: recorder))
    let window = NSWindow(
        contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
        styleMask: [.titled], backing: .buffered, defer: false
    )
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    _ = try await nativeHostedSettle(host)
    sendKey("down", to: window)
    sendKey("down", to: window)
    _ = try await nativeHostedSettle(host)
    sendKey("return", to: window)
    _ = try await nativeHostedSettle(host) { !recorder.pushed.isEmpty }
    #expect(recorder.pushed == [.player(accountId: "two", displayName: nil)])
    #expect(recorder.selected.isEmpty)
    withExtendedLifetime(window) {}
}

/// In a split's list column every arrow selects (the detail follows) and nothing pushes.
@MainActor
@Test func macKeyboardArrowsSelectInSplit() async throws {
    let recorder = MacKeyPushRecorder()
    let host = NSHostingView(rootView: MacKeyProbe(recorder: recorder, split: true))
    let window = NSWindow(
        contentRect: NSRect(x: -10_000, y: -10_000, width: 400, height: 240),
        styleMask: [.titled], backing: .buffered, defer: false
    )
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    _ = try await nativeHostedSettle(host)
    sendKey("down", to: window)
    sendKey("end", to: window)
    _ = try await nativeHostedSettle(host) { recorder.selected.count == 2 }
    #expect(recorder.selected == [
        .player(accountId: "one", displayName: nil), .player(accountId: "three", displayName: nil),
    ])
    #expect(recorder.pushed.isEmpty)
    withExtendedLifetime(window) {}
}
#endif
