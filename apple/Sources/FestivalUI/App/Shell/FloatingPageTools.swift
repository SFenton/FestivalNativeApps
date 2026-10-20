import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Order

/// Positions of a page's tools, leading to trailing (issues #92, #632).
///
/// The page's own actions come first in the page's order (Songs: Sort, then Filter),
/// then Quick Links, trailing-most. Notifications and Profile are not page tools: they
/// share the navigation bar's account pill (issue #632).
enum PageToolOrder {
    /// The page's first action (Songs Sort, Find Rival, Rank By…).
    static let primary = 10
    /// The page's second action (Songs Filter, Song Detail Paths…).
    static let secondary = 20
    /// The page's third action (Item Shop List/Grid).
    static let tertiary = 30
    /// The page's Quick Links menu, after its actions.
    static let quickLinks = 90
}

// MARK: - Registry

/// The front page's tools for the iPhone floating page tools (issues #92, #632).
///
/// Pages register their tools while they are on screen (`onAppear` … `onDisappear`),
/// tagged with their ``PageToolsScope``; only the most recently appeared page's tools
/// show, so a push, pop or tab switch swaps them and two pages' tools never mix.
@MainActor @Observable
final class PageToolsRegistry {
    /// One registered page tool.
    struct Entry: Identifiable {
        let id: UUID
        /// The page (``PageToolsScope``) that registered it.
        var scope: UUID?
        /// Position in the row (``PageToolOrder``); equal orders keep registration order.
        var order: Int
        /// The tool, rendered in the root's environment.
        var content: AnyView
    }

    private(set) var entries: [Entry] = []
    /// Pages on screen, in the order they appeared; the last is the front page.
    private(set) var pageScopes: [UUID] = []
    /// The tab view's measured width (0 before it is laid out), for
    /// ``FloatingPageToolsFit``.
    private(set) var windowWidth: CGFloat = 0
    /// Pages whose tools have appeared at least once: their tools cross-fade on a later
    /// visit instead of replaying the first reveal (web `hasVisitedPage`, issue #632).
    private(set) var revealedScopes: Set<UUID> = []
    /// A root sheet (Notifications, Profile, Search, a tool menu) covers the page, so
    /// the floating tools hide (web `showMobileFab = isMobile && !notificationsOpen`).
    private(set) var isCovered = false
    /// The selected tab's floating row's top edge in global (window) points, or `nil`
    /// while no tab's row is on screen. A page's own bottom chrome (the iPhone Duo
    /// Filter Songs field, ``BottomSearchField``) stacks above it (issue #633).
    private(set) var floatingRowTop: CGFloat?
    /// The row that made the current ``floatingRowTop`` report.
    @ObservationIgnored private var floatingRowOwner: UUID?
    /// A page-tool menu shown as a compact sheet from a floating tool
    /// (``PageToolMenu``); the host presents it.
    var inlineMenu: PageToolInlineMenu?
    /// The choice picked in ``inlineMenu``, run once its sheet has gone.
    private var pendingChoice: (() -> Void)?

