import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Registry

/// The page controls currently offered to the bottom dock (the web app's search pill +
/// Sort + Quick Links bar above the tab bar).
///
/// SwiftUI allows one `tabViewBottomAccessory` per `TabView`, attached at the root. The
/// dock always starts with global Search; the rest belongs to whichever page is on
/// screen (Songs Filter/Sort, Quick Links, profile Select/Deselect). Controls register
/// while their page is visible (`onAppear` … `onDisappear`), so a push or tab switch
/// swaps them; the dock shows every registered control in ``Entry/order``.
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

/// Dock positions after Search, matching the web dock (search, then page tools).
enum DockOrder {
    /// Songs Filter.
    static let filter = 10
    /// Songs Sort.
    static let sort = 20
    /// Quick Links menu.
    static let quickLinks = 30
    /// A page's primary action (profile Select/Switch/Deselect).
    static let pageAction = 40
}

/// How the bottom dock is presented, published by the host.
enum DockPresentation: Equatable {
    /// iOS 26.1+: the system tab-bar bottom accessory (Liquid Glass, Music's slot).
    case accessory
    /// iOS 17–26.0: a glass bar inset at the bottom of each tab's stack, above the tab bar.
    case inset
}

extension EnvironmentValues {
    /// Set only where the bottom dock exists: iPhone with a horizontal tab bar. Nil (the
    /// iPhone Duo vertical bar, iPad, Mac) means pages keep their controls as toolbar items.
    @Entry var tabAccessoryRegistry: TabAccessoryRegistry? = nil

    /// How the dock is presented where it exists.
    @Entry var dockPresentation: DockPresentation? = nil

    /// True when page controls (Search, Filter/Sort, Quick Links, Select) go in the dock
    /// instead of the toolbar.
    var isTabAccessoryAvailable: Bool { tabAccessoryRegistry != nil }
}

// MARK: - Host (root)

extension View {
    /// Host the bottom dock on this iPhone `TabView`: global Search on every page, then the
    /// visible page's controls.
    ///
    /// iOS 26.1+ uses the system `tabViewBottomAccessory`; earlier iOS publishes an
    /// `.inset` presentation that `FestivalTabStack` draws above the tab bar. With the
    /// iPhone Duo vertical bar it publishes nothing, so pages keep toolbar items.
    ///
    /// - Returns: The tab view with the dock host attached.
    func festivalTabAccessoryHost() -> some View {
        modifier(TabAccessoryHost())
    }
}

/// Implementation of ``SwiftUICore/View/festivalTabAccessoryHost()``.
struct TabAccessoryHost: ViewModifier {
    @State private var registry = TabAccessoryRegistry()
    @Environment(\.deviceLayout) private var layout
    @Environment(\.openGlobalSearch) private var openGlobalSearch

    /// A horizontal tab bar inside the app shell (the dock needs the search action).
    private var supported: Bool {
        layout.sectionChrome == .tabBar && openGlobalSearch != nil
    }

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.1, *) {
            content
                .tabViewBottomAccessory(isEnabled: supported) {
                    if let openGlobalSearch {
                        DockBar(items: registry.items) { openGlobalSearch() }
                    }
                }
                // Never minimized: a collapsed bar hides the other tabs' labels on every
                // scroll app-wide (and journeys then cannot find them). Music minimizes;
                // TODO(orchestrator): opt in with `.onScrollDown` if the operator wants it.
                .tabBarMinimizeBehavior(.never)
                .environment(\.tabAccessoryRegistry, supported ? registry : nil)
                .environment(\.dockPresentation, supported ? .accessory : nil)
        } else {
            content
                .environment(\.tabAccessoryRegistry, supported ? registry : nil)
                .environment(\.dockPresentation, supported ? .inset : nil)
        }
        #else
        content
        #endif
    }
}

// MARK: - Dock content

/// The dock's row: a field-shaped Search button, then the page's controls.
struct DockBar: View {
    let items: [TabAccessoryRegistry.Entry]
    let openSearch: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: openSearch) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .accessibilityHidden(true)
                    Text("Search")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(FestivalText.primary)
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search")
            .accessibilityHint("Searches songs, players and bands")
            .accessibilityIdentifier("fst.global-search.open")
            ForEach(items, id: \.id) { item in
                item.content
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, items.isEmpty ? 16 : 6)
        .labelStyle(.iconOnly)
        .tint(BrandTokens.textPrimary)
    }
}

/// Pre-26.1 presentation: the same row on a glass capsule at the bottom of a tab's
/// stack, above the classic tab bar. Applied by `FestivalTabStack`.
struct DockInset: ViewModifier {
    @Environment(\.tabAccessoryRegistry) private var registry
    @Environment(\.dockPresentation) private var presentation
    @Environment(\.openGlobalSearch) private var openGlobalSearch

    func body(content: Content) -> some View {
        if presentation == .inset, let registry, let openGlobalSearch {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                DockBar(items: registry.items) { openGlobalSearch() }
                    .frame(height: 48)
                    .festivalGlassCapsule(.control, interactive: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        } else {
            content
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
