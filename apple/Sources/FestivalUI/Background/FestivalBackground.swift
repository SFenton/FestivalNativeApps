import SwiftUI

// MARK: - Page background entry point

public extension View {
    /// Declare which animated/album-art background this page wants.
    ///
    /// Every screen calls this instead of constructing `ArtworkBackground` directly,
    /// so the background lane can move to a single shared, cross-fading background
    /// hosted by the app shell without editing feature screens.
    ///
    /// - Parameters:
    ///   - mode: `.carousel` for the shared animated album wall, `.song(art)` for a fixed album.
    ///   - session: Shared artwork cache owner.
    ///   - visible: False while this page is covered, so animation can pause.
    /// - Returns: The page with its background applied.
    internal func festivalBackground(
        _ mode: ArtworkBackgroundMode, session: FestivalSession, visible: Bool = true
    ) -> some View {
        background(ArtworkBackground(mode: mode, session: session, visible: visible))
    }
}
