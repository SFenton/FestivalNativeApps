import CoreGraphics
import Foundation
import SwiftUI
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

/// The sheared FC outline stays inside the badge frame, so it never widens the
/// accessibility frame or the shared score column.
@Test func goldSkewBadgeOutlineFitsItsFrame() {
    let rect = CGRect(x: 10, y: 20, width: 96, height: 24)
    let skewed = GoldSkewBadgeShape(skewed: true).path(in: rect).boundingRect
    #expect(skewed.minX >= rect.minX - 0.01 && skewed.maxX <= rect.maxX + 0.01)
    #expect(skewed.minY >= rect.minY - 0.01 && skewed.maxY <= rect.maxY + 0.01)
    let inset = GoldSkewBadgeShape(skewed: true).inset(by: 1).path(in: rect).boundingRect
    #expect(inset.minX > rect.minX && inset.maxX < rect.maxX)
    let plain = GoldSkewBadgeShape(skewed: false).path(in: rect).boundingRect
    #expect(abs(plain.width - 96) < 0.01)
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
    // The 44pt bag target is centred on its narrower reserved slot and overhangs
    // only into the row spacing, never into the text or the chevron.
    let overhang = (ShopRowMetrics.bagSlot - ShopRowMetrics.bagReserve) / 2
    #expect(overhang <= ShopRowMetrics.spacing)
    #expect(ShopRowMetrics.bagTrailingInset(navigable: true)
        == ShopRowMetrics.rowInset + ShopRowMetrics.chevronWidth + ShopRowMetrics.spacing - overhang)
    #expect(ShopRowMetrics.bagTrailingInset(navigable: false) == ShopRowMetrics.rowInset - overhang)
    #expect(ShopRowMetrics.bagTrailingInset(navigable: false) >= 0)
}

// MARK: - Item Shop rows reuse the Song row (issue #18)

/// An unmatched offer still draws the shared row from its own fields only.
@Test func shopOfferSongCarriesOnlyOfferFields() throws {
    let offer = try offers(["/art.jpg"])[0]
    let song = Song(shopOffer: offer)
    #expect(song.songId == "fixture-0" && song.title == "Song 0" && song.artist == "Artist")
    #expect(song.year == 2020 && song.albumArt == "/art.jpg")
    #expect(song.durationSeconds == nil && song.difficulty == nil && song.maxScores == nil)
    #expect(song.album == nil && song.pathArtifactGenerationId == nil && song.sig == nil)
}

/// A catalogue match draws the catalogue song and opens Detail; a miss is bag-only.
@Test func shopRowPolicyNavigatesOnlyToCatalogueMatches() throws {
    let offer = try offers(["/art.jpg"])[0]
    let catalogueSong = Song(shopOffer: offer)
    let matched = ShopRowPolicy.row(
        for: offer, catalogue: [offer.songId: catalogueSong],
        hidden: false, highlightingDisabled: false, reservesBag: true
    )
    #expect(matched.detailSong == catalogueSong && matched.song == catalogueSong)
    #expect(matched.decoration.navigable && matched.decoration.reservesBag)
    let missing = ShopRowPolicy.row(
        for: offer, catalogue: [:],
        hidden: false, highlightingDisabled: false, reservesBag: false
    )
    #expect(missing.detailSong == nil && missing.song.songId == offer.songId)
    #expect(!missing.decoration.navigable && !missing.decoration.reservesBag)
}

