import Testing
import FestivalCore
@testable import FestivalUI

/// The Paths instrument selector wraps only between words, and on folded iPhone Duo shows
/// only its icon with the instrument named in the title (issue #360).
struct SongPathsSelectorTests {
    @Test func longestWordSetsTheUnbrokenWidth() {
        #expect(SongPathsSheet.longestWord(in: "Lead") == "Lead")
        #expect(SongPathsSheet.longestWord(in: "Pro Drums + Cymbals") == "Cymbals")
        #expect(SongPathsSheet.longestWord(in: "Karaoke") == "Karaoke")
        #expect(SongPathsSheet.longestWord(in: "") == "")
    }

    @Test func foldedDuoShowsTheIconOnlyAndNamesTheInstrumentInTheTitle() {
        #expect(!SongPathsSheet.showsInstrumentName(pose: .folded))
        #expect(SongPathsSheet.title(for: .lead, pose: .folded) == "Paths · Lead")
        #expect(SongPathsSheet.title(for: .proDrums, pose: .folded) == "Paths · \(Instrument.proDrums.label)")
    }

    @Test(arguments: [DeviceLayout.Pose.standard, .unfolded, .partiallyFolded])
    func otherPosesKeepTheNamedSelectorAndPlainTitle(pose: DeviceLayout.Pose) {
        #expect(SongPathsSheet.showsInstrumentName(pose: pose))
        #expect(SongPathsSheet.title(for: .lead, pose: pose) == "Paths")
        #expect(SongPathsSheet.title(for: .bass, pose: pose) == "Paths")
    }
}
