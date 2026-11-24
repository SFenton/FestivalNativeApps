import Testing
@testable import FestivalUI

/// The words on a hub rival row, shared by the SwiftUI row and the UIKit port.
@Suite("Rival row copy")
struct RivalRowCopyTests {
    @Test("The ahead pill shows behindCount and the behind pill aheadCount (web RivalRow pairing)")
    func pillsAreCrossed() {
        let copy = RivalRowCopy(name: "Rival", behindCount: 12, aheadCount: 3)
        #expect(copy.aheadPill == "12 ahead")
        #expect(copy.behindPill == "3 behind")
    }

    @Test("The spoken label names the rival and both counts")
    func spokenLabel() {
        let copy = RivalRowCopy(name: "Rival", behindCount: 12, aheadCount: 3)
        #expect(copy.accessibilityLabel == "Rival, 12 songs ahead, 3 songs behind")
    }

    @Test("A rival without a name reads Unknown Player")
    func unknownPlayer() {
        #expect(RivalRowCopy(name: nil, behindCount: 0, aheadCount: 0).name == "Unknown Player")
    }

    @Test("Rivalry section titles resolve without the main actor")
    func rivalryTitle() {
        #expect(RivalryScreen.title(for: "closest_battles") == "Closest Battles")
        #expect(RivalryScreen.title(for: "nope") == "Rivalry")
    }
}
