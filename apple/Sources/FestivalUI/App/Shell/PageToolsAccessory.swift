import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Order

/// Positions of a page's tools in the tab-bar accessory, leading to trailing (issue #92).
///
/// The page's own actions come first in the page's order (Songs: Sort, then Filter),
/// then Quick Links. The account group (Notifications, Profile) always follows them and
/// is drawn by the accessory itself, so Profile is always the trailing-most item.
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
    /// The accessory's measured width (0 before it is laid out).
    private(set) var accessoryWidth: CGFloat = 0
    /// Whether the accessory sits inline beside the minimized tab bar.
    private(set) var isInline = false
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

    /// Record the accessory's layout, skipping identical reports so observers are not
    /// invalidated on every layout pass.
    ///
    /// - Parameters:
    ///   - width: Its width in points.
    ///   - inline: It sits inline beside the minimized tab bar.
    func reportAccessory(width: CGFloat, inline: Bool) {
        if accessoryWidth != width { accessoryWidth = width }
        if isInline != inline { isInline = inline }
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

/// Whether a page's tools fit the tab-bar accessory unfolded (pure, unit-tested; issue #92).
///
/// Every item keeps at least a 44 pt hit target (HIG Buttons: "the hit region is at
/// least 44x44 pt"). When the accessory is too narrow for all of them (inline beside the
/// minimized tab bar, or a small iPhone) or text is at an accessibility size, a page
/// folds its secondary actions into one menu (Songs: "Sort and Filter"); Quick Links,
/// Notifications and Profile always stay visible (HIG Toolbars, iOS: "Put only essential
/// actions in the main area; use More for the rest").
enum PageToolsAccessoryFit {
    /// Minimum width of one item's hit target.
    static let slot: CGFloat = 44
    /// Gap between neighbouring items.
    static let spacing: CGFloat = 4
    /// Width the divider between the page tools and the account group takes.
    static let divider: CGFloat = 1
    /// Leading plus trailing padding inside the accessory capsule.
    static let padding: CGFloat = 12

    /// Width all items need unfolded.
    ///
    /// - Parameters:
    ///   - pageTools: Page actions plus Quick Links.
    ///   - accountItems: Notifications (when shown) plus Profile.
    /// - Returns: The minimum accessory width in points.
    static func requiredWidth(pageTools: Int, accountItems: Int) -> CGFloat {
        let tools = max(0, pageTools)
        let account = max(0, accountItems)
        let items = tools + account
        let dividers = tools > 0 && account > 0 ? 1 : 0
        let gaps = max(0, items + dividers - 1)
        return CGFloat(items) * slot + CGFloat(dividers) * divider
            + CGFloat(gaps) * spacing + padding
    }

    /// Whether the page folds its secondary actions into one menu.
    ///
    /// - Parameters:
    ///   - width: The accessory's measured width; zero (not yet measured) never folds
    ///     on width alone.
    ///   - pageTools: Unfolded page actions plus Quick Links.
    ///   - accountItems: Notifications (when shown) plus Profile.
    ///   - dynamicTypeSize: Current text size; accessibility sizes always fold.
    /// - Returns: True to fold.
    static func folds(
        width: CGFloat, pageTools: Int, accountItems: Int, dynamicTypeSize: DynamicTypeSize
    ) -> Bool {
        if dynamicTypeSize.isAccessibilitySize { return true }
        return width > 0 && width < requiredWidth(pageTools: pageTools, accountItems: accountItems)
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
    /// and the account group sit in the system tab-bar bottom accessory, which moves
    /// inline beside the tab bar when scrolling minimizes it (HIG Tab bars: "With an
    /// attached accessory such as Music's MiniPlayer, scrolling down can minimize the
    /// bar and move the accessory inline"). Elsewhere it publishes nothing, so pages keep
    /// their navigation-bar items.
    ///
    /// - Parameter isEnabled: False hides the accessory (the Search tab is open).
    /// - Returns: The tab view with the accessory attached.
    func festivalPageToolsAccessory(isEnabled: Bool) -> some View {
        modifier(PageToolsAccessoryHost(isEnabled: isEnabled))
    }
}

/// Implementation of ``SwiftUICore/View/festivalPageToolsAccessory(isEnabled:)``.
struct PageToolsAccessoryHost: ViewModifier {
    let isEnabled: Bool
    @State private var registry = PageToolsRegistry()
    @Environment(\.deviceLayout) private var layout

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.1, *) {
            // One branch for both chromes, so a chrome change never rebuilds the tabs.
            let horizontal = layout.sectionChrome == .tabBar
            content
                .tabViewBottomAccessory(isEnabled: horizontal && isEnabled) {
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
/// The tab-bar accessory's contents: the front page's tools, a divider, then
/// Notifications (a profile is selected) and Profile, always the trailing-most item.
///
/// Items share the width evenly; each label fills its slot (``PageToolsAccessoryLabelStyle``)
/// so the whole slot, at least 44×44 pt, is the hit target. The accessory's height is
/// fixed by the system, so text stops growing at ``maxTypeSize``; long-pressing an item
/// shows the Large Content Viewer instead. VoiceOver reads the items left to right.
@available(iOS 26.1, *)
struct PageToolsAccessoryBar: View {
    let registry: PageToolsRegistry
    @Environment(\.festivalSession) private var session
    @Environment(\.openProfile) private var openProfile
    @Environment(\.openNotifications) private var openNotifications
    @Environment(\.pushRoute) private var pushRoute
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    /// The largest Dynamic Type size the fixed-height accessory lays out.
    static let maxTypeSize = DynamicTypeSize.xxxLarge

    var body: some View {
        let tools = registry.frontItems
        let inline = placement == .inline
        HStack(spacing: PageToolsAccessoryFit.spacing) {
            ForEach(tools) { item in
                item.content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityShowsLargeContentViewer()
            }
            if !tools.isEmpty, session != nil {
                Divider()
                    .frame(height: 24)
                    .accessibilityHidden(true)
            }
            if let session {
                if session.selectedPlayer != nil {
                    // The root presents the sheet: one attached in the accessory never shows.
                    NotificationsButton(
                        session: session, pushRoute: pushRoute,
                        open: openNotifications.map { action in { action() } },
                        drawsBadgeOnIcon: true
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityShowsLargeContentViewer()
                }
                RootProfileButton(session: session) { openProfile() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            registry.reportAccessory(width: width, inline: inline)
        }
        .onChange(of: inline) { _, now in
            registry.reportAccessory(width: registry.accessoryWidth, inline: now)
        }
    }
}
#endif

/// Icon-only label that fills its accessory slot, at least 44×44 pt (issue #92).
///
/// The frame and hit shape live inside the label so every button's hit region is the
/// full slot (menus in the accessory are buttons too, ``PageToolMenu``). HIG Buttons:
/// "the hit region is at least 44x44 pt".
struct PageToolsAccessoryLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        // The system icon-only style keeps the title as the VoiceOver label.
        Label(configuration)
            .labelStyle(.iconOnly)
            .frame(
                minWidth: PageToolsAccessoryFit.slot, maxWidth: .infinity,
                minHeight: PageToolsAccessoryFit.slot, maxHeight: .infinity
            )
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
