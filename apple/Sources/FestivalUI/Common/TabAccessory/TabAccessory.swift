import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Registry

/// The pages currently offering a tab-bar bottom accessory, most recently shown last.
///
/// SwiftUI allows one `tabViewBottomAccessory` per `TabView`, attached at the root,
/// but its content belongs to whichever page is on screen (Songs search, the
/// player page's Select/Deselect). Pages register while they are visible
/// (`onAppear` … `onDisappear`); the host shows the newest registration. A push
/// registers the new page before the covered page disappears, and a pop does the
/// reverse, so "newest wins" always names the visible page.
///
/// Design rules: `.agents/design/apple/nav-accessories.md`.
@MainActor @Observable
final class TabAccessoryRegistry {
    /// One page's accessory content.
    struct Entry {
        let id: UUID
        var content: AnyView
    }

    private(set) var entries: [Entry] = []

    /// The accessory to show: the most recently registered visible page's.
    var active: Entry? { entries.last }

    /// Add or replace a page's accessory, keeping its position when replacing.
    ///
    /// - Parameters:
    ///   - id: Stable identity of the registering page instance.
    ///   - content: Accessory content; it renders in the root's environment, so it must
    ///     not rely on page-only environment values.
    func upsert(id: UUID, content: AnyView) {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].content = content
        } else {
            entries.append(Entry(id: id, content: content))
        }
    }

    /// Remove a page's accessory (page disappeared or no longer offers one).
    ///
    /// - Parameter id: Identity passed to ``upsert(id:content:)``.
    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }
}

extension EnvironmentValues {
    /// Set only where a tab-bar bottom accessory can be shown (iOS 26.1+, horizontal tab
    /// bar). Nil means pages must use their fallback placement (toolbar item or
    /// classic `.searchable`).
    @Entry var tabAccessoryRegistry: TabAccessoryRegistry? = nil

    /// True when a page's primary control should go in the tab-bar bottom accessory.
    var isTabAccessoryAvailable: Bool { tabAccessoryRegistry != nil }
}

// MARK: - Host (root)

extension View {
    /// Host page-provided bottom accessories on this `TabView` (Music's mini-player slot).
    ///
    /// Apply once, directly on the iPhone `TabView`. Active only on iOS 26.1+ with a
    /// horizontal tab bar (`DeviceLayout.sectionChrome == .tabBar`); on the iPhone Duo
    /// vertical bar, iPad and earlier iOS it publishes no registry, so pages fall back.
    /// While an accessory is shown the tab bar minimizes on scroll and the accessory
    /// moves inline beside it, as in Music.
    ///
    /// - Returns: The tab view with the accessory host attached.
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
        if #available(iOS 26.1, *) {
            let supported = layout.sectionChrome == .tabBar
            let active = supported ? registry.active : nil
            content
                .tabViewBottomAccessory(isEnabled: active != nil) {
                    active?.content
                }
                .tabBarMinimizeBehavior(active != nil ? .onScrollDown : .never)
                .environment(\.tabAccessoryRegistry, supported ? registry : nil)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// MARK: - Registration (pages)

extension View {
    /// Offer `accessory` as the tab-bar bottom accessory while this page is visible.
    ///
    /// Does nothing where ``EnvironmentValues/isTabAccessoryAvailable`` is false, so
    /// pages pair it with a fallback placement. The content is captured when
    /// registered; pass a `token` covering every value it displays so changes
    /// re-register it (bindings and `@Observable` reads stay live on their own).
    ///
    /// - Parameters:
    ///   - token: Changes whenever the accessory's captured values change.
    ///   - isEnabled: False withdraws the accessory without leaving the page.
    ///   - accessory: Accessory content (rendered in the root's environment).
    /// - Returns: The page, registering its accessory while visible.
    func festivalTabAccessory<Token: Hashable, Accessory: View>(
        token: Token, isEnabled: Bool = true,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) -> some View {
        modifier(TabAccessoryRegistration(token: token, isEnabled: isEnabled, accessory: accessory))
    }
}

/// Implementation of `festivalTabAccessory(token:isEnabled:accessory:)`.
struct TabAccessoryRegistration<Token: Hashable, Accessory: View>: ViewModifier {
    let token: Token
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
            registry.upsert(id: id, content: AnyView(accessory()))
        } else {
            registry.remove(id: id)
        }
    }
}
