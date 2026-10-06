import SwiftUI
import FestivalCore

// MARK: - Bottom chrome fade

extension View {
    /// Reports the top edge of a page's pinned bottom chrome (a pager, optionally
    /// with the selected player's footer above it) for ``bottomChromeFade(chromeTop:distance:in:)``.
    ///
    /// - Parameters:
    ///   - space: Named coordinate space shared with the faded rows.
    ///   - changed: Receives the chrome's top in `space`, or nil while it draws
    ///     nothing (the iPhone Duo vertical bar moves the pager into the rail).
    /// - Returns: The chrome, measured.
    func reportsBottomChromeTop(in space: String, _ changed: @escaping (CGFloat?) -> Void) -> some View {
        onGeometryChange(for: CGFloat?.self) { proxy in
            proxy.size.height > 0 ? proxy.frame(in: .named(space)).minY : nil
        } action: { top in
            changed(top)
        }
    }

    /// Fades a board's scrolling rows out above its pinned bottom chrome, the one
    /// bottom edge every paginated leaderboard shares (issue #305).
    ///
    /// Rows are opaque until up to 36 pt above the chrome's top, fade to clear at
    /// that edge and are not drawn beneath it (web `useScrollFade`, issue #93). The
    /// fade shrinks with the remaining scroll, so the last row comes to rest unfaded
    /// (issue #293). It applies whether or not the chrome holds a player footer: a
    /// board without one (band boards, no selected player, no score here) used to
    /// cut its rows off hard at the pager. A manual scroll-edge effect for a custom
    /// bar: "With custom bars, you might add one manually if needed" (HIG Scroll
    /// views); "Prefer scroll-edge effects to solid/semi-opaque backgrounds beneath
    /// controls" (HIG Layout). Reduce Transparency, Increase Contrast and the app's
    /// Less Transparency / Increase Contrast make it a hard cut at the chrome's top
    /// edge instead (scroll-edge R7).
    ///
    /// - Parameters:
    ///   - chromeTop: The chrome's top from ``reportsBottomChromeTop(in:_:)``; nil
    ///     draws every row. Read the state into a local at the top of the screen's
    ///     own `body`: read only inside a `FestivalReloadGate` content closure, the
    ///     screen never re-renders when it changes (issues #294, #305).
    ///   - distance: The page's fade height, updated from the scroll position.
    ///   - space: Named coordinate space shared with the chrome.
    ///   - legacyScrollTracking: Read the scroll position from the platform scroll view
    ///     (``ScrollEdgeTracking/usesLegacyPath``); tests set it to cover the iOS 17 /
    ///     macOS 14 path on newer systems.
    /// - Returns: The scroll view, masked.
    func bottomChromeFade(
        chromeTop: CGFloat?, distance: Binding<Double>, in space: String,
        legacyScrollTracking: Bool = ScrollEdgeTracking.usesLegacyPath
    ) -> some View {
        modifier(BottomChromeFade(
            chromeTop: chromeTop, distance: distance, space: space, legacyScrollTracking: legacyScrollTracking
        ))
    }
}

/// The mask behind ``SwiftUI/View/bottomChromeFade(chromeTop:distance:in:)``.
///
/// The chrome top arrives as a value the screen read in its own body, not inside the
/// mask's lazy `GeometryReader`: read only there, the first page kept an opaque mask
/// (rows behind the pager) until something else re-rendered the page (issue #294).
struct BottomChromeFade: ViewModifier {
    let chromeTop: CGFloat?
    @Binding var distance: Double
    let space: String
    /// Read the scroll position from the platform scroll view (iOS 17 / macOS 14).
    var legacyScrollTracking = ScrollEdgeTracking.usesLegacyPath
    /// The shared scroll-edge R7 setting, the same one every top-edge fade reads.
    @ScrollEdgeHardEdge private var hardEdge

    func body(content: Content) -> some View {
        let fadeDistance = ScrollEdgeFade.ramp(distance, hardEdge: hardEdge)
        content
            .modifier(BottomFadeDistanceReader(legacy: legacyScrollTracking) { distance = $0 })
            .mask { mask(fadeDistance: fadeDistance) }
    }

    /// The fade height to draw for the system and in-app accessibility settings
    /// (scroll-edge R7): 0, a hard cut at the chrome's top edge, when any is on. The
    /// same resolution as ``ScrollEdgeHardEdge`` with ``ScrollEdgeFade/ramp(_:hardEdge:)``,
    /// spelled out per setting for tests.
    ///
    /// - Parameters:
    ///   - distance: The scroll-driven fade height.
    ///   - systemReduceTransparency: System Reduce Transparency.
    ///   - lessTransparency: The app's Less Transparency.
    ///   - systemContrast: System contrast (Increase Contrast is `.increased`).
    ///   - moreContrast: The app's Increase Contrast.
    /// - Returns: The fade height, in points.
    static func fadeDistance(
        _ distance: Double, systemReduceTransparency: Bool, lessTransparency: Bool,
        systemContrast: ColorSchemeContrast, moreContrast: Bool
    ) -> Double {
        ScrollEdgeFade.ramp(distance, hardEdge: ScrollEdgeHardEdge.resolve(
            reduceTransparency: systemReduceTransparency || lessTransparency,
            increaseContrast: moreContrast || systemContrast == .increased
        ))
    }

    /// Opaque, then a fade ending at the chrome's top edge, clear beneath it.
    /// Extends into the top safe area so rows still scroll under the navigation bar.
    ///
    /// - Parameter fadeDistance: Height of the fade above the chrome.
    /// - Returns: The alpha mask.
    private func mask(fadeDistance: Double) -> some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named(space))
            if let chromeTop {
                let stops = ScrollEdgeFade.bottom(
                    height: Double(frame.height),
                    obscured: Double(frame.maxY - chromeTop),
                    distance: fadeDistance
                )
                LinearGradient(
                    stops: [
                        .init(color: .black, location: stops.fadeStart),
                        .init(color: .clear, location: stops.fadeEnd),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            } else {
                Color.black
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Bottom fade distance reader

/// Reports the bottom fade height for how far a scroll view's rows still run below its
/// pinned chrome, on every supported system (``SwiftUI/View/onScrollEdgeReading(legacy:_:action:)``:
/// `onScrollGeometryChange` on iOS 18 / macOS 15 and later, the platform scroll view
/// before), so the last row comes to rest unfaded everywhere (scroll-edge R4; #308
/// review). Read from the scroll view: a last-row frame reader did not update while the
/// List scrolled, so the fade stayed on the resting last row (issue #293). The value is
/// clamped before it reaches the screen, so only the last fade-height of scrolling
/// re-renders it.
///
/// The scroll view's height is `visibleRect`'s (the platform scroll view's bounds), which
/// spans the regions under its insets for a `List` and a `ScrollView` alike.
/// `containerSize` does only for a `List`: a `ScrollView` reports it without its
/// safe-area insets, which counted the bottom inset twice, so the fade never shrank and
/// the last row rested faded (Full Rankings, band boards; issue #305).
struct BottomFadeDistanceReader: ViewModifier {
    /// Read the platform scroll view (iOS 17 / macOS 14).
    var legacy = ScrollEdgeTracking.usesLegacyPath
    let changed: (Double) -> Void

    func body(content: Content) -> some View {
        content.onScrollEdgeReading(legacy: legacy) { reading in
            ScrollEdgeFade.bottomDistance(lastRowOverflow: reading.overflow.map(Double.init)).rounded()
        } action: { distance in
            changed(distance)
        }
    }
}
