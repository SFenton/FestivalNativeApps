import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - Trailing glass groups (issue #14)

/// Pins how the shared trailing items split into Liquid Glass groups:
/// `FestivalRootTrailingItems` inserts its bell/profile `ToolbarSpacer` from the same
/// ``RootChromeTrailingGroups/separatesBellFromProfile(chrome:)`` decision.
@Suite("Root chrome trailing glass groups")
struct RootChromeTrailingGroupsTests {
    @Test("Horizontal bars give the bell and the profile their own glass buttons")
    func bellAndProfileSeparateInHorizontalBars() {
        for chrome in [DeviceLayout.SectionChrome.tabBar, .sidebar] {
            #expect(RootChromeTrailingGroups.separatesBellFromProfile(chrome: chrome))
            #expect(RootChromeTrailingGroups.resolve(showsSearch: true, showsBell: true, chrome: chrome)
                == [[.search], [.bell], [.profile]])
        }
    }

    @Test("The Duo vertical bar adds no fixed spacing: one group (HIG iPhone Duo)")
    func verticalBarKeepsOneGroup() {
        for edge in [HorizontalEdge.leading, .trailing] {
            let chrome = DeviceLayout.SectionChrome.verticalBar(edge)
            #expect(!RootChromeTrailingGroups.separatesBellFromProfile(chrome: chrome))
            #expect(!RootChromeTrailingGroups.separatesSearch(chrome: chrome))
            #expect(RootChromeTrailingGroups.resolve(showsSearch: true, showsBell: true, chrome: chrome)
                == [[.search, .bell, .profile]])
            #expect(RootChromeTrailingGroups.resolve(showsSearch: true, showsBell: false, chrome: chrome)
                == [[.search, .profile]])
        }
    }

    @Test("Horizontal bars keep Search in its own group")
    func horizontalBarsSeparateSearch() {
        for chrome in [DeviceLayout.SectionChrome.tabBar, .sidebar] {
            #expect(RootChromeTrailingGroups.separatesSearch(chrome: chrome))
        }
    }

    @Test("Without a selected profile only Search and the profile show")
    func anonymousHasNoBell() {
        #expect(RootChromeTrailingGroups.resolve(showsSearch: true, showsBell: false, chrome: .tabBar)
            == [[.search], [.profile]])
        #expect(RootChromeTrailingGroups.resolve(showsSearch: false, showsBell: false, chrome: .tabBar)
            == [[.profile]])
    }

    @Test("The trailing side never exceeds three glass groups (HIG Toolbars)")
    func atMostThreeGroups() {
        let chromes: [DeviceLayout.SectionChrome] = [.tabBar, .sidebar, .verticalBar(.leading), .verticalBar(.trailing)]
        for chrome in chromes {
            for showsSearch in [true, false] {
                for showsBell in [true, false] {
                    let groups = RootChromeTrailingGroups.resolve(
                        showsSearch: showsSearch, showsBell: showsBell, chrome: chrome
                    )
                    #expect(groups.count <= 3)
                    #expect(groups.last?.last == .profile, "profile must stay rightmost")
                }
            }
        }
    }
}
