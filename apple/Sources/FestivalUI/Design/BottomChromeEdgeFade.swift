import FestivalCore
import SwiftUI

// MARK: - Bottom chrome edge fade

/// The one bottom-chrome edge treatment for Apple leaderboards (scroll-edge R1): rows are
/// opaque, fade to clear over up to ``ScrollEdgeFade/distance`` (36 pt, web
/// `useScrollFade`) ending at the pinned footer/pager's top edge, and are not drawn
/// beneath it (issues #93, #293). The fade shrinks as the last row reaches its resting
/// place, one row gap above the chrome.
///
/// With System Reduce Transparency, the in-app Less Transparency, or Increase Contrast
/// (system or in-app) on, the ramp becomes a hard cut at the chrome's top edge
/// (scroll-edge R7): rows stay opaque down to the chrome and are never drawn under it.
///
/// Used by the Solo chart, Full Rankings and the full band leaderboard (issue #306), so
/// the three pages cannot drift apart.
struct BottomChromeEdgeFadeMask: View {
    /// The pinned chrome's measured top in `space`; nil (not measured yet, or no chrome)
    /// draws every row.
    let chromeTop: CGFloat?
    /// Current fade height, from ``BottomFadeDistanceReader``.
    let distance: Double
    /// Named coordinate space shared by the scroll view and the pinned chrome.
    let space: String
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.colorSchemeContrast) private var systemContrast
    @AppStorage("fst.accessibility.lessTransparency") private var lessTransparency = false
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false

    /// The fade height to draw: `distance` normally, 0 (a hard cut) under the
    /// accessibility settings of scroll-edge R7.
    ///
    /// - Parameters:
    ///   - distance: The scroll-driven fade height (``BottomFadeDistanceReader``).
    ///   - reduceTransparency: System Reduce Transparency or in-app Less Transparency.
    ///   - increaseContrast: System or in-app Increase Contrast.
    /// - Returns: A non-negative fade height.
    static func fadeDistance(_ distance: Double, reduceTransparency: Bool, increaseContrast: Bool) -> Double {
        reduceTransparency || increaseContrast ? 0 : distance
    }

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named(space))
            let stops = ScrollEdgeFade.bottom(
                height: Double(frame.height),
                obscured: chromeTop.map { Double(frame.maxY - $0) } ?? 0,
                distance: Self.fadeDistance(
                    distance,
                    reduceTransparency: systemReduceTransparency || lessTransparency,
                    increaseContrast: moreContrast || systemContrast == .increased
                )
            )
            if chromeTop == nil {
                Color.black
            } else {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: stops.fadeStart),
                        .init(color: .clear, location: stops.fadeEnd),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        // Extends into the top safe area so rows still scroll under the navigation bar.
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    /// Fades this scroll view's rows out above pinned bottom chrome and hides them
    /// beneath it (scroll-edge R1–R3).
    ///
    /// Pass `chromeTop` from a value read in the caller's `body`, not from inside a lazy
    /// reader, so measuring the chrome always rebuilds the mask (issue #294).
    ///
    /// - Parameters:
    ///   - chromeTop: The chrome's measured top in `space`; nil draws every row.
    ///   - distance: Current fade height (``BottomFadeDistanceReader``).
    ///   - space: Named coordinate space shared with the pinned chrome.
    /// - Returns: The masked view.
    func bottomChromeEdgeFade(chromeTop: CGFloat?, distance: Double, in space: String) -> some View {
        mask { BottomChromeEdgeFadeMask(chromeTop: chromeTop, distance: distance, space: space) }
    }
}
