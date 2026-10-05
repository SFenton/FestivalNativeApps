import CoreGraphics
import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - PageToolsAccessoryFit (issues #92, #300)

@Suite("Tab-bar accessory fit")
struct PageToolsAccessoryFitTests {
    @Test("Required width counts fixed 44 pt slots and the divider before the bell")
    func requiredWidth() {
        #expect(PageToolsAccessoryFit.requiredWidth(pageTools: 0, showsBell: false) == 0)
        // Notifications alone: one slot, no divider.
        #expect(PageToolsAccessoryFit.requiredWidth(pageTools: 0, showsBell: true) == 44)
        // Sort, Filter, Quick Links without a profile: three slots.
        #expect(PageToolsAccessoryFit.requiredWidth(pageTools: 3, showsBell: false) == 132)
        // Sort, Filter, Quick Links | Notifications.
        #expect(PageToolsAccessoryFit.requiredWidth(pageTools: 3, showsBell: true) == 177)
    }

    @Test("Negative counts are treated as zero")
    func negativeCounts() {
        #expect(PageToolsAccessoryFit.requiredWidth(pageTools: -3, showsBell: true) == 44)
    }

    @Test("The inline width follows the window, never the morphing accessory")
    func inlineWidth() {
        // Measured: the inline capsule is 222 pt on a 402 pt iPhone, 260 pt on 440 pt.
        #expect(PageToolsAccessoryFit.inlineWidth(windowWidth: 402) == 210)
        #expect(PageToolsAccessoryFit.inlineWidth(windowWidth: 440) == 248)
        #expect(PageToolsAccessoryFit.inlineWidth(windowWidth: 375) == 183)
        #expect(PageToolsAccessoryFit.inlineWidth(windowWidth: 100) == 0)
    }

    @Test("Songs keeps every item, expanded and inline, from 375 pt up")
    func songsNeverFoldsAtStandardSizes() {
        for window: CGFloat in [375, 393, 402, 440] {
            #expect(!PageToolsAccessoryFit.folds(
                windowWidth: window, pageTools: 3, showsBell: true, dynamicTypeSize: .large
            ))
        }
    }

    @Test("A window too narrow for the inline accessory folds, in both placements")
    func narrowWindowFolds() {
        // 320 pt (Display Zoom on a small iPhone): 128 pt inline.
        #expect(PageToolsAccessoryFit.folds(
            windowWidth: 320, pageTools: 3, showsBell: true, dynamicTypeSize: .large
        ))
        #expect(!PageToolsAccessoryFit.folds(
            windowWidth: 320, pageTools: 2, showsBell: false, dynamicTypeSize: .large
        ))
    }

    @Test("An unmeasured window never folds on width alone")
    func unmeasured() {
        #expect(!PageToolsAccessoryFit.folds(
            windowWidth: 0, pageTools: 3, showsBell: true, dynamicTypeSize: .large
        ))
    }

    @Test("Accessibility text sizes always fold; standard sizes do not")
    func dynamicType() {
        #expect(PageToolsAccessoryFit.folds(
            windowWidth: 402, pageTools: 2, showsBell: true, dynamicTypeSize: .accessibility1
        ))
        #expect(!PageToolsAccessoryFit.folds(
            windowWidth: 402, pageTools: 2, showsBell: true, dynamicTypeSize: .xxxLarge
        ))
    }
}

// MARK: - PageToolsRegistry (issue #92)

@Suite("Tab-bar accessory registry")
@MainActor
struct PageToolsRegistryTests {
    private func entry(_ registry: PageToolsRegistry, _ scope: UUID, _ order: Int) -> UUID {
        let id = UUID()
        registry.upsert(id: id, scope: scope, order: order, content: AnyView(EmptyView()))
        return id
    }

    @Test("No page on screen shows no tools")
    func emptyWithoutPage() {
        let registry = PageToolsRegistry()
        _ = entry(registry, UUID(), PageToolOrder.primary)
        #expect(registry.frontItems.isEmpty)
    }

    @Test("Tools sort by order, keeping registration order for ties")
    func ordering() {
        let registry = PageToolsRegistry()
        let page = UUID()
        registry.pageAppeared(page)
        let quickLinks = entry(registry, page, PageToolOrder.quickLinks)
        let filter = entry(registry, page, PageToolOrder.secondary)
        let sort = entry(registry, page, PageToolOrder.primary)
        let sortTwin = entry(registry, page, PageToolOrder.primary)
        #expect(registry.frontItems.map(\.id) == [sort, sortTwin, filter, quickLinks])
    }

    @Test("Only the front page's tools show; popping restores the page below")
    func frontPageScoping() {
        let registry = PageToolsRegistry()
        let songs = UUID()
        let detail = UUID()
        registry.pageAppeared(songs)
        let sort = entry(registry, songs, PageToolOrder.primary)
        registry.pageAppeared(detail)
        let paths = entry(registry, detail, PageToolOrder.secondary)
        #expect(registry.frontItems.map(\.id) == [paths])
        registry.pageDisappeared(detail)
        #expect(registry.frontItems.map(\.id) == [sort])
    }

