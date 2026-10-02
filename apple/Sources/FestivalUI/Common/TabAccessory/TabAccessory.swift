import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Registry

/// The page tools shown above the iPhone tab bar (the web app's Songs search dock and
/// Sort / Quick Links FABs over the bottom nav).
///
/// Controls register while their page is visible (`onAppear` … `onDisappear`), so a
/// push or tab switch swaps them. On iOS 26.1+ the front page's tools fill the system
/// tab-bar bottom accessory, which moves inline beside the minimized tab bar while
/// scrolling (issue #42); earlier iOS floats them as separate glass buttons in
/// ``Entry/order``. Global Search and the profile avatar are header buttons instead
/// (operator, 2026-09-28).
///
/// Design rules: `.agents/design/apple/nav-accessories.md`.
@MainActor @Observable
final class TabAccessoryRegistry {
    /// One registered dock control.
    struct Entry {
        let id: UUID
        /// Position among the floating tools (lower first); see ``DockOrder``.
        var order: Int
        var content: AnyView
        /// Accessibility identifier re-applied by the host: the tab content's own
        /// `fst.nav.*` identifier otherwise overrides identifiers inside the inset.
        var accessibilityID: String?
        /// The page (`FloatingPageControls` instance) that owns this control.
        var scope: UUID?
        /// How the accessory lays the control out.
        var kind: DockItemKind = .tool
    }

    private(set) var entries: [Entry] = []
    /// Pages whose floating controls are on screen, in the order they appeared.
    private(set) var pageScopes: [UUID] = []

    /// The page controls to show after Search, in dock order (stable for equal orders).
    var items: [Entry] {
        entries.enumerated()
            .sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }
            .map(\.element)
    }

    /// The most recently registered control.
    var active: Entry? { entries.last }

    /// Add or replace a control, keeping its position when replacing.
    ///
    /// - Parameters:
    ///   - id: Stable identity of the registering view instance.
    ///   - order: Dock position after Search.
    ///   - content: Control content; it renders in the root's environment, so it must
    ///     not rely on page-only environment values.
    ///   - kind: How the tab-bar accessory lays the control out.
    func upsert(
        id: UUID, order: Int = DockOrder.pageAction, accessibilityID: String? = nil,
        scope: UUID? = nil, kind: DockItemKind = .tool, content: AnyView
    ) {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].content = content
            entries[index].order = order
            entries[index].accessibilityID = accessibilityID
            entries[index].scope = scope
            entries[index].kind = kind
        } else {
            entries.append(Entry(
                id: id, order: order, content: content, accessibilityID: accessibilityID,
                scope: scope, kind: kind
            ))
        }
    }

    /// The controls one page registered, in dock order.
    ///
    /// - Parameter scope: The page's `FloatingPageControls` scope.
    /// - Returns: Only that page's controls, so a push never shows two pages' buttons.
    func items(in scope: UUID) -> [Entry] {
        items.filter { $0.scope == scope }
    }

    /// The front page's controls, in dock order: what the tab-bar accessory shows.
    ///
    /// Empty when no page is on screen, so the accessory is withdrawn rather than
    /// showing an outgoing page's tools.
    var frontItems: [Entry] {
        guard let front = pageScopes.last else { return [] }
        return items(in: front)
    }

    /// A page started appearing (a push, a pop revealing it, or a tab switch).
    ///
    /// SwiftUI calls `onAppear` for the incoming page when a transition starts and
    /// `onDisappear` for the outgoing one only when it ends, so both pages are on screen
    /// in between. The most recently appeared page is the front one.
    ///
    /// - Parameter scope: The page's `FloatingPageControls` scope.
    func pageAppeared(_ scope: UUID) {
        pageScopes.removeAll { $0 == scope }
        pageScopes.append(scope)
    }

    /// A page finished disappearing.
    ///
    /// - Parameter scope: The page's `FloatingPageControls` scope.
    func pageDisappeared(_ scope: UUID) {
        pageScopes.removeAll { $0 == scope }
    }

    /// Whether a page is the front one, whose controls float. During a push or pop
    /// only the incoming page's controls show, so two pages' buttons never overlap
    /// over transparent pages; a cancelled interactive pop hands the controls back
    /// when the revealed page disappears again.
    ///
    /// - Parameter scope: The page's `FloatingPageControls` scope.
    /// - Returns: True for the most recently appeared page still on screen.
    func isFront(_ scope: UUID) -> Bool {
        pageScopes.last == scope
    }

    /// Remove a control (its page disappeared or no longer offers it).
    ///
    /// - Parameter id: Identity passed to ``upsert(id:order:content:)``.
    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }
}

