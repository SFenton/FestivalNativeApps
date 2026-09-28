import CoreGraphics
import Foundation
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Song Detail pinned title (gap #6)

/// The nav-bar identity appears only once the hero title is under the bars.
@Test func pinnedTitleWaitsForHeroTitleToScrollUnderBars() {
    // Before layout: never show the pinned title.
    #expect(!SongDetailPinnedTitlePolicy.isHeroHidden(titleMaxY: .infinity))
    #expect(!SongDetailPinnedTitlePolicy.isHeroHidden(titleMaxY: .nan))
    // At rest the title sits below the bar (measured maxY 49 in `.scrollView` space).
    #expect(!SongDetailPinnedTitlePolicy.isHeroHidden(titleMaxY: 49))
    // Exactly at, then past, the bar's lower edge.
    #expect(SongDetailPinnedTitlePolicy.isHeroHidden(titleMaxY: 0))
    #expect(SongDetailPinnedTitlePolicy.isHeroHidden(titleMaxY: -615))
}

// MARK: - Gold full-combo badge (gap #7)

/// The FC badge shear matches CSS `skewX(-8deg)` pivoting on the pill's middle.
@Test func goldSkewLeansTopRightAboutTheCentre() {
    let height: CGFloat = 24
    let transform = SongLeaderboardEntryRow.goldSkew(height: height)
    let shear = tan(8 * CGFloat.pi / 180)
    let top = CGPoint(x: 10, y: 0).applying(transform)
    let middle = CGPoint(x: 10, y: height / 2).applying(transform)
    let bottom = CGPoint(x: 10, y: height).applying(transform)
    #expect(abs(middle.x - 10) < 0.0001)
    #expect(abs(top.x - (10 + shear * height / 2)) < 0.0001)
    #expect(abs(bottom.x - (10 - shear * height / 2)) < 0.0001)
    #expect(top.y == 0 && bottom.y == height)
}

// MARK: - Shop first-screen artwork (gap #17)

/// Decode synthetic offers through the real wire model.
///
/// - Parameter art: One optional `albumArt` value per offer, in display order.
/// - Returns: Offers with fixture IDs and an official jam-track URL.
/// - Throws: A decoding failure for malformed synthetic JSON.
private func offers(_ art: [String?]) throws -> [ShopSong] {
    let rows = art.enumerated().map { index, raw -> String in
        let artJSON = raw.map { "\"\($0)\"" } ?? "null"
        return """
        {"songId":"fixture-\(index)","title":"Song \(index)","artist":"Artist",
         "year":2020,"albumArt":\(artJSON),
         "shopUrl":"https://www.fortnite.com/item-shop/jam-tracks/fixture-\(index)",
         "leavingTomorrow":false,"isNew":false}
        """
    }
    return try JSONDecoder().decode(
        [ShopSong].self, from: Data("[\(rows.joined(separator: ","))]".utf8)
    )
}

/// Prime only distinct, present covers, in display order, up to one screen.
@Test func shopPrimeSkipsBlankAndRepeatedArtAndStopsAtLimit() throws {
    let list = try offers(["/a.jpg", nil, "", "/b.jpg", "/a.jpg", "/c.jpg", "/d.jpg"])
    #expect(ShopArtworkPrimePolicy.paths(for: list, limit: 3) == ["/a.jpg", "/b.jpg", "/c.jpg"])
    #expect(ShopArtworkPrimePolicy.paths(for: list).count == 4)
    #expect(ShopArtworkPrimePolicy.paths(for: []).isEmpty)
    #expect(ShopArtworkPrimePolicy.paths(for: list, limit: 0).isEmpty)
}

/// The priming budget is one phone screen and never longer than the Songs gate.
@Test func shopPrimeBudgetIsBounded() {
    #expect(ShopArtworkPrimePolicy.count >= 10 && ShopArtworkPrimePolicy.count <= 16)
    #expect(ShopArtworkPrimePolicy.timeout <= .milliseconds(900))
    // The bag keeps a 44pt target and the row art matches the ~44pt PWA art.
    #expect(ShopRowMetrics.bagSlot >= 44)
    #expect(ShopRowMetrics.art == 44)
}

// MARK: - Song Detail Shop action tone (operator report)

/// Decode one synthetic offer with the given Shop flags.
///
/// - Parameters:
///   - isNew: Upstream New flag.
///   - leaving: Upstream Leaving Tomorrow flag.
/// - Returns: One validated-shape offer.
/// - Throws: A decoding failure for malformed synthetic JSON.
private func offer(isNew: Bool, leaving: Bool) throws -> ShopSong {
    try JSONDecoder().decode(ShopSong.self, from: Data("""
    {"songId":"fixture-tone","title":"Tone","artist":"Artist","year":null,
     "albumArt":null,"shopUrl":"https://www.fortnite.com/item-shop/jam-tracks/fixture-tone",
     "leavingTomorrow":\(leaving),"isNew":\(isNew)}
    """.utf8))
}

/// Green in shop, gold new, red leaving (leaving wins); none when hidden/disabled/absent.
@Test func shopActionToneFollowsWebHighlightRules() throws {
    let plain = try offer(isNew: false, leaving: false)
    let fresh = try offer(isNew: true, leaving: false)
    let leaving = try offer(isNew: true, leaving: true)
    #expect(ShopStatusTone.tone(for: plain, hidden: false, highlightingDisabled: false) == .inShop)
    #expect(ShopStatusTone.tone(for: fresh, hidden: false, highlightingDisabled: false) == .new)
    #expect(ShopStatusTone.tone(for: leaving, hidden: false, highlightingDisabled: false) == .leaving)
    #expect(ShopStatusTone.tone(for: fresh, hidden: false, highlightingDisabled: true) == nil)
    #expect(ShopStatusTone.tone(for: fresh, hidden: true, highlightingDisabled: false) == nil)
    #expect(ShopStatusTone.tone(for: nil, hidden: false, highlightingDisabled: false) == nil)
    #expect(ShopStatusTone.period == 3)
    #expect(Set([ShopStatusTone.inShop, .new, .leaving].map(\.spokenStatus)).count == 3)
}

// MARK: - Selected-player spotlight row (operator report)

/// Decode one preview row.
///
/// - Parameters:
///   - id: Account ID.
///   - rank: Board rank.
/// - Returns: A synthetic leaderboard row.
private func row(_ id: String, rank: Int) -> LeaderboardEntry {
    LeaderboardEntry(
        accountId: id, displayName: id, score: 1_000 - rank, rank: rank,
        accuracy: nil, isFullCombo: nil, stars: nil, season: nil, difficulty: nil
    )
}

/// Decode a selected-player score with an optional rank.
///
/// - Parameters:
///   - rank: Rank on the chart, or nil when unranked.
///   - score: Score value.
/// - Returns: Synthetic score-index row.
/// - Throws: A decoding failure for malformed synthetic JSON.
private func playerScore(rank: Int?, score: Int = 500) throws -> PlayerScore {
    let rankJSON = rank.map(String.init) ?? "null"
    return try JSONDecoder().decode(PlayerScore.self, from: Data("""
    {"si":"fixture-pulse","ins":"01","sc":\(score),"rk":\(rankJSON)}
    """.utf8))
}

/// The player's own row follows the top ten only when they are ranked outside it.
@Test func spotlightRowOnlyForRankedPlayersOutsideTopTen() throws {
    let top = (1...10).map { row("p\($0)", rank: $0) }
    let me = try JSONDecoder().decode(
        SelectedPlayerIdentity.self, from: Data(#"{"accountId":"ME","displayName":"Me"}"#.utf8)
    )
    let footer = SongPreviewSpotlightPolicy.footerEntry(
        selected: me, score: try playerScore(rank: 42), displayed: top
    )
    #expect(footer?.rank == 42 && footer?.accountId == "ME" && footer?.displayName == "Me")
    // Already in the top ten (case-insensitive): highlighted there, no extra row.
    let withMe = top + [row("me", rank: 11)]
    #expect(SongPreviewSpotlightPolicy.footerEntry(
        selected: me, score: try playerScore(rank: 11), displayed: withMe
    ) == nil)
    #expect(SongPreviewSpotlightPolicy.isSelected(row("me", rank: 3), selected: me))
    #expect(!SongPreviewSpotlightPolicy.isSelected(row("p1", rank: 1), selected: me))
    // No selection, unranked or zero score: nothing appended.
    #expect(SongPreviewSpotlightPolicy.footerEntry(
        selected: nil, score: try playerScore(rank: 42), displayed: top
    ) == nil)
    #expect(SongPreviewSpotlightPolicy.footerEntry(
        selected: me, score: try playerScore(rank: nil), displayed: top
    ) == nil)
    #expect(SongPreviewSpotlightPolicy.footerEntry(
        selected: me, score: try playerScore(rank: 42, score: 0), displayed: top
    ) == nil)
}
