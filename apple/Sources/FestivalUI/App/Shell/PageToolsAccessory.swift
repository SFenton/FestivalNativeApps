import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Order

/// Positions of a page's tools in the tab-bar accessory, leading to trailing (issue #92).
///
/// The page's own actions come first in the page's order (Songs: Sort, then Filter),
/// then Quick Links. Notifications (a profile is selected) is drawn by the accessory
/// itself, pinned to its trailing edge; Profile is the navigation bar's trailing-most
/// item (issue #300).
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

/// The front page's tools for the iPhone tab-bar accessory (issue #92).
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
        /// Position in the accessory (``PageToolOrder``); equal orders keep registration order.
        var order: Int
        /// The tool, rendered in the root's environment.
        var content: AnyView
    }

    private(set) var entries: [Entry] = []
    /// Pages on screen, in the order they appeared; the last is the front page.
    private(set) var pageScopes: [UUID] = []
    /// The tab view's measured width (0 before it is laid out). Unlike the accessory's
    /// own width it does not change while the system morphs the accessory between
    /// expanded and inline, so fit decisions made from it stay put (issue #300).
    private(set) var windowWidth: CGFloat = 0
    /// A page-tool menu shown as a sheet because it sits in the accessory
    /// (``PageToolMenu``); the host presents it.
    var inlineMenu: PageToolInlineMenu?
    /// The choice picked in ``inlineMenu``, run once its sheet has gone.
    private var pendingChoice: (() -> Void)?

    /// Add or replace a tool, keeping its position when replacing.
    ///
    /// - Parameters:
    ///   - id: Stable identity of the registering view instance.
    ///   - scope: The registering page's scope.
    ///   - order: Position in the accessory.
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

    /// The front page's tools in accessory order; empty when no page is on screen.
    var frontItems: [Entry] {
        guard let front = pageScopes.last else { return [] }
        return entries.enumerated()
            .filter { $0.element.scope == front }
            .sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }
            .map(\.element)
    }

    /// Whether the accessory has anything to show: the front page's tools, or
    /// Notifications for a selected profile. An empty accessory is hidden rather than
    /// drawn as an empty capsule (issue #300).
    ///
    /// - Parameter hasPlayer: A profile is selected (the accessory shows Notifications).
    /// - Returns: True when the accessory should be enabled.
    func hasContent(hasPlayer: Bool) -> Bool {
        hasPlayer || !frontItems.isEmpty
    }

    /// Record the tab view's width, skipping identical reports so observers are not
    /// invalidated on every layout pass.
    ///
    /// - Parameter width: Its width in points.
    func reportWindow(width: CGFloat) {
        if windowWidth != width { windowWidth = width }
    }

    /// Show a page-tool menu as a sheet (a `Menu` in the accessory is unreliable).
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

/// A page-tool menu presented as a sheet from the tab-bar accessory (issue #92).
struct PageToolInlineMenu: Identifiable {
    let id = UUID()
    /// The sheet's title (the menu's name).
    let title: String
    /// The choices, in menu order.
    let choices: [PageToolMenuChoice]
}

/// A page tool's `Menu` that works in the tab-bar accessory (issue #92).
///
/// In the bottom accessory iOS 26 does not open a `Menu` while the accessory sits inline
/// beside the minimized tab bar, and when expanded the menu answers only near its glyph
/// rather than across its 44 pt slot (buttons do both). So in the accessory the tool is a
/// button with the same label that lists `choices` in a compact sheet the root presents,
/// the same whether or not the tab bar is minimized; elsewhere (navigation bars, Mac) it
/// is the ordinary `Menu`. Modifiers applied to it (identifier, accessibility label and
/// value, tint) apply to either form.
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

    var body: some View {
        #if os(iOS)
        if #available(iOS 26.1, *) {
            PlacementAwarePageToolMenu(menu: self)
        } else {
            Menu(content: content, label: label)
        }
        #else
        Menu(content: content, label: label)
        #endif
    }
}

#if os(iOS)
/// ``PageToolMenu`` reading the accessory placement (iOS 26.1+).
@available(iOS 26.1, *)
private struct PlacementAwarePageToolMenu<MenuContent: View, MenuLabel: View>: View {
    let menu: PageToolMenu<MenuContent, MenuLabel>
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(\.pageToolsRegistry) private var registry

