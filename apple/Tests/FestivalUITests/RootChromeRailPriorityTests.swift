import Testing
@testable import FestivalUI

// MARK: - Rail overflow ranking (operator decision, 2026-09-28)

/// Pins `RootChromeRailItem`'s ranking so a future edit to `RootChrome.swift`
/// can't silently flip which item overflows first in the folded iPhone Duo
/// vertical bar. `FestivalRootChrome`/`FestivalRootTrailingItems` apply this
/// enum as the real `visibilityPriority`, so this test is exercising the same
/// switch the shell renders from, not a separate description of it.
///
/// The rendered result (bell + profile visible, hamburger under "…") is native
/// system layout that needs the device/simulator to see end to end — captured
/// via `ios_sim.py drive --pose folded --device duo` in
/// `.agents/design/apple/duo.md`'s W1/W3 capture log — but the *ranking* itself
/// is pure and belongs in a fast unit test.
@Suite("Root chrome rail overflow ranking")
struct RootChromeRailPriorityTests {
    @Test("Bell and profile stay visible ahead of the drawer")
    func bellAndProfileOutrankDrawer() {
        #expect(RootChromeRailItem.bell.staysVisibleAheadOfOthers)
        #expect(RootChromeRailItem.profile.staysVisibleAheadOfOthers)
        #expect(!RootChromeRailItem.drawer.staysVisibleAheadOfOthers)
    }

    @Test("Every rail item resolves to a ranking (no silent gaps as cases are added)")
    func everyCaseResolves() {
        for item in RootChromeRailItem.allCases {
            _ = item.staysVisibleAheadOfOthers
        }
        #expect(RootChromeRailItem.allCases.count == 3)
    }
}