    @Test("A page that reappears becomes the front page again")
    func reappearMovesToFront() {
        let registry = PageToolsRegistry()
        let first = UUID()
        let second = UUID()
        registry.pageAppeared(first)
        registry.pageAppeared(second)
        let tool = entry(registry, first, PageToolOrder.primary)
        registry.pageAppeared(first)
        #expect(registry.frontItems.map(\.id) == [tool])
    }

    @Test("Replacing a tool keeps its slot; removing it drops it")
    func upsertAndRemove() {
        let registry = PageToolsRegistry()
        let page = UUID()
        registry.pageAppeared(page)
        let sort = entry(registry, page, PageToolOrder.primary)
        let filter = entry(registry, page, PageToolOrder.primary)
        registry.upsert(id: sort, scope: page, order: PageToolOrder.primary, content: AnyView(Text("Sort")))
        #expect(registry.frontItems.map(\.id) == [sort, filter])
        registry.remove(id: sort)
        #expect(registry.frontItems.map(\.id) == [filter])
    }

    @Test("Window width reports are stored")
    func reportWindow() {
        let registry = PageToolsRegistry()
        #expect(registry.windowWidth == 0)
        registry.reportWindow(width: 402)
        #expect(registry.windowWidth == 402)
        registry.reportWindow(width: 402)
        #expect(registry.windowWidth == 402)
    }

    @Test("The accessory has content with a profile or with front-page tools")
    func hasContent() {
        let registry = PageToolsRegistry()
        let page = UUID()
        registry.pageAppeared(page)
        #expect(!registry.hasContent(hasPlayer: false))
        #expect(registry.hasContent(hasPlayer: true))
        _ = entry(registry, page, PageToolOrder.primary)
        #expect(registry.hasContent(hasPlayer: false))
    }

    @Test("An inline menu choice runs only after its sheet has closed")
    func inlineMenuChoiceRunsAfterDismissal() {
        let registry = PageToolsRegistry()
        var picked: [String] = []
        let sort = PageToolMenuChoice(id: "sort", label: AnyView(Text("Sort…"))) { picked.append("sort") }
        let filter = PageToolMenuChoice(id: "filter", label: AnyView(Text("Filter…"))) { picked.append("filter") }
        registry.presentInlineMenu(title: "Sort and Filter", choices: [sort, filter])
        #expect(registry.inlineMenu?.title == "Sort and Filter")
        #expect(registry.inlineMenu?.choices.map(\.id) == ["sort", "filter"])
        registry.choose(filter)
        #expect(registry.inlineMenu == nil)
        #expect(picked.isEmpty)
        registry.inlineMenuDismissed()
        #expect(picked == ["filter"])
        registry.inlineMenuDismissed()
        #expect(picked == ["filter"])
    }

    @Test("Closing an inline menu without a choice runs nothing")
    func inlineMenuCloseRunsNothing() {
        let registry = PageToolsRegistry()
        var ran = false
        let choice = PageToolMenuChoice(id: "a", label: AnyView(Text("A"))) { ran = true }
        registry.presentInlineMenu(title: "Rank By", choices: [choice])
        registry.inlineMenu = nil
        registry.inlineMenuDismissed()
        #expect(!ran)
        #expect(registry.inlineMenu == nil)
    }
}

// MARK: - Host gate (iPhone Duo inner portrait)

@Suite("Tab-bar accessory host")
struct PageToolsAccessoryHostTests {
    @Test("iPhone portrait hosts the accessory")
    func iPhoneHosts() {
        let phone = DeviceLayout.resolve(LayoutSignals(
            size: CGSize(width: 402, height: 874), widthClass: .compact,
            safeAreaInsets: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)
        ))
        #expect(PageToolsAccessoryHost.hostsAccessory(in: phone))
    }

    @Test("Duo inner portrait (regular width, horizontal tab bar) keeps bar items")
    func duoInnerPortraitKeepsBarItems() {
        let inner = DeviceLayout.resolve(LayoutSignals(
            size: CGSize(width: 669, height: 951), widthClass: .regular, hinge: .fullyOpen
        ))
        #expect(inner.sectionChrome == .tabBar)
        #expect(!PageToolsAccessoryHost.hostsAccessory(in: inner))
    }

    @Test("Duo vertical bars never host the accessory")
    func verticalBarsDoNot() {
        let folded = DeviceLayout.resolve(LayoutSignals(
            size: CGSize(width: 466, height: 678), widthClass: .compact,
            safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 34, trailing: 84),
            verticalBarEdge: .trailing, hinge: .closed
        ))
        let innerLandscape = DeviceLayout.resolve(LayoutSignals(
            size: CGSize(width: 951, height: 669), widthClass: .regular,
            safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 84),
            verticalBarEdge: .trailing, hinge: .fullyOpen
        ))
        #expect(!PageToolsAccessoryHost.hostsAccessory(in: folded))
        #expect(!PageToolsAccessoryHost.hostsAccessory(in: innerLandscape))
    }
}
