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

// MARK: - Bottom chrome fade

extension View {
    /// Fade scrolling rows out above chrome pinned to the bottom of the page (a pager, a
    /// footer row), like the web's `useScrollFade` (``ScrollEdgeFade/distance``, 36 pt;
    /// issues #93, #293, #308).
    ///
    /// Rows are fully drawn until the ramp above the chrome's top edge, fade to clear at
    /// that edge and are never drawn beneath the chrome. The ramp shrinks away as the
    /// last row arrives, so at the end of the list nothing is dimmed and the last row
    /// rests unfaded above the chrome. Reduce Transparency and Increase Contrast make it a
    /// hard edge. The mask reaches into the top safe area so rows still scroll under the
    /// navigation bar. Apply it to the scroll view itself.
    ///
    /// - Parameters:
    ///   - chromeTop: The chrome's top edge in `space`; nil (no chrome) draws every row.
    ///   - space: Name of a coordinate space shared by the scroll view and the chrome.
    /// - Returns: The masked scroll view.
    func scrollEdgeFade(bottomChromeTop chromeTop: CGFloat?, in space: String) -> some View {
        modifier(BottomChromeEdgeFadeModifier(chromeTop: chromeTop, space: space))
    }
}

/// Masks a scroll view above its pinned bottom chrome (``View/scrollEdgeFade(bottomChromeTop:in:)``).
private struct BottomChromeEdgeFadeModifier: ViewModifier {
    let chromeTop: CGFloat?
    let space: String
    /// Ramp height for how far the rows still run past the chrome; full mid-list (and
    /// before iOS 18 / macOS 15), shrinking to 0 at the list's end (issue #293).
    @State private var distance = ScrollEdgeFade.distance
    @ScrollEdgeHardEdge private var hardEdge

    func body(content: Content) -> some View {
        let ramp = ScrollEdgeFade.ramp(distance, hardEdge: hardEdge)
        content
            .modifier(BottomFadeDistanceReader { distance = $0 })
            .mask {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .named(space))
                    let stops = ScrollEdgeFade.bottom(
                        height: Double(frame.height),
                        obscured: chromeTop.map { Double(frame.maxY - $0) } ?? 0,
                        distance: ramp
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
                .ignoresSafeArea()
                .accessibilityHidden(true)
            }
    }
}

/// Reports the bottom fade height for how far a scroll view's rows still run below its
/// pinned chrome (iOS 18 / macOS 15 and later; nothing before, which keeps the full
/// fade). Read from the scroll view: a last-row frame reader did not update while the
/// List scrolled, so the fade stayed on the resting last row (issue #293). The value
/// is clamped before it reaches the modifier, so only the last fade-height of scrolling
/// re-renders it.
private struct BottomFadeDistanceReader: ViewModifier {
    let changed: (Double) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.onScrollGeometryChange(for: Double.self) { geometry in
                ScrollEdgeFade.bottomDistance(lastRowOverflow: ScrollEdgeFade.contentOverflow(
                    contentHeight: Double(geometry.contentSize.height),
                    offsetY: Double(geometry.contentOffset.y),
                    containerHeight: Double(geometry.containerSize.height),
                    bottomInset: Double(geometry.contentInsets.bottom)
                )).rounded()
            } action: { _, distance in
                changed(distance)
            }
        } else {
            content
        }
    }
}
