#if os(iOS) && DEBUG
import FestivalCore
import UIKit

/// Screenshot and journey hook for the Song Detail lane (Debug only):
/// `FST_UIKIT_DEBUG_SONGDETAIL=<songId or title>` pushes that song's Detail on the selected
/// section once the catalogue loads, so the page can be reached before the Songs list is
/// merged. The Songs lane's own `FST_DEBUG_SONG` hook is separate.
@MainActor
enum UKSongDetailDebug {
    /// Starts the hook if the environment asks for it.
    ///
    /// - Parameter root: The window root.
    static func openIfRequested(on root: UKRootViewController) {
        guard let value = ProcessInfo.processInfo.environment["FST_UIKIT_DEBUG_SONGDETAIL"], !value.isEmpty else { return }
        Task { @MainActor in
            do {
                let payload = try await root.session.catalog()
                guard let song = payload.catalog.songs.first(where: { $0.songId == value || $0.title == value }) else { return }
                try? await Task.sleep(for: .seconds(1))
                root.push(.songDetail(song))
            } catch {
                return
            }
        }
    }
}
#endif