/// Shop rows keep New / Leaving badges and their red/gold pulse; a plain offer and
/// hidden or disabled highlighting show neither (web passes only red/gold flags).
@Test func shopRowDecorationKeepsShopOnlyBadges() throws {
    func decoration(_ offer: ShopSong, hidden: Bool = false, disabled: Bool = false)
        -> SongRowShopOffer {
        ShopRowPolicy.row(
            for: offer, catalogue: [:], hidden: hidden,
            highlightingDisabled: disabled, reservesBag: true
        ).decoration
    }
    let fresh = decoration(try offer(isNew: true, leaving: false))
    #expect(fresh.highlight == .new && fresh.pulseTone == .new)
    let leaving = decoration(try offer(isNew: true, leaving: true))
    #expect(leaving.highlight == .leavingTomorrow && leaving.pulseTone == .leaving)
    let plain = decoration(try offer(isNew: false, leaving: false))
    #expect(plain.highlight == nil && plain.pulseTone == nil)
    let disabled = decoration(try offer(isNew: true, leaving: false), disabled: true)
    #expect(disabled.highlight == nil && disabled.pulseTone == nil)
    let hidden = decoration(try offer(isNew: false, leaving: true), hidden: true)
    #expect(hidden.highlight == nil && hidden.pulseTone == nil)
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

/// Preview rows open profiles like the web `InstrumentCard` links (issue #33): another
/// player's profile, the selected player's Statistics, and the footer row's own page
/// of the full chart; anonymous rows stay inert.
@Test func previewRowsRouteToProfilesLikeTheWeb() throws {
    let song = try JSONDecoder().decode(Song.self, from: Data("""
    {"songId":"fixture-pulse","title":"Fixture Pulse","artist":"Fixture Artist"}
    """.utf8))
    let me = try JSONDecoder().decode(
        SelectedPlayerIdentity.self, from: Data(#"{"accountId":"ME","displayName":"Me"}"#.utf8)
    )
    func route(_ entry: LeaderboardEntry, selected: SelectedPlayerIdentity?, footer: Bool = false)
        -> AppRoute? {
        SongPreviewSpotlightPolicy.route(
            for: entry, selected: selected, song: song, instrument: .lead, isFooter: footer
        )
    }
    let other = row("p1", rank: 1)
    #expect(route(other, selected: me) == .player(accountId: "p1", displayName: "p1"))
    #expect(route(other, selected: nil) == .player(accountId: "p1", displayName: "p1"))
    // Own row in the top ten (case-insensitive) → Statistics, as on the Solo chart.
    #expect(route(row("me", rank: 3), selected: me) == .statistics)
    // Own footer row → the full chart page containing the rank (25 per page), with
    // the row brought into view (issue #307).
    #expect(route(row("ME", rank: 42), selected: me, footer: true)
        == .songLeaderboard(song, .lead, 2, focusSelected: true))
    #expect(route(row("ME", rank: 25), selected: me, footer: true)
        == .songLeaderboard(song, .lead, 1, focusSelected: true))
    // Anonymous rows have no profile.
    #expect(route(row("", rank: 4), selected: me) == nil)
    #expect(SongPreviewSpotlightPolicy.hint(for: .statistics) == "Opens your statistics")
    #expect(SongPreviewSpotlightPolicy.hint(for: .player(accountId: "p1", displayName: nil))
        == "Opens player profile")
    #expect(SongPreviewSpotlightPolicy.hint(for: .songLeaderboard(song, .lead, 2))
        == "Jumps to your position in the full leaderboard")
}

/// The selected band's row appended after a band preview follows the solo spotlight
/// row's rule (issue #307): it opens the full band board at the page containing its
/// rank, focused on that band; every other band row opens its Band page.
@Test func bandPreviewRowsRouteLikeTheSoloSpotlight() throws {
    let song = try JSONDecoder().decode(Song.self, from: Data("""
    {"songId":"fixture-pulse","title":"Fixture Pulse","artist":"Fixture Artist"}
    """.utf8))
    func band(_ id: String, rank: Int) throws -> SongBandLeaderboardEntry {
        try JSONDecoder().decode(SongBandLeaderboardEntry.self, from: Data("""
        {"bandId":"\(id)","bandType":"Band_Duets","teamKey":"\(id)-key","comboId":null,
         "members":[{"accountId":"a","displayName":"Ann","instruments":["Solo_Guitar"]},
                    {"accountId":"b","displayName":"Bo","instruments":["Solo_Drums"]}],
         "score":1000,"rank":\(rank),"accuracy":990000,"isFullCombo":false,"stars":5,
         "season":9,"difficulty":3,"percentile":0.5,"endTime":null}
        """.utf8))
    }
    let mine = try band("mine", rank: 57)
    let appended = SongBandRowNavigation.previewRoute(
        for: mine, song: song, bandType: .duets, isAppended: true
    )
    #expect(appended == .songBandLeaderboard(
        song, bandType: "Band_Duets", page: 3, focus: SongBandRowFocus(mine)
    ))
    #expect(SongBandRowNavigation.hint(for: appended)
        == "Jumps to your band's position in the full leaderboard")
    // A top-ten row (the selected band's highlighted one included) opens its page.
    let other = try band("other", rank: 2)
    let bandPage = AppRoute.band(
        bandId: "other", name: "Ann + Bo", bandType: "Band_Duets", teamKey: "other-key"
    )
    #expect(SongBandRowNavigation.previewRoute(
        for: other, song: song, bandType: .duets, isAppended: false
    ) == bandPage)
    #expect(SongBandRowNavigation.bandRoute(other) == bandPage)
    #expect(SongBandRowNavigation.hint(for: bandPage) == "Opens band")
    // The full board's footer follows the Solo footer: jump while off the shown page,
    // open the band once its row is on screen.
    let offPage = SongBandRowNavigation.footerAction(for: mine, pageEntries: [other])
    #expect(offPage == .jump(page: 3))
    #expect(SongBandRowNavigation.footerHint(for: offPage) == "Jumps to your band's position")
    let onPage = SongBandRowNavigation.footerAction(for: mine, pageEntries: [other, mine])
    #expect(onPage == .openProfile)
    #expect(SongBandRowNavigation.footerHint(for: onPage) == "Opens band")
    // Without a usable rank the appended row falls back to the Band page.
    #expect(SongBandRowNavigation.previewRoute(
        for: try band("mine", rank: 0), song: song, bandType: .duets, isAppended: true
    ) == SongBandRowNavigation.bandRoute(try band("mine", rank: 0)))
}

