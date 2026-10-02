import CoreGraphics
import Testing
@testable import FestivalUI

/// Chips go beside the title only when the row fits artwork, a 180 pt title column,
/// one line of chips and the Shop bag's slot (web desktop row), the same for every row
/// of a list, and never before the row is measured.
@Test func songRowSingleLineNeedsRoomForTitleAndChips() {
    #expect(SongRowLayoutPolicy.chipRowWidth(count: 0) == 0)
    #expect(SongRowLayoutPolicy.chipRowWidth(count: 9) == 338)
    // 104 fixed + 180 title + 338 chips + 28 Shop slot = 650 pt.
    #expect(SongRowLayoutPolicy.fitsSingleLine(width: 650, chipCount: 9))
    #expect(!SongRowLayoutPolicy.fitsSingleLine(width: 649, chipCount: 9))
    // Fewer visible instruments fit a narrower row: 5 chips need 498 pt.
    #expect(SongRowLayoutPolicy.fitsSingleLine(width: 498, chipCount: 5))
    #expect(!SongRowLayoutPolicy.fitsSingleLine(width: 497, chipCount: 5))
    #expect(!SongRowLayoutPolicy.fitsSingleLine(width: 0, chipCount: 9))
    #expect(!SongRowLayoutPolicy.fitsSingleLine(width: 900, chipCount: 0))
}

/// Mac rows tint lightly under the pointer and more while pressed, never at rest
/// (HIG Pointing devices: tint without scale for rows).
@Test func macRowHoverTintRises() {
    #expect(MacRowInteraction.tint(hovered: false, pressed: false) == 0)
    #expect(MacRowInteraction.tint(hovered: true, pressed: false) > 0)
    #expect(MacRowInteraction.tint(hovered: true, pressed: true) > MacRowInteraction.tint(hovered: true, pressed: false))
}
