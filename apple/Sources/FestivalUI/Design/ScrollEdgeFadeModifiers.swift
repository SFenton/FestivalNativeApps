import FestivalCore
import SwiftUI

// MARK: - Accessibility hard edge

/// Whether scroll-edge ramps become a hard edge (`.agents/patterns/scroll-edge.md` R7,
/// issue #308): system Reduce Transparency or Increase Contrast, or the app's Less
/// Transparency or Increase Contrast setting. Content is then cut cleanly at the edge,
/// never dimmed and never drawn behind the chrome, matching the opaque material fallback
/// (`FestivalGlassModifier`).
@propertyWrapper
struct ScrollEdgeHardEdge: DynamicProperty {
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.colorSchemeContrast) private var systemContrast
    @AppStorage("fst.accessibility.lessTransparency") private var lessTransparency = false
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false

    init() {}

    /// True when every scroll-edge ramp should be a hard edge.
    var wrappedValue: Bool {
        ScrollEdgeHardEdge.resolve(
            reduceTransparency: systemReduceTransparency || lessTransparency,
            increaseContrast: moreContrast || systemContrast == .increased
        )
    }

    /// The hard-edge decision from the merged settings.
    ///
    /// - Parameters:
    ///   - reduceTransparency: System Reduce Transparency or the app's Less Transparency.
    ///   - increaseContrast: System or in-app Increase Contrast.
    /// - Returns: True when either is on.
    nonisolated static func resolve(reduceTransparency: Bool, increaseContrast: Bool) -> Bool {
        reduceTransparency || increaseContrast
    }
}