    /// Add or replace a tool, keeping its position when replacing.
    ///
    /// - Parameters:
    ///   - id: Stable identity of the registering view instance.
    ///   - scope: The registering page's scope.
    ///   - order: Position in the row.
    ///   - content: The tool.
    func upsert(id: UUID, scope: UUID?, order: Int, content: AnyView) {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].scope = scope
            entries[index].order = order
            entries[index].content = content
        } else {
            entries.append(Entry(id: id, scope: scope, order: order, content: content))
        }
    }

    /// Remove a tool (its page disappeared or no longer offers it).
    ///
    /// - Parameter id: Identity passed to ``upsert(id:scope:order:content:)``.
    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    /// A page started appearing (a push, a pop revealing it, or a tab switch).
    ///
    /// SwiftUI calls `onAppear` for the incoming page when a transition starts and
    /// `onDisappear` for the outgoing one when it ends, so the most recently appeared
    /// page still on screen is the front one.
    ///
    /// - Parameter scope: The page's scope.
    func pageAppeared(_ scope: UUID) {
        pageScopes.removeAll { $0 == scope }
        pageScopes.append(scope)
    }

    /// A page finished disappearing.
    ///
    /// - Parameter scope: The page's scope.
    func pageDisappeared(_ scope: UUID) {
        pageScopes.removeAll { $0 == scope }
    }

    /// A page's visibility changed: it appeared or disappeared, or its tab was selected
    /// or left.
    ///
    /// Only a page on screen in the selected tab can be the front page. SwiftUI can call
    /// `onAppear` on an unselected tab's root when the tab set changes (a deselect drops
    /// the profile tabs, issue #487); counting that as an appearance put Settings' Quick
    /// Links in place of Songs' Sort and Filter until the user left the page.
    ///
    /// - Parameters:
    ///   - scope: The page's scope.
    ///   - onScreen: Between the page's `onAppear` and `onDisappear`.
    ///   - inSelectedTab: The page's tab is the selected one.
    func pageVisibilityChanged(_ scope: UUID, onScreen: Bool, inSelectedTab: Bool) {
        if onScreen && inSelectedTab {
            pageAppeared(scope)
        } else {
            pageDisappeared(scope)
        }
    }

    /// Forget every page and tool: the window stopped floating page tools (an iPhone Duo
    /// inner window rotated from the tab bar to the vertical bar, #633).
    ///
    /// Pages keep their identity across that change, so while the registry is withdrawn
    /// a page popped or pushed cannot report it; when tools float again, every page on
    /// screen reports itself and its tools afresh (``PageToolsScopeModifier``,
    /// ``PageToolRegistration``). Revealed scopes are kept, so returning tools don't
    /// replay their first-appearance motion.
    func resetPages() {
        entries.removeAll()
        pageScopes.removeAll()
        floatingRowTop = nil
        floatingRowOwner = nil
    }

    /// The front page: the most recently appeared page on screen in the selected tab.
    var frontScope: UUID? { pageScopes.last }

    /// The front page's tools in row order; empty when no page is on screen.
    var frontItems: [Entry] {
        guard let front = pageScopes.last else { return [] }
        return entries.enumerated()
            .filter { $0.element.scope == front }
            .sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }
            .map(\.element)
    }

    /// Whether a page's tools have appeared before (``revealedScopes``).
    ///
    /// - Parameter scope: The page's scope.
    /// - Returns: True after ``markRevealed(_:)``.
    func hasRevealed(_ scope: UUID) -> Bool {
        revealedScopes.contains(scope)
    }

    /// Remember that a page's tools have appeared, so a later visit does not replay the
    /// first reveal.
    ///
    /// - Parameter scope: The page's scope.
    func markRevealed(_ scope: UUID) {
        if !revealedScopes.contains(scope) { revealedScopes.insert(scope) }
    }

    /// Hide or show the floating tools for a covering root sheet, skipping identical
    /// reports.
    ///
    /// - Parameter covered: A root sheet covers the page.
    func setCovered(_ covered: Bool) {
        if isCovered != covered { isCovered = covered }
    }

    /// Record the tab view's width, skipping identical reports so observers are not
    /// invalidated on every layout pass.
    ///
    /// - Parameter width: Its width in points.
    func reportWindow(width: CGFloat) {
        if windowWidth != width { windowWidth = width }
    }

    /// Record the selected tab's floating row's top edge, skipping identical reports.
    ///
    /// A row clears only its own report, so a tab switch never loses the new tab's row
    /// to the old one's late clear.
    ///
    /// - Parameters:
    ///   - top: Its top in global points (whole points), or `nil` once it is off screen
    ///     or no longer selected.
    ///   - owner: The reporting row's identity.
    func reportFloatingRow(top: CGFloat?, from owner: UUID) {
        if top == nil, floatingRowOwner != owner { return }
        floatingRowOwner = top == nil ? nil : owner
        if floatingRowTop != top { floatingRowTop = top }
    }

    /// Show a page-tool menu as a compact sheet (``PageToolMenu``).
    ///
    /// - Parameters:
    ///   - title: The sheet's title.
    ///   - choices: The menu's choices, in menu order.
    func presentInlineMenu(title: String, choices: [PageToolMenuChoice]) {
        pendingChoice = nil
        inlineMenu = PageToolInlineMenu(title: title, choices: choices)
    }

    /// Pick a choice: close the sheet, then run it from ``inlineMenuDismissed()`` so a
    /// sheet it presents (Songs Sort, Filter) never collides with the closing one.
    ///
    /// - Parameter choice: The picked choice.
    func choose(_ choice: PageToolMenuChoice) {
        pendingChoice = choice.action
        inlineMenu = nil
    }

    /// The inline menu's sheet finished closing; run the picked choice, if any.
    func inlineMenuDismissed() {
        let choice = pendingChoice
        pendingChoice = nil
        inlineMenu = nil
        choice?()
    }
}