/// The Shop action's breathe really cycles (0 → 1 → 0 over 3 s) and holds a static
/// tint whenever motion is off.
@Test func shopBreatheAnimatesUnlessMotionIsOff() {
    let low = ShopStatusBreathe.intensity(at: 0, animating: true)
    let peak = ShopStatusBreathe.intensity(at: 1.5, animating: true)
    let back = ShopStatusBreathe.intensity(at: 3, animating: true)
    let quarter = ShopStatusBreathe.intensity(at: 0.75, animating: true)
    #expect(abs(low) < 0.0001 && abs(peak - 1) < 0.0001 && abs(back) < 0.0001)
    #expect(abs(quarter - 0.5) < 0.0001)
    // The level toggles over time rather than sitting still.
    let samples = stride(from: 0.0, to: 3.0, by: 0.25).map {
        ShopStatusBreathe.intensity(at: $0, animating: true)
    }
    #expect(Set(samples.map { ($0 * 100).rounded() }).count > 5)
    // Static tint (full status colour) when not animating.
    #expect(ShopStatusBreathe.intensity(at: 0.4, animating: false) == 1)
    #expect(ShopStatusBreathe.animates(reduceMotion: false, sceneActive: true, still: false))
    #expect(!ShopStatusBreathe.animates(reduceMotion: true, sceneActive: true, still: false))
    #expect(!ShopStatusBreathe.animates(reduceMotion: false, sceneActive: false, still: false))
    #expect(!ShopStatusBreathe.animates(reduceMotion: false, sceneActive: true, still: true))
}

// MARK: - Shop action in the iPhone Duo vertical bar

/// The breathing Shop fill is a custom view, which the Duo vertical bar dropped from
/// both the rail and its overflow; the rail gets a titled symbol instead.
@Suite("Song Detail Shop action style")
struct SongDetailShopActionStyleTests {
    @Test("Horizontal bars keep the breathing status fill")
    func horizontalBarsBreathe() {
        for chrome in [DeviceLayout.SectionChrome.tabBar, .sidebar] {
            #expect(SongDetailShopActionStyle.resolve(tone: .new, chrome: chrome) == .breathing(.new))
            #expect(SongDetailShopActionStyle.resolve(tone: nil, chrome: chrome)
                == .titled(spokenLabel: "Item Shop"))
        }
    }

    @Test("The vertical bar always uses a titled symbol and keeps the spoken status")
    func verticalBarIsTitled() {
        for edge in [HorizontalEdge.leading, .trailing] {
            let chrome = DeviceLayout.SectionChrome.verticalBar(edge)
            #expect(SongDetailShopActionStyle.resolve(tone: .leaving, chrome: chrome)
                == .titled(spokenLabel: "Item Shop, Leaving the Item Shop tomorrow"))
            #expect(SongDetailShopActionStyle.resolve(tone: nil, chrome: chrome)
                == .titled(spokenLabel: "Item Shop"))
        }
    }
}
