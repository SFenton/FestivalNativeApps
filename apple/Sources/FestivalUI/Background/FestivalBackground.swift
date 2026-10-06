import SwiftUI

// MARK: - Page background entry point

public extension View {
    /// Declare which animated/album-art background this page wants.
    ///
    /// Every screen calls this instead of constructing `ArtworkBackground`
    /// directly. The page registers its mode with the session's
    /// `FestivalBackgroundCoordinator` (the most recently appeared visible page
    /// wins) and draws a mirror of the one shared, timestamped backdrop driven
    /// by the shell's `FestivalBackgroundHost`. Because every page mirrors the
    /// same state and clock, tab switches and pushes show one continuous
    /// background: the carousel never restarts, and opening a song animates the
    /// shared backdrop from the carousel to that song's cover.
    ///
    /// Inside an on-demand split the container draws one backdrop for both panes, so
    /// the page draws none, and a trailing-pane page never registers: its parent page
    /// decides the split's background (`SplitPaneChrome`).
    ///
    /// - Parameters:
    ///   - mode: `.carousel` for the shared animated album wall, `.song(art)` for a fixed album.
    ///   - session: Shared artwork cache and background coordinator owner.
    ///   - visible: False while this page is covered, so it never claims the background.
    /// - Returns: The page with its background declared and drawn.
    internal func festivalBackground(
        _ mode: ArtworkBackgroundMode, session: FestivalSession, visible: Bool = true
    ) -> some View {
        modifier(FestivalBackgroundModifier(mode: mode, session: session, visible: visible))
    }
}

// MARK: - Modifier

/// Registers a page with the shared background and draws its mirror.
struct FestivalBackgroundModifier: ViewModifier {
    let mode: ArtworkBackgroundMode
    let session: FestivalSession
    let visible: Bool

    @State private var token = UUID()
    @State private var appeared = false
    /// The on-demand split pane this page is in, if any.
    @Environment(\.splitPane) private var pane
    /// Whether a split container draws the one backdrop behind this page.
    @Environment(\.splitSharesBackdrop) private var sharedBySplit

    /// Trailing-pane pages leave the backdrop to their parent page (`SplitPaneChrome`).
    private var registers: Bool { SplitPaneChrome.registersBackground(pane: pane) }

    func body(content: Content) -> some View {
        let coordinator = session.backgroundCoordinator
        content
            .background {
                if SplitPaneChrome.drawsOwnBackdrop(sharedBySplit: sharedBySplit) {
                    FestivalBackdropView(coordinator: coordinator, appeared: appeared)
                        .accessibilityHidden(true)
                }
            }
            .onAppear {
                appeared = true
                if registers { coordinator.appear(token, mode: mode, visible: visible) }
            }
            .onDisappear {
                appeared = false
                coordinator.disappear(token)
            }
            .onChange(of: mode) { _, new in
                coordinator.update(token, mode: new, visible: visible)
            }
            .onChange(of: visible) { _, new in
                coordinator.update(token, mode: mode, visible: new)
            }
            .onChange(of: registers) { _, registers in
                if !registers {
                    coordinator.disappear(token)
                } else if appeared {
                    coordinator.appear(token, mode: mode, visible: visible)
                }
            }
    }
}
