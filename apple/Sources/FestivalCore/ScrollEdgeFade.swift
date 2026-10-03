import Foundation

// MARK: - Scroll edge fade

/// Where scrolling rows fade out above chrome pinned to the bottom of a page, like
/// the web's `useScrollFade` (36 px, `FortniteFestivalWeb/src/hooks/ui/useScrollFade.ts`):
/// rows are fully drawn until `distance` above the chrome's top edge, fade to clear
/// at that edge and are not drawn beneath the chrome at all (issue #93).
public enum ScrollEdgeFade {
    /// Web `DEFAULT_DISTANCE`: the height of the fade above the chrome.
    public static let distance: Double = 36

    /// Unit gradient locations (0 = top of the masked area, 1 = bottom).
    public struct Stops: Equatable, Sendable {
        /// Last fully opaque location; the fade starts here.
        public let fadeStart: Double
        /// First fully clear location: the chrome's top edge.
        public let fadeEnd: Double

        /// - Parameters:
        ///   - fadeStart: Last fully opaque location.
        ///   - fadeEnd: First fully clear location.
        public init(fadeStart: Double, fadeEnd: Double) {
            self.fadeStart = fadeStart
            self.fadeEnd = fadeEnd
        }
    }

    /// Fade stops for a masked area whose bottom `obscured` points sit under chrome.
    ///
    /// - Parameters:
    ///   - height: Height of the masked area, including the part under the chrome.
    ///   - obscured: Height of the area's bottom covered by the chrome.
    ///   - distance: Height of the fade above the chrome.
    /// - Returns: Clamped unit stops; an empty or invalid area stays fully opaque.
    public static func bottom(height: Double, obscured: Double, distance: Double = distance) -> Stops {
        guard height.isFinite, height > 0, obscured.isFinite, distance.isFinite else {
            return Stops(fadeStart: 1, fadeEnd: 1)
        }
        let end = min(max((height - max(0, obscured)) / height, 0), 1)
        let start = min(max((height - max(0, obscured) - max(0, distance)) / height, 0), end)
        return Stops(fadeStart: start, fadeEnd: end)
    }
}
