import Testing
@testable import FestivalUI

/// The Paths instrument selector wraps only between words (iPhone Duo folded sheet).
struct SongPathsSelectorTests {
    @Test func longestWordSetsTheUnbrokenWidth() {
        #expect(SongPathsSheet.longestWord(in: "Lead") == "Lead")
        #expect(SongPathsSheet.longestWord(in: "Pro Drums + Cymbals") == "Cymbals")
        #expect(SongPathsSheet.longestWord(in: "Karaoke") == "Karaoke")
        #expect(SongPathsSheet.longestWord(in: "") == "")
    }
}