/// Floating-control positions, leading to trailing (the trailing edge is nearest the thumb).
enum DockOrder {
    /// A page's search field (Songs), leading in the tab-bar accessory.
    static let search = 0
    /// Songs Filter.
    static let filter = 10
    /// Songs Sort.
    static let sort = 20
    /// Quick Links menu.
    static let quickLinks = 30
    /// Any other page control.
    static let pageAction = 40
}

/// How a registered control sits in the tab-bar accessory.
enum DockItemKind: Equatable, Sendable {
    /// An icon button with a 44 pt hit target (Filter, Sort, Quick Links).
    case tool
    /// A field-shaped button that takes the remaining width (Songs search).
    case field
}

/// Where a page's tools (search, Filter, Sort, Quick Links) live on this layout.
enum PageToolsPresentation: Equatable, Sendable {
    /// iOS 26.1+ iPhone: the system tab-bar bottom accessory, inline beside the
    /// minimized tab bar while scrolling (issue #42).
    case accessory
    /// iOS 17–26.0 iPhone: separate floating glass buttons above the tab bar, handed to
    /// the navigation bar while scrolling (issue #13).
    case floating

    /// Choose the presentation for a layout.
    ///
    /// - Parameters:
    ///   - horizontalTabBar: The section chrome is the bottom tab bar (iPhone, not the
    ///     iPhone Duo vertical bar, iPad sidebar or Mac).
    ///   - accessorySupported: The OS has `tabViewBottomAccessory(isEnabled:)` (26.1+).
    /// - Returns: Nil where the tools stay toolbar items.
    static func resolve(horizontalTabBar: Bool, accessorySupported: Bool) -> Self? {
        guard horizontalTabBar else { return nil }
        return accessorySupported ? .accessory : .floating
    }
}

extension EnvironmentValues {
    /// Set only where page controls sit above the tab bar: iPhone with a horizontal
    /// tab bar. Nil (the iPhone Duo vertical bar, iPad, Mac) means pages keep their
    /// controls as toolbar items.
    @Entry var tabAccessoryRegistry: TabAccessoryRegistry? = nil

    /// How the page tools above the tab bar are presented; nil with no registry.
    @Entry var pageToolsPresentation: PageToolsPresentation? = nil

    /// True when page controls (Filter/Sort, Quick Links) sit above the tab bar instead
    /// of in the toolbar.
    var isTabAccessoryAvailable: Bool { tabAccessoryRegistry != nil }

    /// Height the floating page tools take above the tab bar (0 when none), for trailing
    /// overlays such as the Songs A–Z scrubber that must end above them.
    @Entry var floatingControlsInset: CGFloat = 0

    /// The enclosing page's floating-controls scope; registrations are tagged with it.
    @Entry var floatingControlsScope: UUID? = nil
}

// MARK: - Host (root)

