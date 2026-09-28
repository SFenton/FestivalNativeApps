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
        /// Position within the dock after Search (lower first); see ``DockOrder``.
        var order: Int
        var content: AnyView
    }

    private(set) var entries: [Entry] = []

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
    func upsert(id: UUID, order: Int = DockOrder.pageAction, content: AnyView) {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].content = content
            entries[index].order = order
        } else {
            entries.append(Entry(id: id, order: order, content: content))
        }
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
/// just above the tab bar (like the web's FABs). Applied by `FestivalTabStack` as a
/// bottom `safeAreaInset`, so lists scroll clear of them and page-owned bottom bars
/// (e.g. the Full Rankings pager) stack above them instead of overlapping.
struct FloatingPageControls: ViewModifier {
    @Environment(\.tabAccessoryRegistry) private var registry

    /// Button size plus its bottom margin.
    static let height: CGFloat = 50 + 8

    func body(content: Content) -> some View {
        let hasItems = !(registry?.items.isEmpty ?? true)
        content
            .environment(\.floatingControlsInset, hasItems ? Self.height : 0)
            .safeAreaInset(edge: .bottom, spacing: 0) {
            if let registry, !registry.items.isEmpty {
                FestivalGlassGroup(spacing: 12) {
                    HStack(spacing: 12) {
                        Spacer(minLength: 0)
                        ForEach(registry.items, id: \.id) { item in
                            item.content
                                .labelStyle(.iconOnly)
                                .font(.title3)
                                .frame(width: 50, height: 50)
                                .contentShape(Circle())
                                .festivalGlassCapsule(.control, interactive: true)
                        }
                    }
                }
                .padding(.horizontal, 16)
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
        token: Token, order: Int = DockOrder.pageAction, isEnabled: Bool = true,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) -> some View {
        modifier(TabAccessoryRegistration(
            token: token, order: order, isEnabled: isEnabled, accessory: accessory
        ))
    }
}

/// Implementation of `festivalTabAccessory(token:order:isEnabled:accessory:)`.
struct TabAccessoryRegistration<Token: Hashable, Accessory: View>: ViewModifier {
    let token: Token
    let order: Int
    let isEnabled: Bool
    let accessory: () -> Accessory
    @Environment(\.tabAccessoryRegistry) private var registry
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
            registry.upsert(id: id, order: order, content: AnyView(accessory()))
        } else {
            registry.remove(id: id)
        }
    }
}
