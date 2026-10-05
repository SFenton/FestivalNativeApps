import SwiftUI

// MARK: - Modal top-edge fade

/// Geometry of the fade that hides modal content before it reaches the header (issue #94).
///
/// A modal's header (inline title, Close and any toolbar items) is its navigation bar. Like
/// the web modal's scroll mask (`FortniteFestivalWeb/src/hooks/ui/useScrollMask.ts` with
/// `selfScroll`, from `components/modals/Modal.tsx`), content is never drawn under the
/// header: it is fully transparent up to the header's bottom edge and, once scrolled, fades
/// back in over ``rampHeight`` points below it. At rest (scrolled to the top) nothing below
/// the header is dimmed; the fade grows with the first ``rampHeight`` points of scrolling
/// instead of the web's on/off switch.
enum ModalTopEdgeFade {
    /// Height of the fade below the header: the web mask's `DEFAULT_SIZE` (40 px).
    static let rampHeight: CGFloat = 40

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

    /// How far the fade below the header has grown.
    ///
    /// - Parameters:
    ///   - scrollOffset: Distance scrolled from the content's resting top (content offset
    ///     plus top inset); negative while pulled down past the top.
    ///   - rampHeight: The ramp's height; 0 (content that fades itself, issue #301) is a
    ///     hard edge as soon as the content scrolls.
    /// - Returns: 0 at rest or when pulled down (no fade), rising linearly to 1 (full fade)
    ///   after `rampHeight` points; 0 for a non-finite reading.
    static func progress(scrollOffset: CGFloat, rampHeight: CGFloat = ModalTopEdgeFade.rampHeight) -> CGFloat {
        guard scrollOffset.isFinite else { return 0 }
        guard rampHeight > 0 else { return scrollOffset > 0 ? 1 : 0 }
        return min(max(scrollOffset / rampHeight, 0), 1)
    }

    /// Mask opacity at the header's bottom edge, where the fade below the header starts.
    ///
    /// The mask is always clear above this edge, so content never shows under the header;
    /// below it the mask ramps to opaque over ``rampHeight``.
    ///
    /// - Parameter progress: The fade's growth from ``progress(scrollOffset:)``.
    /// - Returns: 1 at rest (content right below the header fully drawn), 0 once scrolled
    ///   (content fully transparent at the header edge).
    static func edgeOpacity(progress: CGFloat) -> CGFloat {
        guard progress.isFinite else { return 1 }
        return 1 - min(max(progress, 0), 1)
    }
}

/// Keeps a modal's content out from under its header, like the web modals: the header has
/// no glass band of its own and sits directly on the sheet background, and scrolled content
/// fades to fully transparent before it reaches the header (issue #94).
///
/// The platform default lets content scroll under the sheet's navigation bar behind a
/// scroll-edge effect (HIG Materials: "Let content scroll and peek through while preserving
/// control and navigation legibility"). The owner chose web parity instead; with nothing
/// scrolling behind the header the effect is hidden, per HIG Scroll views: "Only use an edge
/// effect when a scroll view is behind floating interface elements. It isn't decorative."
/// The system navigation bar, title, Close, swipe-to-dismiss, hit testing, VoiceOver and
/// detents are unchanged, and the sheet's own background (glass, frosted, or opaque under
/// Reduce Transparency and Increase Contrast) shows behind the header.
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
    /// Distance the content's scroll view has scrolled from its resting top.
    @State private var scrollOffset: CGFloat = 0
    /// Ramp height the content asked for (``ModalTopEdgeFadeRampKey``); nil uses
    /// ``ModalTopEdgeFade/rampHeight``.
    @State private var rampOverride: CGFloat?

    private var rampHeight: CGFloat { rampOverride ?? ModalTopEdgeFade.rampHeight }

    private var headerHeight: CGFloat {
        ModalTopEdgeFade.headerHeight(safeAreaInset: safeAreaInset, containerOffset: containerOffset)
    }

    func body(content: Content) -> some View {
        content
            .modifier(ModalScrollOffsetReader(offset: $scrollOffset))
            .modifier(ModalHeaderBackgroundHidden())
            .onPreferenceChange(ModalTopEdgeFadeRampKey.self) { rampOverride = $0 }
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
                    Color.clear
                        .frame(height: headerHeight)
                    LinearGradient(
                        colors: [
                            .black.opacity(
                                ModalTopEdgeFade.edgeOpacity(
                                    progress: ModalTopEdgeFade.progress(
                                        scrollOffset: scrollOffset, rampHeight: rampHeight
                                    )
                                )
                            ),
                            .black,
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: rampHeight)
                    Color.black
                }
                // Reach under the header so the mask covers (and hides) it.
                .ignoresSafeArea()
            }
            .coordinateSpace(.named(Self.space))
    }
}

/// Reads how far the content's scroll view has scrolled (iOS 18 / macOS 15 and later).
///
/// Earlier systems keep the fade at 0, so content is cut off cleanly at the header's
/// bottom edge rather than dimmed at rest.
private struct ModalScrollOffsetReader: ViewModifier {
    @Binding var offset: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, newValue in
                offset = newValue
            }
        } else {
            content
        }
    }
}

/// Hides the header's own background: the top scroll-edge effect (iOS and macOS 26) and the
/// navigation bar's material (earlier iOS), so the header sits on the sheet background.
private struct ModalHeaderBackgroundHidden: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content
                .scrollEdgeEffectHidden(true, for: .top)
                #if os(iOS)
                .toolbarBackground(.hidden, for: .navigationBar)
                #endif
        } else {
            content
                #if os(iOS)
                .toolbarBackground(.hidden, for: .navigationBar)
                #endif
        }
    }
}
