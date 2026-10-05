import CoreGraphics
import SwiftUI

// MARK: - Section bar edge fade

/// How Songs rows fade out as they scroll up under the floating section title (issue #10).
///
/// iOS 26 fades content under the navigation bar with its soft scroll-edge effect, but the
/// system draws that effect only at bar edges, never under the custom section title. Rows
/// used to end at the title's bottom edge with a hard cut. Now the row mask ramps from
/// transparent at that edge to opaque ``height`` points below it, so rows fade out under
/// the title as they do under the bar. Rows never show behind the title text itself.
/// Near a section's start the fade is shorter (``SongsScrollChrome/rowFadeLimit``,
/// issue #298), so a section a jump has just shown keeps its first row unfaded.
///
/// Reduce Transparency, and the app's Less Transparency and Increase Contrast settings
/// (or the system's Increase Contrast), keep the hard cut. That matches the app's glass
/// fallback (`FestivalGlassModifier`): no see-through rows beside the title, and a crisp
/// edge between the title and the content.
enum SectionBarEdgeFade {
    /// Distance below the section title's bottom edge over which rows fade in, in points.
    static let height: CGFloat = 28

    /// Gradient sample positions, from the title's edge (0) to the end of the fade (1).
    static let sampleLocations: [CGFloat] = [0, 0.25, 0.5, 0.75, 1]

    /// The fade height for the current accessibility settings.
    ///
    /// - Parameters:
    ///   - reduceTransparency: System Reduce Transparency or the app's Less Transparency.
    ///   - increaseContrast: System Increase Contrast or the app's Increase Contrast.
    /// - Returns: ``height``, or 0 (a hard edge) when either setting is on.
    static func height(reduceTransparency: Bool, increaseContrast: Bool) -> CGFloat {
        reduceTransparency || increaseContrast ? 0 : height
    }

    /// Row opacity at a fraction of the way through the fade: a smoothstep, so the fade
    /// eases in at the title's edge and out where rows become fully opaque.
    ///
    /// - Parameter progress: 0 at the title's bottom edge, 1 at the end of the fade;
    ///   clamped to that range.
    /// - Returns: The mask opacity, 0 to 1.
    static func opacity(at progress: CGFloat) -> Double {
        let t = Double(min(max(progress, 0), 1))
        return t * t * (3 - 2 * t)
    }

    /// The mask gradient's stops, sampled from ``opacity(at:)``.
    static var gradientStops: [Gradient.Stop] {
        sampleLocations.map {
            Gradient.Stop(color: .black.opacity(opacity(at: $0)), location: $0)
        }
    }
}
