import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - Trailing glass groups (issues #14, #92)

/// Pins how the trailing items split into Liquid Glass groups: page tools (Sort, Filter,
/// Quick Links), then account (bell, profile). `FestivalRootTrailingItems` and
/// `PageTrailingItems` insert their `ToolbarSpacer` from the same
/// ``RootChromeTrailingGroups/separatesAccount(chrome:)`` decision.
@Suite("Root chrome trailing glass groups")
struct RootChromeTrailingGroupsTests {
    @Test("Songs reads Sort, Filter, Quick Links | Notifications, Profile")
    func songsTwoGroups() {
        for chrome in [DeviceLayout.SectionChrome.tabBar, .sidebar] {
            #expect(RootChromeTrailingGroups.separatesAccount(chrome: chrome))
            #expect(RootChromeTrailingGroups.resolve(pageActions: 2, showsQuickLinks: true, showsBell: true, chrome: chrome)
                == [[.pageAction, .pageAction, .quickLinks], [.bell, .profile]])
        }
    }

    @Test("Folded Sort and Filter count as one page action")
    func foldedTools() {
        #expect(RootChromeTrailingGroups.resolve(pageActions: 1, showsQuickLinks: true, showsBell: false, chrome: .tabBar)
            == [[.pageAction, .quickLinks], [.profile]])
    }

    @Test("Pages without tools show only Notifications and Profile")
    func noToolsOneGroup() {
        #expect(RootChromeTrailingGroups.resolve(pageActions: 0, showsQuickLinks: false, showsBell: true, chrome: .tabBar)
            == [[.bell, .profile]])
        #expect(RootChromeTrailingGroups.resolve(pageActions: 0, showsQuickLinks: false, showsBell: false, chrome: .tabBar)
            == [[.profile]])
    }

    @Test("The Duo vertical bar adds no fixed spacing: one group (HIG iPhone Duo)")
    func verticalBarKeepsOneGroup() {
        for edge in [HorizontalEdge.leading, .trailing] {
            let chrome = DeviceLayout.SectionChrome.verticalBar(edge)
            #expect(!RootChromeTrailingGroups.separatesAccount(chrome: chrome))
            #expect(RootChromeTrailingGroups.resolve(pageActions: 2, showsQuickLinks: true, showsBell: true, chrome: chrome)
                == [[.pageAction, .pageAction, .quickLinks, .bell, .profile]])
        }
    }

    @Test("The trailing side never exceeds three glass groups; Profile stays rightmost (HIG Toolbars)")
    func atMostThreeGroups() {
        let chromes: [DeviceLayout.SectionChrome] = [.tabBar, .sidebar, .verticalBar(.leading), .verticalBar(.trailing)]
        for chrome in chromes {
            for actions in 0...2 {
                for quickLinks in [true, false] {
                    for bell in [true, false] {
                        let groups = RootChromeTrailingGroups.resolve(
                            pageActions: actions, showsQuickLinks: quickLinks, showsBell: bell, chrome: chrome
                        )
                        #expect(groups.count <= 3)
                        #expect(groups.allSatisfy { !$0.isEmpty })
                        #expect(groups.last?.last == .profile, "profile must stay rightmost")
                    }
                }
            }
        }
    }
}

// MARK: - Pushed-page avatar placement (issue #85)

/// iOS pins `.primaryAction` to the far trailing edge, and the pushed-page avatar comes
/// from an outer modifier (`.pageTrailingItems()`) whose items SwiftUI lays out
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
