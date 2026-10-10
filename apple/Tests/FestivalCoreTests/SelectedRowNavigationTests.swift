import Foundation
import Testing
@testable import FestivalCore

// MARK: - Selected-row action (issue #307)

/// A full board's footer opens the profile while its row is visible and otherwise
/// jumps to the page that contains it, for players and bands alike.
@Test func selectedFooterJumpsOffPageAndOpensProfileOnPage() {
    #expect(SelectedRowAction.footer(rank: 57, isVisible: false, pageSize: 25) == .jump(page: 3))
    #expect(SelectedRowAction.footer(rank: 25, isVisible: false, pageSize: 25) == .jump(page: 1))
    #expect(SelectedRowAction.footer(rank: 26, isVisible: false, pageSize: 25) == .jump(page: 2))
    #expect(SelectedRowAction.footer(rank: 57, isVisible: true, pageSize: 25) == .openProfile)
    // No usable rank: nothing to jump to.
    #expect(SelectedRowAction.footer(rank: 0, isVisible: false, pageSize: 25) == .openProfile)
    #expect(SelectedRowAction.footer(rank: -3, isVisible: false, pageSize: 25) == .openProfile)
}

/// Song Detail's appended selected row jumps; a selected row inside the top rows opens
/// the profile.
@Test func selectedPreviewRowJumpsOnlyWhenAppended() {
    #expect(SelectedRowAction.preview(rank: 14, isAppended: true, pageSize: 25) == .jump(page: 1))
    #expect(SelectedRowAction.preview(rank: 1_234, isAppended: true, pageSize: 25) == .jump(page: 50))
    #expect(SelectedRowAction.preview(rank: 3, isAppended: false, pageSize: 25) == .openProfile)
    #expect(SelectedRowAction.preview(rank: 0, isAppended: true, pageSize: 25) == .openProfile)
}

/// Footer labels name the rank and the destination for both boards and both actions,
/// so VoiceOver says where the footer goes (issue #307).
@Test func selectedFooterLabelsNameTheDestination() {
    let jump = SelectedRowAction.jump(page: 2)
    let open = SelectedRowAction.openProfile
    #expect(jump.footerLabel(for: .player, rank: 29) == "Your rank, 29th. Jump to your position.")
    #expect(open.footerLabel(for: .player, rank: 3) == "Your rank, 3rd. Open your statistics.")
    #expect(jump.footerLabel(for: .band, rank: 29)
        == "Your band's rank, 29th. Jump to your band's position.")
    #expect(open.footerLabel(for: .band, rank: 1) == "Your band's rank, 1st. Open band.")
}

// MARK: - Band row focus

/// A focus matches the same `bandId`, or the same size and roster key, like the web's
/// `isSameSongBandEntry`; empty identifiers never match.
@Test func bandRowFocusMatchesSameBand() throws {
    func entry(bandId: String, bandType: String = "Band_Duets", teamKey: String) throws
        -> SongBandLeaderboardEntry {
        try JSONDecoder().decode(SongBandLeaderboardEntry.self, from: Data("""
        {"bandId":"\(bandId)","bandType":"\(bandType)","teamKey":"\(teamKey)","comboId":null,
         "members":[],"score":1,"rank":14,"accuracy":990000,"isFullCombo":false,"stars":5,
         "season":9,"difficulty":3,"percentile":0.5,"endTime":null}
        """.utf8))
    }
    let mine = try entry(bandId: "band-a", teamKey: "a:b")
    let focus = SongBandRowFocus(mine)
    #expect(focus == SongBandRowFocus(bandId: "band-a", bandType: "Band_Duets", teamKey: "a:b"))
    #expect(focus.matches(mine))
    #expect(focus.matches(try entry(bandId: "band-a", teamKey: "other")))
    #expect(focus.matches(try entry(bandId: "", teamKey: "a:b")))
    #expect(!focus.matches(try entry(bandId: "band-b", teamKey: "c:d")))
    // The same roster in another size is another band.
    #expect(!focus.matches(try entry(bandId: "band-c", bandType: "Band_Trios", teamKey: "a:b")))
    let anonymous = SongBandRowFocus(bandId: "", bandType: "Band_Duets", teamKey: "")
    #expect(!anonymous.matches(try entry(bandId: "", teamKey: "")))
}

// MARK: - Pinned placement (R11, issue #386)

/// The selected row stays pinned at every standard text size, however tall it is.
@Test func selectedRowStaysPinnedAtStandardSizes() {
    #expect(SelectedRowPinning.pins(isAccessibilitySize: false, rowHeight: 545, boardHeight: 690))
    #expect(SelectedRowPinning.pins(isAccessibilitySize: false, rowHeight: 110, boardHeight: 300))
}

/// At accessibility sizes a row covering more than a third of the board scrolls with the
/// rows instead (the iPhone band row measured 545 of 690 pt at the largest size).
@Test func selectedRowScrollsWhenItWouldCoverTheBoardAtAccessibilitySizes() {
    #expect(!SelectedRowPinning.pins(isAccessibilitySize: true, rowHeight: 545, boardHeight: 690))
    #expect(!SelectedRowPinning.pins(isAccessibilitySize: true, rowHeight: 231, boardHeight: 690))
    #expect(SelectedRowPinning.pins(isAccessibilitySize: true, rowHeight: 230, boardHeight: 690))
    #expect(SelectedRowPinning.pins(isAccessibilitySize: true, rowHeight: 164, boardHeight: 900))
}

/// Before either height is measured the row keeps its pinned place, so a board never
/// starts with its row in the list and then moves it.
@Test func selectedRowPinsUntilMeasured() {
    #expect(SelectedRowPinning.pins(isAccessibilitySize: true, rowHeight: 0, boardHeight: 690))
    #expect(SelectedRowPinning.pins(isAccessibilitySize: true, rowHeight: 545, boardHeight: 0))
}
