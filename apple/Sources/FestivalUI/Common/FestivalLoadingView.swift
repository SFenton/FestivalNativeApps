import SwiftUI
import FestivalDesign

// MARK: - FestivalLoadingView

/// The app's one loading spinner (operator, 2026-09-28: "Any loading spinner should be
/// white, with no subtitle"). A plain circular `ProgressView`, tinted pure white, with no
/// visible title or subtitle text — only an accessibility label so VoiceOver still
/// announces what is loading.
///
/// Use this in place of every `ProgressView("…")`/`ProgressView()` across `Features/**`
/// (see `.agents/design/apple/liquid-glass.md` — spinners are content, not glass, so they
/// need no container of their own). Page/result regions opt into ``Placement/fill``;
/// rows, cards and footers keep the default intrinsic ``Placement/inline`` sizing.
///
/// The label goes on the system indicator itself, so assistive technology meets one
/// element with the busy-indicator role and this name (#431). Wrapping it with
/// `accessibilityElement(children: .ignore)` left a role-less named element (`AXUnknown`
/// on the Mac) with no busy indicator reachable beneath it.
struct FestivalLoadingView: View {
    /// Whether the indicator occupies a bounded result region or stays intrinsic.
    enum Placement: Sendable {
        /// Keep the native indicator's size for a row, card or footer.
        case inline
        /// Fill the parent's visible region and centre outside an active fold.
        case fill
    }

    /// Spoken-only context for VoiceOver; never rendered as visible text.
    var accessibilityLabel: String = "Loading"
    /// The parent supplies the region below page controls and above lower chrome.
    var placement: Placement = .inline

    @Environment(\.deviceLayout) private var layout

    @ViewBuilder
    var body: some View {
        switch placement {
        case .inline:
            indicator
        case .fill:
            GeometryReader { proxy in
                let region = FoldAvoidingPlacement.region(
                    container: proxy.frame(in: .global), fold: layout.splitHinge
                )
                indicator
                    .position(x: region.midX, y: region.midY)
            }
        }
    }

    /// One native busy indicator; its placement wrapper adds no accessibility element.
    private var indicator: some View {
        ProgressView()
            .tint(.white)
            .accessibilityLabel(accessibilityLabel)
    }
}
