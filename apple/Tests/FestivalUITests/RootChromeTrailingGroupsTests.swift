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

// MARK: - Pushed-page avatar placement (issue #85)

/// iOS pins `.primaryAction` to the far trailing edge, and the pushed-page avatar comes
/// from an outer modifier (`.globalSearchToolbarItem()`) whose items SwiftUI lays out
/// before the page's own. The avatar stays rightmost and standalone only while it is the
/// sole `.primaryAction` item, so page actions must use `.festivalPageAction`.
@Suite("Pushed-page avatar placement")
struct PushedPageAvatarPlacementTests {
    @Test("Page actions never claim the avatar's .primaryAction slot")
    func pageActionsUseFestivalPageAction() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FestivalUI")
        let allowed: Set<String> = [
            // Defines `.festivalPageAction` and the macOS branch of the shared items.
            "App/Shell/RootChrome.swift",
            // The pushed-page avatar itself.
            "Features/Search/GlobalSearchView.swift",
        ]
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        var scanned = 0
        for case let url as URL in files where url.pathExtension == "swift" {
            let relative = String(url.path.dropFirst(sources.path.count + 1))
            // The Mac shell owns its own window toolbar (no pushed-page avatar).
            guard !relative.hasPrefix("Mac/"), !allowed.contains(relative) else { continue }
            scanned += 1
            let text = try String(contentsOf: url, encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                if !code.hasPrefix("//"), code.contains(".primaryAction") {
                    offenders.append("\(relative):\(index + 1)")
                }
            }
        }
        #expect(scanned > 50)
        #expect(offenders.isEmpty, "Use .festivalPageAction for page actions: \(offenders)")
    }
}
