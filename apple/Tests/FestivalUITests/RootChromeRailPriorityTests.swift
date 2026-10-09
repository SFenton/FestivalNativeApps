import SwiftUI
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

    @Test("Quick Links yields the folded rail to the bell and profile (issue #92)")
    func quickLinksYieldsToAccountItems() {
        #expect(!RootChromeRailItem.quickLinks.staysVisibleAheadOfOthers)
    }

    @Test("A page's prominent primary action stays in the rail; a plain one overflows first (issue #351)")
    func primaryPageActionStaysVisible() {
        #expect(RootChromeRailItem.primaryPageAction.staysVisibleAheadOfOthers)
        #expect(!RootChromeRailItem.pageAction.staysVisibleAheadOfOthers)
    }

    @Test("Player Select and Switch rank as the prominent primary rail action (issue #351)")
    func identityRailItemIsPrimary() {
        for identity in [ProfileIdentityAction.select, .switchTo] {
            let item = VerticalBarActionItem(
                title: identity.title, systemImage: identity.systemImage,
                identifier: identity.railAccessibilityIdentifier,
                prominentFill: identity.prominentFill, action: {}
            )
            #expect(item.railItem == .primaryPageAction)
        }
        let plain = VerticalBarActionItem(title: "Action", systemImage: "star", identifier: "x", action: {})
        #expect(plain.railItem == .pageAction)
    }

    @Test("Every rail item resolves to a ranking (no silent gaps as cases are added)")
    func everyCaseResolves() {
        for item in RootChromeRailItem.allCases {
            _ = item.staysVisibleAheadOfOthers
        }
        #expect(RootChromeRailItem.allCases.count == 6)
    }
}

// MARK: - Bar item spoken state (#432)

/// The iPhone Duo vertical bar drops a toolbar item's accessibility value, so a page
/// tool's state joins its label there; every other bar keeps label and value apart.
/// The folded-Duo journey `SongsFilterAccessibilityJourneyTests` checks the rendered rail.
@Suite("Bar item spoken state")
struct BarItemSpokenStateTests {
    @Test("Horizontal bars, the tab-bar accessory and the Mac sidebar keep a separate value")
    func horizontalChromeKeepsValue() {
        for chrome in [DeviceLayout.SectionChrome.tabBar, .sidebar] {
            let spoken = BarItemSpokenState.resolve(label: "Filter Songs", value: "No filters", chrome: chrome)
            #expect(spoken.label == "Filter Songs")
            #expect(spoken.value == "No filters")
        }
    }

    @Test("The vertical bar reads the state in the label, on either edge")
    func verticalBarJoinsValueToLabel() {
        for edge in [HorizontalEdge.leading, .trailing] {
            let spoken = BarItemSpokenState.resolve(
                label: "Filter Songs", value: "Year filter, Duration filter", chrome: .verticalBar(edge)
            )
            #expect(spoken.label == "Filter Songs, Year filter, Duration filter")
            #expect(spoken.value.isEmpty)
        }
    }

    @Test("A tool with no state keeps its bare name in the vertical bar")
    func emptyValueKeepsLabel() {
        let spoken = BarItemSpokenState.resolve(label: "Quick Links", value: "", chrome: .verticalBar(.trailing))
        #expect(spoken.label == "Quick Links")
        #expect(spoken.value.isEmpty)
    }
}
