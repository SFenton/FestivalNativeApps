import CoreGraphics
import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - FloatingPageToolsFit (issues #92, #300, #632)

@Suite("Floating page tools fit")
struct FloatingPageToolsFitTests {
    @Test("Each tool is a 44 pt circle 10 pt from its neighbour (web Gap.sm)")
    func requiredWidth() {
        #expect(FloatingPageToolsFit.slot == 44)
        #expect(FloatingPageToolsFit.requiredWidth(pageTools: 0) == 0)
        #expect(FloatingPageToolsFit.requiredWidth(pageTools: 1) == 44)
        // Sort, Filter, Quick Links.
        #expect(FloatingPageToolsFit.requiredWidth(pageTools: 3) == 152)
    }

    @Test("Negative counts are treated as zero")
    func negativeCounts() {
        #expect(FloatingPageToolsFit.requiredWidth(pageTools: -3) == 0)
    }

    @Test("The row reserves the circle plus clear space above and below")
    func reservedHeight() {
        #expect(FloatingPageToolsFit.reservedHeight == 60)
    }

    @Test("The available width is the window less a 16 pt margin each side")
    func availableWidth() {
        #expect(FloatingPageToolsFit.availableWidth(windowWidth: 402) == 370)
        #expect(FloatingPageToolsFit.availableWidth(windowWidth: 320) == 288)
        #expect(FloatingPageToolsFit.availableWidth(windowWidth: 20) == 0)
    }

    @Test("Songs keeps every tool from 320 pt up")
    func songsNeverFoldsAtStandardSizes() {
        for window: CGFloat in [320, 375, 393, 402, 440] {
            #expect(!FloatingPageToolsFit.folds(windowWidth: window, pageTools: 3))
        }
    }

    @Test("A window too narrow for the row folds")
    func narrowWindowFolds() {
        #expect(FloatingPageToolsFit.folds(windowWidth: 150, pageTools: 3))
        #expect(!FloatingPageToolsFit.folds(windowWidth: 150, pageTools: 2))
    }

    @Test("An unmeasured window never folds on width alone")
    func unmeasured() {
        #expect(!FloatingPageToolsFit.folds(windowWidth: 0, pageTools: 3))
    }
}

// MARK: - FloatingPageToolsMotion (issue #632)

@Suite("Floating page tools motion")
struct FloatingPageToolsMotionTests {
    @Test("Web MobileFloatingActionButton timings")
    func webConstants() {
        #expect(FloatingPageToolsMotion.staggerInterval == 0.125)
        #expect(FloatingPageToolsMotion.fadeDuration == 0.4)
        #expect(FloatingPageToolsMotion.quickFade == 0.15)
        #expect(FloatingPageToolsMotion.rise == 12)
    }

    @Test("First reveal staggers, a revisit cross-fades, Reduce Motion removes both")
    func resolve() {
        #expect(FloatingPageToolsMotion.resolve(reduceMotion: false, revealed: false) == .staggered)
        #expect(FloatingPageToolsMotion.resolve(reduceMotion: false, revealed: true) == .quick)
        #expect(FloatingPageToolsMotion.resolve(reduceMotion: true, revealed: false) == .none)
        #expect(FloatingPageToolsMotion.resolve(reduceMotion: true, revealed: true) == .none)
    }

    @Test("The stagger reveals right to left")
    func staggerRightToLeft() {
        #expect(FloatingPageToolsMotion.staggerDelay(index: 2, count: 3) == 0)
        #expect(FloatingPageToolsMotion.staggerDelay(index: 1, count: 3) == 0.125)
        #expect(FloatingPageToolsMotion.staggerDelay(index: 0, count: 3) == 0.25)
        #expect(FloatingPageToolsMotion.staggerDelay(index: 3, count: 3) == 0)
        #expect(FloatingPageToolsMotion.staggerDelay(index: -1, count: 3) == 0)
    }
}

// MARK: - PageToolsRegistry (issue #92)

@Suite("Floating page tools registry")
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

    @Test("A page in an unselected tab never takes the front (#487)")
    func unselectedTabNeverTakesFront() {
        let registry = PageToolsRegistry()
        let songs = UUID()
        let settings = UUID()
        registry.pageVisibilityChanged(songs, onScreen: true, inSelectedTab: true)
        let sort = entry(registry, songs, PageToolOrder.primary)
        let quickLinks = entry(registry, settings, PageToolOrder.quickLinks)
        // A deselect drops the profile tabs; SwiftUI calls Settings' root `onAppear`.
        registry.pageVisibilityChanged(settings, onScreen: true, inSelectedTab: false)
        #expect(registry.frontItems.map(\.id) == [sort])
        // Choosing Settings brings its tools forward; leaving it restores Songs'.
        registry.pageVisibilityChanged(songs, onScreen: true, inSelectedTab: false)
        registry.pageVisibilityChanged(settings, onScreen: true, inSelectedTab: true)
        #expect(registry.frontItems.map(\.id) == [quickLinks])
        registry.pageVisibilityChanged(settings, onScreen: true, inSelectedTab: false)
        registry.pageVisibilityChanged(songs, onScreen: true, inSelectedTab: true)
        #expect(registry.frontItems.map(\.id) == [sort])
    }

    @Test("A page off screen in the selected tab is not the front")
    func offScreenInSelectedTab() {
        let registry = PageToolsRegistry()
        let songs = UUID()
        let detail = UUID()
        registry.pageVisibilityChanged(songs, onScreen: true, inSelectedTab: true)
        let sort = entry(registry, songs, PageToolOrder.primary)
        registry.pageVisibilityChanged(detail, onScreen: true, inSelectedTab: true)
        let paths = entry(registry, detail, PageToolOrder.secondary)
        #expect(registry.frontItems.map(\.id) == [paths])
        registry.pageVisibilityChanged(detail, onScreen: false, inSelectedTab: true)
        #expect(registry.frontItems.map(\.id) == [sort])
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

    @Test("A page's tools are revealed once; a revisit does not replay (web hasVisitedPage)")
    func revealedOnce() {
        let registry = PageToolsRegistry()
        let songs = UUID()
        let detail = UUID()
        registry.pageAppeared(songs)
        #expect(registry.frontScope == songs)
        #expect(!registry.hasRevealed(songs))
        registry.markRevealed(songs)
        registry.markRevealed(songs)
        #expect(registry.hasRevealed(songs))
        registry.pageAppeared(detail)
        #expect(registry.frontScope == detail)
        #expect(!registry.hasRevealed(detail))
        registry.pageDisappeared(detail)
        #expect(registry.frontScope == songs)
        #expect(registry.hasRevealed(songs))
    }

    @Test("A covering sheet hides the tools without dropping them")
    func covered() {
        let registry = PageToolsRegistry()
        let page = UUID()
        registry.pageAppeared(page)
        let sort = entry(registry, page, PageToolOrder.primary)
        #expect(!registry.isCovered)
        registry.setCovered(true)
        #expect(registry.isCovered)
        #expect(registry.frontItems.map(\.id) == [sort])
        registry.setCovered(false)
        #expect(!registry.isCovered)
    }

    @Test("No page on screen has no front scope")
    func noFrontScope() {
        #expect(PageToolsRegistry().frontScope == nil)
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

// MARK: - Host gate (iPhone, iPhone Duo)

@Suite("Floating page tools host")
struct FloatingPageToolsHostTests {
    @Test("iPhone portrait floats page tools")
    func iPhoneHosts() {
        let phone = DeviceLayout.resolve(LayoutSignals(
            size: CGSize(width: 402, height: 874), widthClass: .compact,
            safeAreaInsets: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)
        ))
        #expect(FloatingPageToolsHost.floatsPageTools(in: phone))
    }

    @Test("Duo inner portrait (regular width, horizontal tab bar) keeps bar items")
    func duoInnerPortraitKeepsBarItems() {
        let inner = DeviceLayout.resolve(LayoutSignals(
            size: CGSize(width: 669, height: 951), widthClass: .regular, hinge: .fullyOpen
        ))
        #expect(inner.sectionChrome == .tabBar)
        #expect(!FloatingPageToolsHost.floatsPageTools(in: inner))
    }

    @Test("Duo vertical bars never float page tools")
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
        #expect(!FloatingPageToolsHost.floatsPageTools(in: folded))
        #expect(!FloatingPageToolsHost.floatsPageTools(in: innerLandscape))
    }
}