// MARK: - Menus

/// One choice of a page-tool menu, as the inline fallback sheet lists it (issue #92).
struct PageToolMenuChoice: Identifiable {
    /// Accessibility identifier, matching the `Menu` item's.
    let id: String
    /// The row's icon and title.
    let label: AnyView
    /// Checked (the current Rank By, Band Size or Quick Links section).
    var isSelected = false
    /// What picking it does.
    let action: () -> Void
}

/// A page-tool menu presented as a sheet from a floating page tool (issues #92, #632).
struct PageToolInlineMenu: Identifiable {
    let id = UUID()
    /// The sheet's title (the menu's name).
    let title: String
    /// The choices, in menu order.
    let choices: [PageToolMenuChoice]
}

/// A page tool's `Menu`, which a floating page tool shows as a compact sheet (issues
/// #92, #632).
///
/// The iPhone tab-bar accessory this replaced could not open a `Menu` inline and only
/// answered near its glyph, so its menus became buttons listing `choices` in a compact
/// sheet the root presents (#92). The floating tools keep that sheet (#632 changed their
/// placement, not what a tap opens): ``FloatingPageToolsBar`` marks them with
/// ``EnvironmentValues/pageToolsFloating``. Elsewhere (navigation bars, Mac) it is the
/// ordinary `Menu`. Modifiers applied to it (identifier, accessibility label and value,
/// tint) apply to either form.
struct PageToolMenu<MenuContent: View, MenuLabel: View>: View {
    let title: String
    let choices: () -> [PageToolMenuChoice]
    let content: () -> MenuContent
    let label: () -> MenuLabel

    /// Create the menu.
    ///
    /// - Parameters:
    ///   - title: The fallback sheet's title.
    ///   - choices: The same choices as `content`, for the fallback sheet.
    ///   - content: The `Menu`'s items.
    ///   - label: The `Menu`'s label.
    init(
        _ title: String, choices: @escaping () -> [PageToolMenuChoice],
        @ViewBuilder content: @escaping () -> MenuContent,
        @ViewBuilder label: @escaping () -> MenuLabel
    ) {
        self.title = title
        self.choices = choices
        self.content = content
        self.label = label
    }

    @Environment(\.pageToolsFloating) private var floating
    @Environment(\.pageToolsRegistry) private var registry

    var body: some View {
        // Only ``FloatingPageToolsBar`` sets `floating`; navigation bars keep the menu.
        if floating, let registry {
            Button {
                registry.presentInlineMenu(title: title, choices: choices())
            } label: {
                label()
            }
        } else {
            Menu(content: content, label: label)
        }
    }
}

/// The sheet listing an inline page-tool menu's choices (issue #92).
struct PageToolInlineMenuSheet: View {
    let menu: PageToolInlineMenu
    let registry: PageToolsRegistry