    var body: some View {
        // `placement` is nil outside the accessory (navigation bars).
        if placement != nil, let registry {
            Button {
                registry.presentInlineMenu(title: menu.title, choices: menu.choices())
            } label: {
                menu.label()
            }
        } else {
            Menu(content: menu.content, label: menu.label)
        }
    }
}
#endif

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

/// Fixed slot layout and fold rule for the tab-bar accessory (pure, unit-tested; issues
/// #92, #300).
///
/// Every item has a fixed 44 pt slot (HIG Buttons: "the hit region is at least 44x44
/// pt"): page tools from the leading edge, Notifications pinned to the trailing edge
/// after a divider. Slots never stretch to share the width, so a push, pop or tab switch
/// only swaps the page tools and Notifications never moves.
///
/// The fold decision never reads the accessory's live width. The system morphs the
/// accessory between expanded (window − 54 pt) and inline beside the minimized tab bar
/// (window − 180 pt; 222 pt on a 402 pt iPhone 17 Pro, 260 pt on a 440 pt Pro Max,
/// measured 2026-10-04), and swapping items mid-morph was the jitter of issue #300.
/// Instead a page folds (Songs: Sort and Filter into one "Sort and Filter") only when
/// its items would not fit the *inline* width for this window, or at accessibility text
/// sizes, so the expanded and inline accessory always show the same items. Quick Links
/// and Notifications always stay visible (HIG Toolbars, iOS: "Put only essential actions
/// in the main area; use More for the rest").
enum PageToolsAccessoryFit {
    /// Width of one item's slot, which is also its hit target.
    static let slot: CGFloat = 44
    /// Width of the hairline divider before Notifications (the 44 pt slots either side
    /// already give it clear space).
    static let divider: CGFloat = 1
    /// Leading plus trailing padding inside the accessory capsule.
    static let padding: CGFloat = 12
    /// How much narrower than the window the inline accessory capsule is (the minimized
    /// tab bar, the Search tab button and the margins; measured on iOS 26.5).
    static let inlineInset: CGFloat = 180

    /// Content width the items need, excluding ``padding``.
    ///
    /// - Parameters:
    ///   - pageTools: Page actions plus Quick Links.
    ///   - showsBell: Notifications shows (a profile is selected).
    /// - Returns: The minimum content width in points.
    static func requiredWidth(pageTools: Int, showsBell: Bool) -> CGFloat {
        let tools = CGFloat(max(0, pageTools)) * slot
        guard showsBell else { return tools }
        return tools + (pageTools > 0 ? divider : 0) + slot
    }

    /// The inline accessory's content width for a window (capsule minus ``padding``):
    /// 210 pt on a 402 pt iPhone, 183 pt on a 375 pt one.
    ///
    /// - Parameter windowWidth: The tab view's width.
    /// - Returns: Its content width in points, never negative.
    static func inlineWidth(windowWidth: CGFloat) -> CGFloat {
        max(0, windowWidth - inlineInset - padding)
    }

    /// Whether the page folds its secondary actions into one menu, the same expanded and
    /// inline.
    ///
    /// - Parameters:
    ///   - windowWidth: The tab view's width; zero (not yet measured) never folds on
    ///     width alone.
    ///   - pageTools: Unfolded page actions plus Quick Links.
    ///   - showsBell: Notifications shows (a profile is selected).
    ///   - dynamicTypeSize: Current text size; accessibility sizes always fold.
    /// - Returns: True to fold.
    static func folds(
        windowWidth: CGFloat, pageTools: Int, showsBell: Bool, dynamicTypeSize: DynamicTypeSize
    ) -> Bool {
        if dynamicTypeSize.isAccessibilitySize { return true }
        guard windowWidth > 0 else { return false }
        return inlineWidth(windowWidth: windowWidth) < requiredWidth(pageTools: pageTools, showsBell: showsBell)
    }
}

// MARK: - Environment

extension EnvironmentValues {
    /// Set only where page tools live in the iPhone tab-bar accessory (iOS 26.1+,
    /// horizontal tab bar). Nil (older iOS, the iPhone Duo vertical bar, iPad, Mac)
    /// means pages keep their tools as navigation-bar items.
    @Entry var pageToolsRegistry: PageToolsRegistry? = nil