extension View {
    /// Publish the page-tools registry for this iPhone `TabView`.
    ///
    /// iOS 26.1+: the front page's tools fill the system tab-bar bottom accessory and the
    /// tab bar minimizes on scroll down, moving the accessory inline beside it (Music's
    /// MiniPlayer behavior, issue #42). Earlier iOS: each tab's `FestivalTabStack` floats
    /// them (`FloatingPageControls`). With the iPhone Duo vertical bar it publishes
    /// nothing, so pages keep toolbar items.
    ///
    /// - Returns: The tab view with the registry attached.
    func festivalTabAccessoryHost() -> some View {
        modifier(TabAccessoryHost())
    }
}

/// Implementation of ``SwiftUICore/View/festivalTabAccessoryHost()``.
struct TabAccessoryHost: ViewModifier {
    @State private var registry = TabAccessoryRegistry()
    @Environment(\.deviceLayout) private var layout

    func body(content: Content) -> some View {
        #if os(iOS)
        let horizontal = layout.sectionChrome == .tabBar
        if #available(iOS 26.1, *) {
            let items = registry.frontItems
            content
                .tabViewBottomAccessory(isEnabled: horizontal && !items.isEmpty) {
                    PageToolsAccessoryBar(items: items)
                }
                // HIG Tab bars (iOS): "scrolling down can minimize the bar and move the
                // accessory inline; tapping a tab or scrolling to the top exits."
                .tabBarMinimizeBehavior(horizontal ? .onScrollDown : .automatic)
                .environment(\.tabAccessoryRegistry, horizontal ? registry : nil)
                .environment(\.pageToolsPresentation, PageToolsPresentation.resolve(
                    horizontalTabBar: horizontal, accessorySupported: true
                ))
        } else {
            content
                .environment(\.tabAccessoryRegistry, horizontal ? registry : nil)
                .environment(\.pageToolsPresentation, PageToolsPresentation.resolve(
                    horizontalTabBar: horizontal, accessorySupported: false
                ))
        }
        #else
        content
        #endif
    }
}

// MARK: - Tab-bar accessory

/// The front page's tools inside the system tab-bar bottom accessory (iOS 26.1+): one
/// shared capsule, so every control stays a separate button with its own VoiceOver
/// label and a 44 pt hit target, and the field-shaped search takes the remaining width.
///
/// The accessory's height is fixed by the system, so text stops growing at
/// ``maxTypeSize``; long-pressing a control shows the Large Content Viewer instead.
struct PageToolsAccessoryBar: View {
    let items: [TabAccessoryRegistry.Entry]

    /// The largest Dynamic Type size the fixed-height accessory lays out.
    static let maxTypeSize = DynamicTypeSize.xxxLarge

    var body: some View {
        let arrangement = PageToolsAccessoryArrangement(kinds: items.map(\.kind))
        HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if arrangement.showsDivider(before: index) {
                    Divider()
                        .frame(height: 22)
                        .padding(.horizontal, 4)
                        .accessibilityHidden(true)
                }
                cell(item, spans: arrangement.spans(index))
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .font(.body)
        .tint(BrandTokens.textPrimary)
        .dynamicTypeSize(...Self.maxTypeSize)
    }

    @ViewBuilder
    private func cell(_ item: TabAccessoryRegistry.Entry, spans: Bool) -> some View {
        switch (item.kind, spans) {
        case (.field, _):
            // A field sets its own identifiers: one applied here would replace its
            // inner buttons' (open, clear).
            item.content
                .frame(maxWidth: .infinity, minHeight: 44)
        case (.tool, let spans):
            item.content
                .labelStyle(AccessoryToolLabelStyle(spans: spans))
                .frame(maxWidth: spans ? .infinity : nil)
                .accessibilityIdentifier(item.accessibilityID ?? "")
                .accessibilityShowsLargeContentViewer()
        }
    }
}

/// Lays out a tool's label inside the accessory with its hit area *inside* the label:
/// a frame applied outside a `Button` or `Menu` enlarges its layout but not what
/// responds to a tap.
struct AccessoryToolLabelStyle: LabelStyle {
    /// The tool fills the capsule with its icon and title (a page's only tool).
    let spans: Bool