    var body: some View {
        FestivalModal(menu.title, closeIdentifier: "fst.page-tools.menu.close") {
            List(menu.choices) { choice in
                Button {
                    registry.choose(choice)
                } label: {
                    HStack {
                        choice.label
                        Spacer(minLength: 8)
                        if choice.isSelected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(BrandTokens.accentBlue)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .foregroundStyle(BrandTokens.textPrimary)
                .accessibilityAddTraits(choice.isSelected ? .isSelected : [])
                .accessibilityIdentifier(choice.id)
            }
        }
        .festivalSheet(.compact)
    }
}

// MARK: - Fit

/// Fixed slot layout and fold rule for the iPhone floating page tools (pure,
/// unit-tested; issues #92, #300, #632).
///
/// Every tool is its own 44 pt Liquid Glass circle (HIG Buttons: "Minimum hit region:
/// 44x44 pt"), laid out from the trailing edge with ``spacing`` between circles, like
/// the web's mobile floating action buttons (`MobileFloatingActionButton`). Slots never
/// stretch, so a push, pop or tab switch only swaps the tools. Notifications is not a
/// floating tool: it shares the navigation bar's account pill with Profile (#632).
///
/// The row floats above the tab bar in the page's bottom safe area
/// (``FloatingPageToolsInset``), which does not change when scrolling minimizes the
/// tab bar, so the buttons stay put (no inline morph as the old accessory had). A page
/// folds its secondary actions (Songs: Sort and Filter into "Sort and Filter") only when
/// its tools would not fit the row's width; the circles do not grow with text size, so
/// accessibility sizes no longer fold (the Large Content Viewer shows each tool's
/// name, HIG Accessibility).
enum FloatingPageToolsFit {
    /// Diameter of one tool's glass circle, which is also its hit target.
    static let slot: CGFloat = 44
    /// Space between neighbouring circles (web `Gap.sm`).
    static let spacing: CGFloat = 10
    /// Distance from the window's trailing edge to the trailing-most circle (the
    /// system's standard 16 pt content margin on iPhone).
    static let margin: CGFloat = 16
    /// Clear space above and below the row, between the content and the tab bar.
    static let verticalPadding: CGFloat = 8
    /// The bottom safe-area height the row reserves on every page of the tab, tools or
    /// not, so the last content row scrolls clear of the buttons and a push never moves
    /// the content's bottom edge.
    static var reservedHeight: CGFloat { slot + verticalPadding * 2 }

    /// Bottom padding that ends a page's content at the floating row's top (issue #678).
    ///
    /// The row sits in the tab stack's bottom safe-area inset, but on iOS 26.5 and 27 a
    /// page's scroll view inside the `NavigationStack` still ends at the tab bar: the
    /// page's frame stops there and its scroll content insets only for the tab bar, so
    /// the last row (a failed section's Retry) scrolled under the buttons. (The page's
    /// geometry reports the stack's inset in its safe area, but the scroll view ignores
    /// it.) Measured from the page's frame rather than fixed, it falls to zero wherever
    /// a page already ends above the row, so content is never lifted twice.
    ///
    /// - Parameters:
    ///   - pageBottom: The page's bottom edge, in window (global) points, before this
    ///     padding.
    ///   - floatingRowTop: The floating row's top in the same space, or `nil` where no
    ///     row floats (``PageToolsRegistry/floatingRowTop``).
    /// - Returns: The overlap to reserve, in whole points (never negative).
    static func pageBottomReserve(pageBottom: CGFloat, floatingRowTop: CGFloat?) -> CGFloat {
        guard let floatingRowTop, pageBottom > 0 else { return 0 }
        return max(0, pageBottom - floatingRowTop).rounded(.up)
    }

    /// Width the row needs for some tools.
    ///
    /// - Parameter pageTools: Page actions plus Quick Links.
    /// - Returns: The row's minimum width in points, excluding ``margin``.
    static func requiredWidth(pageTools: Int) -> CGFloat {
        let count = CGFloat(max(0, pageTools))
        guard count > 0 else { return 0 }
        return count * slot + (count - 1) * spacing
    }

    /// The row's available width in a window: the window less a ``margin`` each side.
    ///
    /// - Parameter windowWidth: The tab view's width.
    /// - Returns: The available width in points, never negative.
    static func availableWidth(windowWidth: CGFloat) -> CGFloat {
        max(0, windowWidth - margin * 2)
    }

    /// Whether the page folds its secondary actions into one menu.
    ///
    /// - Parameters:
    ///   - windowWidth: The tab view's width; zero (not yet measured) never folds.
    ///   - pageTools: Unfolded page actions plus Quick Links.
    /// - Returns: True to fold.
    static func folds(windowWidth: CGFloat, pageTools: Int) -> Bool {
        guard windowWidth > 0 else { return false }
        return availableWidth(windowWidth: windowWidth) < requiredWidth(pageTools: pageTools)
    }
}

// MARK: - Motion

/// How the floating page tools appear and leave (pure, unit-tested; issue #632).
///
/// Web `MobileFloatingActionButton`: the first time a page's tools appear they fade up
/// right to left, `STAGGER_INTERVAL` 125 ms apart, each over `FADE_DURATION` 400 ms
/// ease-out from 12 px below; returning to a page does not replay that (`hasVisitedPage`)
/// and its tools only cross-fade (`QUICK_FADE_MS` 150 ms), as do tools leaving on a push,
/// pop or tab switch and the whole row hiding while Notifications or another sheet covers
/// it. Reduce Motion (system or the app's setting) removes every fade.
enum FloatingPageToolsMotion: Equatable {
    /// Right-to-left fade-up stagger: a page's first reveal.
    case staggered
    /// A short cross-fade: a revisited page, a tool added later, a tool leaving.
    case quick
    /// No animation (Reduce Motion).
    case none

    /// Delay between neighbouring tools' first fade-up (web `STAGGER_INTERVAL`).
    static let staggerInterval: Double = 0.125
    /// One tool's first fade-up (web `FADE_DURATION`).
    static let fadeDuration: Double = 0.4
    /// The cross-fade for every other change (web `QUICK_FADE_MS`).
    static let quickFade: Double = 0.15
    /// How far a tool rises while it first fades up (web `fadeInUp`, 12 px).
    static let rise: CGFloat = 12

    /// Resolve the motion for the front page's tools.
    ///
    /// - Parameters:
    ///   - reduceMotion: System or in-app Reduce Motion.
    ///   - revealed: The page's tools have appeared before.
    /// - Returns: The motion to use.
    static func resolve(reduceMotion: Bool, revealed: Bool) -> Self {
        if reduceMotion { return .none }
        return revealed ? .quick : .staggered
    }

    /// The delay before a tool fades up in a ``staggered`` reveal: the trailing-most
    /// tool first, then each one to its left (web reveals right to left).
    ///
    /// - Parameters:
    ///   - index: The tool's position, leading to trailing.
    ///   - count: Tools in the row.
    /// - Returns: The delay in seconds; zero for a tool outside the row.
    static func staggerDelay(index: Int, count: Int) -> Double {
        guard index >= 0, index < count else { return 0 }
        return Double(count - 1 - index) * staggerInterval
    }
}

// MARK: - Environment

extension EnvironmentValues {
    /// Set only where page tools float above a horizontal tab bar (iPhone, compact iPad
    /// windows, the iPhone Duo inner display in portrait; issues #632, #633). Nil (the
    /// iPhone Duo vertical bar, the regular-width iPad sidebar shell, Mac) means pages
    /// keep their tools as navigation-bar, rail or window-toolbar items.
    @Entry var pageToolsRegistry: PageToolsRegistry? = nil

    /// The enclosing page's scope; tool registrations are tagged with it.
    @Entry var pageToolsScope: UUID? = nil

    /// True inside ``FloatingPageToolsBar``: a ``PageToolMenu`` there is a button that
    /// lists its choices in a compact sheet (issues #92, #632).
    @Entry var pageToolsFloating = false
}

// MARK: - Host (root)

extension View {
    /// Host the floating page tools on the iPhone root `TabView` (issues #92, #632).
    ///
    /// A window with a horizontal tab bar publishes a ``PageToolsRegistry``: pages hand it their tools, and each tab's
    /// ``FloatingPageToolsInset`` draws the front page's tools as individual floating
    /// Liquid Glass buttons above the tab bar. Elsewhere it publishes nothing, so pages
    /// keep their navigation-bar items. The host presents a ``PageToolMenu``'s choices.
    ///
    /// - Parameter covered: The tools hide (Search is open, or Notifications, Profile or
    ///   another root sheet covers the page).
    /// - Returns: The tab view hosting the registry.
    func festivalFloatingPageTools(covered: Bool) -> some View {
        modifier(FloatingPageToolsHost(covered: covered))
    }
}

/// Implementation of ``SwiftUICore/View/festivalFloatingPageTools(covered:)``.
struct FloatingPageToolsHost: ViewModifier {
    let covered: Bool

    /// Whether the window floats page tools: wherever the horizontal tab bar is
    /// (agent decision, issue #633; pattern `page-tools-and-nav-chrome` R28).
    ///
    /// That is iPhone in either orientation (a large iPhone in landscape is regular
    /// width), compact iPad windows and the iPhone Duo inner display in portrait or
    /// partially folded portrait, a single full-width push stack (on-demand splits are
    /// landscape only). The Duo vertical bar (folded, inner landscape and book) keeps
    /// rail items with system overflow, the regular-width iPad sidebar shell keeps
    /// trailing navigation-bar items and the Mac keeps its window toolbar.
    ///
    /// - Parameter layout: The window's published layout.
    /// - Returns: True for a horizontal tab bar.
    nonisolated static func floatsPageTools(in layout: DeviceLayout) -> Bool {
        layout.sectionChrome == .tabBar
    }
    @State private var registry = PageToolsRegistry()
    @Environment(\.deviceLayout) private var layout

    func body(content: Content) -> some View {
        #if os(iOS)
        // One branch for both chromes, so a chrome change never rebuilds the tabs.
        let floats = Self.floatsPageTools(in: layout)
        let isCovered = covered || registry.inlineMenu != nil
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                registry.reportWindow(width: width)
            }
            .onChange(of: isCovered, initial: true) { _, covered in
                registry.setCovered(covered)
            }
            .onChange(of: floats) { _, floats in
                if !floats { registry.resetPages() }
            }
            .sheet(item: Bindable(registry).inlineMenu, onDismiss: registry.inlineMenuDismissed) { menu in
                PageToolInlineMenuSheet(menu: menu, registry: registry)
            }
            .environment(\.pageToolsRegistry, floats ? registry : nil)
        #else
        content
        #endif
    }
}

// MARK: - Per-tab inset

extension View {
    /// Float the front page's tools above the tab bar for this tab's navigation stack
    /// (issue #632). `FestivalTabStack` applies it; a no-op without a
    /// ``PageToolsRegistry`` (pages there keep their navigation-bar items).
    ///
    /// - Parameter isSelected: This tab is the selected one.
    /// - Returns: The stack with the floating row in its bottom safe area.
    func floatingPageTools(isSelected: Bool) -> some View {
        modifier(FloatingPageToolsInset(isSelected: isSelected))
    }
}

/// Implementation of ``SwiftUICore/View/floatingPageTools(isSelected:)``.
///
/// The row sits in the stack's bottom safe-area inset, outside the pushed pages, so a
/// push or pop swaps the tools with a fade instead of sliding them, and the tab bar
/// minimizing on scroll does not move it. Pages' scroll views inside the stack ignore
/// that inset (iOS 26.5, 27), so each page reserves the row itself
/// (``PageToolsScopeModifier``, ``FloatingPageToolsFit/pageBottomReserve(pageBottom:floatingRowTop:)``):
/// the last row scrolls clear of the buttons.
struct FloatingPageToolsInset: ViewModifier {
    let isSelected: Bool
    @Environment(\.pageToolsRegistry) private var registry