    /// The enclosing page's scope; tool registrations are tagged with it.
    @Entry var pageToolsScope: UUID? = nil
}

// MARK: - Host (root)

extension View {
    /// Host the page-tools accessory on the iPhone root `TabView` (issue #92).
    ///
    /// iOS 26.1+ with a horizontal tab bar: the front page's tools (``PageToolsRegistry``)
    /// and Notifications sit in the system tab-bar bottom accessory, which moves
    /// inline beside the tab bar when scrolling minimizes it (HIG Tab bars: "With an
    /// attached accessory such as Music's MiniPlayer, scrolling down can minimize the
    /// bar and move the accessory inline"). Elsewhere it publishes nothing, so pages keep
    /// their navigation-bar items.
    ///
    /// The accessory hides while it has nothing to show (no profile and a page without
    /// tools; ``PageToolsRegistry/hasContent(hasPlayer:)``).
    ///
    /// - Parameter isEnabled: False hides the accessory (the Search tab is open).
    /// - Returns: The tab view with the accessory attached.
    func festivalPageToolsAccessory(isEnabled: Bool) -> some View {
        modifier(PageToolsAccessoryHost(isEnabled: isEnabled))
    }

    /// Keeps a nested tab view (a picture of the tab bar, such as the first-run Navigation
    /// demo) free of the shell's page-tools accessory, which nested tab views inherit on
    /// iOS 26.1 (issue #380).
    ///
    /// - Returns: The tab view with no bottom accessory.
    @ViewBuilder
    func festivalPageToolsAccessoryHidden() -> some View {
        #if os(iOS)
        if #available(iOS 26.1, *) {
            tabViewBottomAccessory(isEnabled: false) { EmptyView() }
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// Implementation of ``SwiftUICore/View/festivalPageToolsAccessory(isEnabled:)``.
struct PageToolsAccessoryHost: ViewModifier {
    let isEnabled: Bool

    /// Whether the window hosts the page-tools accessory: a horizontal tab bar in a
    /// compact-width window (iPhone, compact iPad windows).
    ///
    /// The iPhone Duo inner display in portrait also has a horizontal tab bar, but at
    /// regular width with a list/detail split: there the accessory showed only
    /// Notifications while every page (Song Detail's Item Shop and Paths included)
    /// handed its tools to it, so they vanished. Regular-width windows keep their
    /// navigation-bar items, as the vertical bar and the iPad sidebar do.
    ///
    /// - Parameter layout: The window's published layout.
    /// - Returns: True for a compact-width horizontal tab bar.
    nonisolated static func hostsAccessory(in layout: DeviceLayout) -> Bool {
        layout.sectionChrome == .tabBar && layout.windowWidthClass == .compact
    }
    @State private var registry = PageToolsRegistry()
    @Environment(\.deviceLayout) private var layout
    @Environment(\.festivalSession) private var session

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.1, *) {
            // One branch for both chromes, so a chrome change never rebuilds the tabs.
            let horizontal = Self.hostsAccessory(in: layout)
            let hasContent = registry.hasContent(hasPlayer: session?.selectedPlayer != nil)
            content
                // The tab view's width does not change while the accessory morphs.
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                    registry.reportWindow(width: width)
                }
                .tabViewBottomAccessory(isEnabled: horizontal && isEnabled && hasContent) {
                    PageToolsAccessoryBar(registry: registry)
                        .environment(\.pageToolsRegistry, registry)
                }
                // A sheet attached inside the accessory never presents, so the root does.
                .sheet(item: Bindable(registry).inlineMenu, onDismiss: registry.inlineMenuDismissed) { menu in
                    PageToolInlineMenuSheet(menu: menu, registry: registry)
                }
                .environment(\.pageToolsRegistry, horizontal ? registry : nil)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// MARK: - Accessory bar

#if os(iOS)
/// The tab-bar accessory's contents: the front page's tools from the leading edge, then
/// a divider and Notifications (a profile is selected) pinned to the trailing edge.
/// Profile is the navigation bar's trailing-most item instead (issue #300).
///
/// Every item has a fixed 44 × 44 pt slot (``PageToolsAccessoryFit``,
/// ``PageToolsAccessoryLabelStyle``), so items never redistribute when a page with a
/// different number of tools comes to the front, and the expanded and inline accessory
/// show the same items. The accessory's height is fixed by the system, so text stops
/// growing at ``maxTypeSize``; long-pressing an item shows the Large Content Viewer
/// instead. VoiceOver reads the items left to right.
@available(iOS 26.1, *)
struct PageToolsAccessoryBar: View {
    let registry: PageToolsRegistry
    @Environment(\.festivalSession) private var session
    @Environment(\.openNotifications) private var openNotifications
    @Environment(\.pushRoute) private var pushRoute

    /// The largest Dynamic Type size the fixed-height accessory lays out.
    static let maxTypeSize = DynamicTypeSize.xxxLarge

    var body: some View {
        let tools = registry.frontItems
        HStack(spacing: 0) {
            ForEach(tools) { item in
                item.content
                    .frame(width: PageToolsAccessoryFit.slot)
                    .frame(maxHeight: .infinity)
                    .accessibilityShowsLargeContentViewer()
            }
            Spacer(minLength: 0)
            if let session, session.selectedPlayer != nil {
                if !tools.isEmpty {
                    Divider()
                        .frame(height: 24)
                        .frame(width: PageToolsAccessoryFit.divider)
                        .accessibilityHidden(true)
                }
                // The root presents the sheet: one attached in the accessory never shows.
                NotificationsButton(
                    session: session, pushRoute: pushRoute,
                    open: openNotifications.map { action in { action() } },
                    drawsBadgeOnIcon: true
                )
                    .frame(width: PageToolsAccessoryFit.slot)
                    .frame(maxHeight: .infinity)
                    .accessibilityShowsLargeContentViewer()
            }
        }
        .labelStyle(PageToolsAccessoryLabelStyle())
        .padding(.horizontal, PageToolsAccessoryFit.padding / 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .font(.body)
        .tint(BrandTokens.textPrimary)
        .dynamicTypeSize(...Self.maxTypeSize)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Page Tools")
        .accessibilityIdentifier("fst.page-tools")
    }
}
#endif

/// Icon-only label that fills its fixed 44 × 44 pt accessory slot (issues #92, #300).
///
/// The frame and hit shape live inside the label so every button's hit region is the
/// full slot (menus in the accessory are buttons too, ``PageToolMenu``). HIG Buttons:
/// "the hit region is at least 44x44 pt".
struct PageToolsAccessoryLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        // The system icon-only style keeps the title as the VoiceOver label.
        Label(configuration)
            .labelStyle(.iconOnly)
            .frame(width: PageToolsAccessoryFit.slot)
            .frame(minHeight: PageToolsAccessoryFit.slot, maxHeight: .infinity)
            .contentShape(Rectangle())
    }
}

// MARK: - Page scope

extension View {
    /// Mark this view as one page for the tab-bar accessory: tools registered inside it
    /// show only while it is the front page. `FestivalTabStack` applies it to every tab
    /// root and pushed page.
    ///
    /// - Returns: The page, scoped.
    func pageToolsScope() -> some View {
        modifier(PageToolsScopeModifier())
    }
}

/// Implementation of ``SwiftUICore/View/pageToolsScope()``.
struct PageToolsScopeModifier: ViewModifier {
    @Environment(\.pageToolsRegistry) private var registry
    @State private var scope = UUID()

    func body(content: Content) -> some View {
        content
            .environment(\.pageToolsScope, scope)
            .onAppear { registry?.pageAppeared(scope) }
            .onDisappear { registry?.pageDisappeared(scope) }
    }
}

// MARK: - Registration (pages)

extension View {
    /// Offer `tool` to the tab-bar accessory while this page is visible (issue #92).
    ///
    /// Does nothing where ``EnvironmentValues/pageToolsRegistry`` is nil, so callers keep
    /// their toolbar item for that case (`if pageTools == nil`). The tool is captured when
    /// registered and renders in the root's environment: pass a `token` covering every
    /// value it displays so a change re-registers it, and push routes through
    /// `\.pushRoute` rather than `NavigationLink` (the accessory is outside the stack).
    ///
    /// - Parameters:
    ///   - token: Changes whenever the tool's captured values change.
    ///   - order: Position in the accessory (``PageToolOrder``).
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
