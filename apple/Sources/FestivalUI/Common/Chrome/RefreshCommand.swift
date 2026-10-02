import SwiftUI

// MARK: - Refresh command (⌘R)

/// The pull-to-refresh actions of the pages on screen, so the root's ⌘R hardware
/// keyboard shortcut can run the frontmost page's refresh.
///
/// SwiftUI's `refresh` environment value only reaches views *inside* a `.refreshable`
/// container, never the root, so each refreshable page registers it here through a
/// zero-size probe (``SwiftUI/View/festivalRefreshable(_:)``). Pages register in
/// appearance order; the most recently shown page still on screen wins (in an iPad
/// list/detail split that is the detail page).
///
/// Not observable: nothing draws from it, so registering never invalidates a view.
@MainActor
final class RefreshCommandRegistry {
    /// A registered page's refresh.
    typealias Action = @MainActor () async -> Void

    private var entries: [(id: UUID, action: Action)] = []

    /// Record (or move to the front) a page's refresh action.
    ///
    /// - Parameters:
    ///   - id: The registering probe.
    ///   - action: The page's refresh (its `refresh` environment action).
    func register(_ id: UUID, action: @escaping Action) {
        entries.removeAll { $0.id == id }
        entries.append((id, action))
    }

    /// Forget a page that left the screen.
    ///
    /// - Parameter id: The registering probe.
    func unregister(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    /// Whether a page on screen can refresh.
    var canRefresh: Bool { !entries.isEmpty }

    /// Run the frontmost page's refresh, if any.
    func refresh() async {
        guard let action = entries.last?.action else { return }
        await action()
    }
}

extension EnvironmentValues {
    /// Root-owned refresh registry for ⌘R; nil outside the root shell (hosted tests).
    @Entry var refreshCommandRegistry: RefreshCommandRegistry? = nil
}

extension View {
    /// `.refreshable(action:)` that also offers the action to the root's ⌘R shortcut.
    ///
    /// - Parameter action: The page's reload.
    /// - Returns: The refreshable view.
    func festivalRefreshable(_ action: @escaping @MainActor @Sendable () async -> Void) -> some View {
        background { RefreshCommandProbe() }
            .refreshable(action: action)
    }
}

/// Zero-size probe inside a `.refreshable` container that registers its `refresh`.
private struct RefreshCommandProbe: View {
    @Environment(\.refresh) private var refresh
    @Environment(\.refreshCommandRegistry) private var registry
    @State private var id = UUID()

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                if let refresh { registry?.register(id) { await refresh() } }
            }
            .onDisappear { registry?.unregister(id) }
    }
}

// MARK: - Key command button

/// An invisible, zero-size button that only carries a ⌘ keyboard shortcut for the
/// root shell (hidden from VoiceOver; the visible controls stay the accessible path).
struct KeyCommandButton: View {
    /// Title shown in the ⌘-hold shortcut overlay and the iPadOS menu bar.
    let title: String
    /// Key pressed with Command.
    let key: KeyEquivalent
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .keyboardShortcut(key, modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}