    func body(content: Content) -> some View {
        // One branch whether or not tools float: an iPhone Duo inner window rotating
        // between the vertical bar and the tab bar toggles the registry (#633), and a
        // branch change would rebuild the stack, dropping its pages' state (an open
        // Paths sheet). Without a registry the inset is empty and adds no height.
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if let registry {
                FloatingPageToolsBar(registry: registry, isSelected: isSelected)
            }
        }
    }
}

// MARK: - Floating bar

/// The front page's tools as individual floating Liquid Glass buttons, trailing-aligned
/// above the tab bar (issue #632; web `MobileFloatingActionButton`).
///
/// Each tool is a 44 × 44 pt glass circle (``FloatingPageToolsFit``,
/// ``FloatingPageToolLabelStyle``) on the shared glass surface, so Reduce Transparency
/// and Increase Contrast (system or in-app) give an opaque circle with a border
/// (`surface-materials` R4). Tools appear with their page's loaded content (pages
/// register them behind their load gate) and fade as ``FloatingPageToolsMotion``
/// describes. The row hides while a root sheet covers it. Text stops growing at
/// ``maxTypeSize``; long-pressing a tool shows the Large Content Viewer instead.
/// VoiceOver reads the tools leading to trailing, after the page content.
///
/// It builds on every platform so the hosted accessibility tests in `apple-ci` (macOS)
/// render the real bar (`NavButtonAccessibilityTests`, issue #395).
struct FloatingPageToolsBar: View {
    let registry: PageToolsRegistry
    /// The bar's tab is the selected one; other tabs' bars draw nothing.
    var isSelected = true
    /// This row's identity for ``PageToolsRegistry/reportFloatingRow(top:from:)``.
    @State private var rowID = UUID()
    /// This row's last measured top, in global points.
    @State private var rowTop: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var reduceMotion = false