    func makeBody(configuration: Configuration) -> some View {
        // The system styles keep the title as the accessibility label when it is hidden.
        Group {
            if spans {
                Label(configuration)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                Label(configuration)
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .contentShape(Rectangle())
    }
}

/// How ``PageToolsAccessoryBar`` lays out its controls (pure, unit-tested).
struct PageToolsAccessoryArrangement: Equatable {
    let kinds: [DockItemKind]

    /// Whether the control at `index` takes the remaining width: a field always does; a
    /// page's only tool (e.g. Quick Links on Song Detail) fills the capsule with its
    /// title so the bar never reads as an empty pill around one icon.
    ///
    /// - Parameter index: Control position in dock order.
    /// - Returns: True for a field, or for a lone tool.
    func spans(_ index: Int) -> Bool {
        guard kinds.indices.contains(index) else { return false }
        return kinds[index] == .field || kinds.count == 1
    }

    /// Whether a hairline separates the field from the tools after it, so the shared
    /// capsule reads as a search field plus separate buttons (HIG: distinct controls for
    /// distinct actions) rather than one search bar with attachments.
    ///
    /// - Parameter index: Control position in dock order.
    /// - Returns: True for the first tool after a field.
    func showsDivider(before index: Int) -> Bool {
        guard index > 0, kinds.indices.contains(index) else { return false }
        return kinds[index - 1] == .field && kinds[index] == .tool
    }
}

// MARK: - Floating controls

/// The visible page's controls as separate floating glass buttons, trailing-aligned
/// just above the tab bar (like the web's FABs). `FestivalTabStack` applies it to each
/// page inside the navigation stack: the page gets matching bottom safe-area padding
/// (lists scroll clear, trailing overlays such as the A–Z rail end above the buttons)
/// and the buttons are an overlay. (A `safeAreaInset` outside the stack was ignored by
/// the pages and let the tab's `fst.nav.*` identifier replace the buttons' own.)
struct FloatingPageControls: ViewModifier {
    @Environment(\.tabAccessoryRegistry) private var registry
    @Environment(\.pageToolsPresentation) private var presentation
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false
    /// This page's scope: only controls registered from inside it are shown here.
    @State private var scope = UUID()

    /// Diameter of one floating glass button, which is also its square hit region.
    static let buttonSize: CGFloat = 50
    /// Gap between neighbouring buttons; it keeps their hit regions apart.
    static let spacing: CGFloat = 12
    /// Button size plus its bottom margin.
    static let height: CGFloat = buttonSize + 8

    func body(content: Content) -> some View {
        // In the tab-bar accessory (iOS 26.1+) the system draws the tools and insets the
        // page; this only tracks which page is in front and tags its registrations.
        let items = presentation == .floating ? (registry?.items(in: scope) ?? []) : []
        // Only the front page draws its buttons (see `TabAccessoryRegistry.isFront`);
        // the inset stays so an outgoing page's layout does not jump mid-transition.
        let front = registry?.isFront(scope) ?? false
        let style = PageToolsHandOff.style(
            systemReduceMotion: systemReduceMotion, appReduceMotion: appReduceMotion
        )
        content
            .environment(\.floatingControlsScope, scope)
            .environment(\.floatingControlsInset, items.isEmpty ? 0 : Self.height)
            .safeAreaPadding(.bottom, items.isEmpty ? 0 : Self.height)
            .onAppear { registry?.pageAppeared(scope) }
            .onDisappear { registry?.pageDisappeared(scope) }
            .animation(.easeInOut(duration: 0.15), value: front)
            .overlay(alignment: .bottomTrailing) {
                ZStack(alignment: .bottomTrailing) {
                    if !items.isEmpty && front {
                        FestivalGlassGroup(spacing: Self.spacing) {
                            HStack(spacing: Self.spacing) {
                                ForEach(items, id: \.id) { item in
                                    item.content
                                        .labelStyle(FloatingPageToolLabelStyle(side: Self.buttonSize))
                                        .font(.title3)
                                        .frame(width: Self.buttonSize, height: Self.buttonSize)
                                        .contentShape(Rectangle())
                                        .festivalGlassCapsule(.control, interactive: true)
                                        .accessibilityIdentifier(item.accessibilityID ?? "")
                                        .transition(PageToolsHandOff.dockTransition(style))
                                }
                            }
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 8)
                        .transition(PageToolsHandOff.dockTransition(style))
                    }
                }
                // Registrations change outside the scroll hand-off's transaction, so the
                // dock animates its own half with the same timing (issue #13); scoped to
                // the overlay so the page itself never animates with it.
                .animation(PageToolsHandOff.animation(style), value: items.map(\.id))
            }
    }
}

// MARK: - Floating tool label

/// Icon-only label that fills a floating page tool's whole square (issue #15).
///
/// A `Menu` (Quick Links) only responds to taps on its label, so the frame and hit
/// shape around the glyph must live *inside* the label: the glass circle drawn around
/// it is not tappable. Buttons honour the outer frame too; using one style keeps every
/// floating tool's hit region the same square. HIG Buttons: "As a general rule, the hit
/// region is at least 44x44 pt"; ``FloatingPageControls/spacing`` keeps neighbours apart.
struct FloatingPageToolLabelStyle: LabelStyle {
    /// Side of the square hit region, in points.
    let side: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        // The system icon-only style keeps the title as the VoiceOver label.
        Label(configuration)
            .labelStyle(.iconOnly)
            .frame(width: side, height: side)
            .contentShape(Rectangle())
    }
}

// MARK: - Registration (pages)

extension View {
    /// Offer `accessory` to the bottom dock while this view is visible.
    ///
    /// Does nothing where ``EnvironmentValues/isTabAccessoryAvailable`` is false, so
    /// callers pair it with a toolbar fallback. The content is captured when registered;
    /// pass a `token` covering every value it displays so changes re-register it
    /// (bindings and `@Observable` reads stay live on their own).
    ///
    /// - Parameters:
    ///   - token: Changes whenever the control's captured values change.
    ///   - order: Dock position after Search (``DockOrder``).
    ///   - accessibilityID: Identifier the host re-applies to the control.
    ///   - kind: How the tab-bar accessory lays the control out.
    ///   - isEnabled: False withdraws the control without leaving the page.
    ///   - accessory: Control content (rendered in the root's environment).
    /// - Returns: The view, registering its control while visible.
    func festivalTabAccessory<Token: Hashable, Accessory: View>(
        token: Token, order: Int = DockOrder.pageAction, accessibilityID: String? = nil,
        kind: DockItemKind = .tool,
        isEnabled: Bool = true, @ViewBuilder accessory: @escaping () -> Accessory
    ) -> some View {
        modifier(TabAccessoryRegistration(
            token: token, order: order, accessibilityID: accessibilityID, kind: kind,
            isEnabled: isEnabled, accessory: accessory
        ))
    }
}

/// Implementation of `festivalTabAccessory(token:order:isEnabled:accessory:)`.
struct TabAccessoryRegistration<Token: Hashable, Accessory: View>: ViewModifier {
    let token: Token
    let order: Int
    let accessibilityID: String?
    let kind: DockItemKind
    let isEnabled: Bool
    let accessory: () -> Accessory
    @Environment(\.tabAccessoryRegistry) private var registry
    @Environment(\.floatingControlsScope) private var scope
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
            .onChange(of: registry == nil) { _, _ in sync() }
    }

    /// Register while visible and enabled; otherwise withdraw.
    private func sync() {
        guard let registry else { return }
        if visible && isEnabled {
            registry.upsert(
                id: id, order: order, accessibilityID: accessibilityID, scope: scope,
                kind: kind, content: AnyView(accessory())
            )
        } else {
            registry.remove(id: id)
        }
    }
}
