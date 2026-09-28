import SwiftUI

// MARK: - Shell-level background host

/// Single background layer hosted once by the app shell, behind every tab.
///
/// Currently empty: pages still draw their own background through
/// `.festivalBackground(_:session:visible:)`. The background lane moves the
/// animated carousel and album-art transitions here (driven by a preference
/// that pages set) so tab switches and pushes never restart the animation.
struct FestivalBackgroundHost: View {
    let session: FestivalSession

    var body: some View {
        Color.clear
    }
}