    /// The largest Dynamic Type size the fixed-size circles lay out.
    static let maxTypeSize = DynamicTypeSize.xxxLarge

    var body: some View {
        let tools = isSelected ? registry.frontItems : []
        let front = registry.frontScope
        let motion = FloatingPageToolsMotion.resolve(
            reduceMotion: reduceMotion || systemReduceMotion,
            revealed: front.map(registry.hasRevealed) ?? true
        )
        let covered = registry.isCovered
        HStack(spacing: FloatingPageToolsFit.spacing) {
            Spacer(minLength: 0)
            ForEach(Array(tools.enumerated()), id: \.element.id) { index, item in
                item.content
                    .frame(width: FloatingPageToolsFit.slot, height: FloatingPageToolsFit.slot)
                    .festivalGlassCapsule(.control, interactive: true)
                    .accessibilityShowsLargeContentViewer()
                    .transition(Self.transition(motion, index: index, count: tools.count))
            }
        }
        .labelStyle(FloatingPageToolLabelStyle())
        .environment(\.pageToolsFloating, true)
        .padding(.horizontal, FloatingPageToolsFit.margin)
        .frame(height: FloatingPageToolsFit.reservedHeight)
        .frame(maxWidth: .infinity)
        .font(.body)
        .tint(BrandTokens.textPrimary)
        .dynamicTypeSize(...Self.maxTypeSize)
        .opacity(covered ? 0 : 1)
        .animation(
            motion == .none ? nil : .easeOut(duration: FloatingPageToolsMotion.quickFade),
            value: covered
        )
        .allowsHitTesting(!covered)
        // An empty row is no element at all, so VoiceOver never lands on a nameless group.
        .accessibilityHidden(covered || tools.isEmpty)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Page Tools")
        .accessibilityIdentifier("fst.page-tools")
        .onChange(of: tools.map(\.id)) { _, ids in
            // Later visits to this page cross-fade instead of replaying the stagger.
            if let front, !ids.isEmpty { registry.markRevealed(front) }
        }
        // The page's own bottom chrome stacks above the selected row (issue #633).
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY.rounded() } action: { top in
            rowTop = top
            if isSelected { registry.reportFloatingRow(top: top, from: rowID) }
        }
        .onChange(of: isSelected) { _, selected in
            registry.reportFloatingRow(top: selected ? rowTop : nil, from: rowID)
        }
        .onDisappear { registry.reportFloatingRow(top: nil, from: rowID) }
    }

    /// A tool's insertion and removal transition.
    ///
    /// - Parameters:
    ///   - motion: The row's motion.
    ///   - index: The tool's position, leading to trailing.
    ///   - count: Tools in the row.
    /// - Returns: The transition.
    static func transition(_ motion: FloatingPageToolsMotion, index: Int, count: Int) -> AnyTransition {
        let quick = Animation.easeOut(duration: FloatingPageToolsMotion.quickFade)
        switch motion {
        case .none:
            return .identity
        case .quick:
            return AnyTransition.opacity.animation(quick)
        case .staggered:
            let delay = FloatingPageToolsMotion.staggerDelay(index: index, count: count)
            return .asymmetric(
                insertion: AnyTransition.opacity
                    .combined(with: .offset(y: FloatingPageToolsMotion.rise))
                    .animation(.easeOut(duration: FloatingPageToolsMotion.fadeDuration).delay(delay)),
                removal: AnyTransition.opacity.animation(quick)
            )
        }
    }
}

