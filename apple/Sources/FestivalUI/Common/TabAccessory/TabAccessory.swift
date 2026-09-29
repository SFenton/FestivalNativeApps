import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Registry

/// The page controls currently floating above the iPhone tab bar (the web app's
/// Sort / Quick Links FABs over the bottom nav).
///
/// Controls register while their page is visible (`onAppear` … `onDisappear`), so a
/// push or tab switch swaps them; they float as separate glass buttons in
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
    func upsert(
        id: UUID, order: Int = DockOrder.pageAction, accessibilityID: String? = nil,
        scope: UUID? = nil, content: AnyView
    ) {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].content = content
            entries[index].order = order
            entries[index].accessibilityID = accessibilityID
            entries[index].scope = scope
        } else {
            entries.append(Entry(
                id: id, order: order, content: content, accessibilityID: accessibilityID,
                scope: scope
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
    /// Songs Filter.
    static let filter = 10
    /// Songs Sort.
    static let sort = 20
    /// Quick Links menu.
    static let quickLinks = 30
    /// Any other page control.
    static let pageAction = 40
}

extension EnvironmentValues {
    /// Set only where page controls float above the tab bar: iPhone with a horizontal
    /// tab bar. Nil (the iPhone Duo vertical bar, iPad, Mac) means pages keep their
    /// controls as toolbar items.
    @Entry var tabAccessoryRegistry: TabAccessoryRegistry? = nil

    /// True when page controls (Filter/Sort, Quick Links) float above the tab bar instead
    /// of sitting in the toolbar.
    var isTabAccessoryAvailable: Bool { tabAccessoryRegistry != nil }

    /// Height the floating page tools take above the tab bar (0 when none), for trailing
    /// overlays such as the Songs A–Z scrubber that must end above them.
    @Entry var floatingControlsInset: CGFloat = 0

    /// The enclosing page's floating-controls scope; registrations are tagged with it.
    @Entry var floatingControlsScope: UUID? = nil
}

// MARK: - Host (root)

extension View {
    /// Publish the floating-controls registry for this iPhone `TabView`.
    ///
    /// Each tab's `FestivalTabStack` draws the registered controls (`FloatingPageControls`).
    /// With the iPhone Duo vertical bar it publishes nothing, so pages keep toolbar items.
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
        content.environment(\.tabAccessoryRegistry, layout.sectionChrome == .tabBar ? registry : nil)
        #else
        content
        #endif
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
    /// This page's scope: only controls registered from inside it are shown here.
    @State private var scope = UUID()

    /// Button size plus its bottom margin.
    static let height: CGFloat = 50 + 8

    func body(content: Content) -> some View {
        let items = registry?.items(in: scope) ?? []
        // Only the front page draws its buttons (see `TabAccessoryRegistry.isFront`);
        // the inset stays so an outgoing page's layout does not jump mid-transition.
        let front = registry?.isFront(scope) ?? false
        content
            .environment(\.floatingControlsScope, scope)
            .environment(\.floatingControlsInset, items.isEmpty ? 0 : Self.height)
            .safeAreaPadding(.bottom, items.isEmpty ? 0 : Self.height)
            .onAppear { registry?.pageAppeared(scope) }
            .onDisappear { registry?.pageDisappeared(scope) }
            .animation(.easeInOut(duration: 0.15), value: front)
            .overlay(alignment: .bottomTrailing) {
                if !items.isEmpty && front {
                    FestivalGlassGroup(spacing: 12) {
                        HStack(spacing: 12) {
                            ForEach(items, id: \.id) { item in
                                item.content
                                    .labelStyle(.iconOnly)
                                    .font(.title3)
                                    .frame(width: 50, height: 50)
                                    .contentShape(Circle())
                                    .festivalGlassCapsule(.control, interactive: true)
                                    .accessibilityIdentifier(item.accessibilityID ?? "")
                            }
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 8)
                    .transition(.opacity)
                }
            }
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
    ///   - isEnabled: False withdraws the control without leaving the page.
    ///   - accessory: Control content (rendered in the root's environment).
    /// - Returns: The view, registering its control while visible.
    func festivalTabAccessory<Token: Hashable, Accessory: View>(
        token: Token, order: Int = DockOrder.pageAction, accessibilityID: String? = nil,
        isEnabled: Bool = true, @ViewBuilder accessory: @escaping () -> Accessory
    ) -> some View {
        modifier(TabAccessoryRegistration(
            token: token, order: order, accessibilityID: accessibilityID,
            isEnabled: isEnabled, accessory: accessory
        ))
    }
}

/// Implementation of `festivalTabAccessory(token:order:isEnabled:accessory:)`.
struct TabAccessoryRegistration<Token: Hashable, Accessory: View>: ViewModifier {
    let token: Token
    let order: Int
    let accessibilityID: String?
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
                content: AnyView(accessory())
            )
        } else {
            registry.remove(id: id)
        }
    }
}
