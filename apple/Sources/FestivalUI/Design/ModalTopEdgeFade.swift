import SwiftUI

// MARK: - Modal top-edge fade

/// Geometry of the fade that hides modal content as it scrolls up under the header
/// (issue #94).
///
/// A modal's header (inline title, Close and any toolbar items) is its navigation bar.
/// Content is fully transparent behind the upper part of the header and fades back in over
/// ``rampHeight(headerHeight:)`` points ending at the header's bottom edge, so content at
/// rest below the header is never dimmed.
enum ModalTopEdgeFade {
    /// Longest fade ramp, matching the web modal list's 18 px edge fade plus a little
    /// room for the taller native bar.
    static let maxRampHeight: CGFloat = 24

    /// Header height from the content's two readings.
    ///
    /// A full-bleed `List` (Notifications) reaches under the bar, so the header is its top
    /// safe-area inset and the container offset is 0. Content that sits below the bar while
    /// its scroll view draws upward (Paths) is offset from the container's top by the
    /// header, yet still reports the same inset (measured on iOS 26.5), so the two must not
    /// be added: the larger one is the header in both layouts.
    ///
    /// - Parameters:
    ///   - safeAreaInset: The content's top safe-area inset.
    ///   - containerOffset: How far the content's top sits below the modal container's top.
    /// - Returns: The header height; 0 for negative or non-finite readings.
    static func headerHeight(safeAreaInset: CGFloat, containerOffset: CGFloat) -> CGFloat {
        let readings = [safeAreaInset, containerOffset].filter(\.isFinite)
        return max(0, readings.max() ?? 0)
    }

    /// Length of the fade ramp for a header.
    ///
    /// - Parameter headerHeight: The modal's header height.
    /// - Returns: At most half the header (so the title and Close always sit over a fully
    ///   faded region) and at most ``maxRampHeight``; 0 when there is no header.
    static func rampHeight(headerHeight: CGFloat) -> CGFloat {
        guard headerHeight.isFinite, headerHeight > 0 else { return 0 }
        return min(maxRampHeight, headerHeight / 2)
    }

    /// Where, as a fraction of the header height, content starts fading back in.
    ///
    /// - Parameter headerHeight: The modal's header height.
    /// - Returns: A location in `0...1` for the gradient's last transparent stop; 1 when
    ///   there is no header.
    static func fadeStart(headerHeight: CGFloat) -> CGFloat {
        let ramp = rampHeight(headerHeight: headerHeight)
        guard ramp > 0 else { return 1 }
        return (headerHeight - ramp) / headerHeight
    }
}

/// Fades a modal's content out under its header instead of drawing it hard behind the
/// title and Close, like pages (`TopEdgeScrim`) and the web modals' scroll mask.
///
/// HIG Color: "content may scroll under controls, but make sure the resting state, like the
/// top of scrollable content, stays clearly legible." The mask covers only the header's
/// region, so resting content, hit testing, VoiceOver and detents are unchanged, and the
/// sheet's own background (glass, frosted, or opaque under Reduce Transparency and Increase
/// Contrast) shows through behind the header. The system scroll-edge effect stays on its
/// automatic style (HIG Scroll views: "Prefer the automatic style").
struct ModalTopEdgeFadeModifier: ViewModifier {
    /// The content's own coordinate space. Global coordinates would include the sheet's
    /// presentation transform, which SwiftUI doesn't report as a geometry change.
    private nonisolated static let space = "fst.modalTopEdgeFade"

    /// The content's top safe-area inset, from a reader that respects the safe area: a view
    /// that ignores it, and a mask, always report a zero inset.
    @State private var safeAreaInset: CGFloat = 0
    /// Distance from the modal container's top (reached by a reader that ignores the safe
    /// area) down to the content's top.
    @State private var containerOffset: CGFloat = 0

    private var headerHeight: CGFloat {
        ModalTopEdgeFade.headerHeight(safeAreaInset: safeAreaInset, containerOffset: containerOffset)
    }

    func body(content: Content) -> some View {
        content
            .background {
                Color.clear
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.safeAreaInsets.top
                    } action: { safeAreaInset = $0 }
                    .accessibilityHidden(true)
            }
            .background {
                Color.clear
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        -proxy.frame(in: .named(Self.space)).minY
                    } action: { containerOffset = $0 }
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: ModalTopEdgeFade.fadeStart(headerHeight: headerHeight)),
                            .init(color: .black, location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: headerHeight)
                    Color.black
                }
                // Reach under the header so the mask covers (and fades) it.
                .ignoresSafeArea()
            }
            .coordinateSpace(.named(Self.space))
    }
}