/// Icon-only label filling a floating tool's 44 × 44 pt circle (issues #92, #300, #632).
///
/// The frame and hit shape live inside the label so every button's hit region is the
/// full circle (menus there are buttons too, ``PageToolMenu``). HIG Buttons: "Minimum
/// hit region: 44x44 pt".
struct FloatingPageToolLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        // The system icon-only style keeps the title as the VoiceOver label.
        Label(configuration)
            .labelStyle(.iconOnly)
            .frame(width: FloatingPageToolsFit.slot, height: FloatingPageToolsFit.slot)
            .contentShape(Circle())
    }
}

// MARK: - Page scope

extension View {
    /// Mark this view as one page for the floating page tools: tools registered inside it
    /// show only while it is the front page. `FestivalTabStack` applies it to every tab
    /// root and pushed page.
    ///
    /// - Parameter inSelectedTab: The page's tab is the selected one; a page in another
    ///   tab never becomes the front page (``PageToolsRegistry/pageVisibilityChanged(_:onScreen:inSelectedTab:)``).
    /// - Returns: The page, scoped.
    func pageToolsScope(inSelectedTab: Bool) -> some View {
        modifier(PageToolsScopeModifier(inSelectedTab: inSelectedTab))
    }
}

/// Implementation of ``SwiftUICore/View/pageToolsScope(inSelectedTab:)``.
struct PageToolsScopeModifier: ViewModifier {
    let inSelectedTab: Bool
    @Environment(\.pageToolsRegistry) private var registry
    @State private var scope = UUID()
    @State private var onScreen = false
    /// The page's bottom edge in global points, measured outside the reserve.
    @State private var pageBottom: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .environment(\.pageToolsScope, scope)
            #if os(iOS)
            // Every page ends its content at the floating row (pattern
            // page-tools-and-nav-chrome R28), tools or not, so a push never moves it.
            .safeAreaPadding(.bottom, FloatingPageToolsFit.pageBottomReserve(
                pageBottom: pageBottom, floatingRowTop: registry?.floatingRowTop
            ))
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .global).maxY.rounded()
            } action: { pageBottom = $0 }
            #endif
            .onAppear {
                onScreen = true
                sync()
            }
            .onDisappear {
                onScreen = false
                sync()
            }
            .onChange(of: inSelectedTab) { _, _ in sync() }
            // Tools start floating without the page reappearing (#633).
            .onChange(of: registry == nil) { _, _ in sync() }
    }

    /// Report the page's visibility to the registry.
    private func sync() {
        registry?.pageVisibilityChanged(scope, onScreen: onScreen, inSelectedTab: inSelectedTab)
    }
}

