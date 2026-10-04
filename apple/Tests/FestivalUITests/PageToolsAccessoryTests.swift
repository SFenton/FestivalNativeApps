import CoreGraphics
import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - PageToolsAccessoryFit (issue #92)

@Suite("Tab-bar accessory fit")
struct PageToolsAccessoryFitTests {
    @Test("Required width counts 44 pt slots, gaps, the divider and padding")
    func requiredWidth() {
        // Profile only: one slot plus padding.
        #expect(PageToolsAccessoryFit.requiredWidth(pageTools: 0, accountItems: 1) == 56)
        // Notifications and Profile: two slots, one gap, no divider.
        #expect(PageToolsAccessoryFit.requiredWidth(pageTools: 0, accountItems: 2) == 104)
        // Sort, Filter | Notifications, Profile: four slots, a divider, four gaps.
        #expect(PageToolsAccessoryFit.requiredWidth(pageTools: 2, accountItems: 2) == 205)
        // Sort, Filter, Quick Links | Notifications, Profile.
        #expect(PageToolsAccessoryFit.requiredWidth(pageTools: 3, accountItems: 2) == 253)
    }

    @Test("Negative counts are treated as zero")
    func negativeCounts() {
        #expect(PageToolsAccessoryFit.requiredWidth(pageTools: -3, accountItems: -1) == 12)
    }

    @Test("The expanded accessory keeps every Songs item")
    func expandedKeepsAll() {
        // iPhone 17 (402 pt): the expanded accessory measures 348 pt.
        #expect(!PageToolsAccessoryFit.folds(
            width: 348, pageTools: 3, accountItems: 2, dynamicTypeSize: .large
        ))
    }

    @Test("The inline accessory folds five items but keeps four")
    func inlineFoldsOnlyWhenNeeded() {
        // Inline beside the minimized tab bar it measures 222 pt.
        #expect(PageToolsAccessoryFit.folds(
            width: 222, pageTools: 3, accountItems: 2, dynamicTypeSize: .large
        ))
        #expect(!PageToolsAccessoryFit.folds(
            width: 222, pageTools: 2, accountItems: 2, dynamicTypeSize: .large
        ))
    }

    @Test("An unmeasured accessory never folds on width alone")
    func unmeasured() {
        #expect(!PageToolsAccessoryFit.folds(
            width: 0, pageTools: 3, accountItems: 2, dynamicTypeSize: .large
        ))
    }

    @Test("Accessibility text sizes always fold; standard sizes do not")
    func dynamicType() {
        #expect(PageToolsAccessoryFit.folds(
            width: 400, pageTools: 2, accountItems: 1, dynamicTypeSize: .accessibility1
        ))
        #expect(!PageToolsAccessoryFit.folds(
            width: 400, pageTools: 2, accountItems: 1, dynamicTypeSize: .xxxLarge
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

    @Test("Identical layout reports leave the stored values unchanged")
    func reportAccessory() {
        let registry = PageToolsRegistry()
        registry.reportAccessory(width: 348, inline: false)
        #expect(registry.accessoryWidth == 348)
        #expect(!registry.isInline)
        registry.reportAccessory(width: 222, inline: true)
        #expect(registry.accessoryWidth == 222)
        #expect(registry.isInline)
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