// MARK: - Registration (pages)

extension View {
    /// Offer `tool` to the floating page tools while this page is visible (issues #92,
    /// #632).
    ///
    /// Does nothing where ``EnvironmentValues/pageToolsRegistry`` is nil, so callers keep
    /// their toolbar item for that case (`if pageTools == nil`). The tool is captured when
    /// registered and renders in the root's environment: pass a `token` covering every
    /// value it displays so a change re-registers it, and push routes through
    /// `\.pushRoute` rather than `NavigationLink` (the row is outside the stack).
    ///
    /// - Parameters:
    ///   - token: Changes whenever the tool's captured values change.
    ///   - order: Position in the row (``PageToolOrder``).
    ///   - isEnabled: False withdraws the tool without leaving the page.
    ///   - tool: The tool, normally a `Button` or `Menu` with an icon `Label`.
    /// - Returns: The view, registering its tool while visible.
    func festivalPageTool<Token: Hashable, Tool: View>(
        token: Token, order: Int, isEnabled: Bool = true,
        @ViewBuilder tool: @escaping () -> Tool
    ) -> some View {
        modifier(PageToolRegistration(token: token, order: order, isEnabled: isEnabled, tool: tool))
    }
}

/// Implementation of `festivalPageTool(token:order:isEnabled:tool:)`.
struct PageToolRegistration<Token: Hashable, Tool: View>: ViewModifier {
    let token: Token
    let order: Int
    let isEnabled: Bool
    let tool: () -> Tool
    @Environment(\.pageToolsRegistry) private var registry
    @Environment(\.pageToolsScope) private var scope
    @State private var id = UUID()
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                visible = true
                sync()
            }
            .onDisappear {
                visible = false
                registry?.remove(id: id)
            }
            .onChange(of: token) { _, _ in sync() }
            .onChange(of: isEnabled) { _, _ in sync() }
            .onChange(of: order) { _, _ in sync() }
            .onChange(of: registry == nil) { _, _ in sync() }
    }

    /// Register while visible and enabled; otherwise withdraw.
    private func sync() {
        guard let registry else { return }
        if visible && isEnabled {
            registry.upsert(id: id, scope: scope, order: order, content: AnyView(tool()))
        } else {
            registry.remove(id: id)
        }
    }
}
