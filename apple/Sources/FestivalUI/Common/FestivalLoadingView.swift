import SwiftUI
import FestivalDesign

// MARK: - FestivalLoadingView

/// The app's one loading spinner (operator, 2026-09-28: "Any loading spinner should be
/// white, with no subtitle"). An indeterminate `ProgressView` drawn by
/// ``FestivalArcProgressStyle`` as a white arc spinning on a faint track (#635: the web
/// `ArcSpinner`, Android `FestivalLoading` and the Windows `ProgressRing` style), with no
/// visible title or subtitle text — only an accessibility label so VoiceOver still
/// announces what is loading.
///
/// Use this in place of every `ProgressView("…")`/`ProgressView()` across `Features/**`
/// (see `.agents/design/apple/liquid-glass.md` — spinners are content, not glass, so they
/// need no container of their own). Page/result regions opt into ``Placement/fill``
/// (web `SpinnerSize.LG`); rows, cards and footers keep the default intrinsic
/// ``Placement/inline`` sizing, chosen with `controlSize` (``FestivalArcMetrics``). A
/// status row whose text says what is in progress passes `status`, the one case with
/// visible text (Android's feedback status row).
///
/// The label goes on the progress view itself, so assistive technology meets one
/// element with the busy-indicator role and this name (#431). Wrapping it with
/// `accessibilityElement(children: .ignore)` left a role-less named element (`AXUnknown`
/// on the Mac) with no busy indicator reachable beneath it.
struct FestivalLoadingView: View {
    /// Whether the indicator occupies a bounded result region or stays intrinsic.
    enum Placement: Sendable {
        /// Keep the arc's intrinsic size for a row, card or footer.
        case inline
        /// Fill the parent's visible region and centre outside an active fold.
        case fill
    }

    /// Spoken-only context for VoiceOver; never rendered as visible text.
    var accessibilityLabel: String = "Loading"
    /// The parent supplies the region below page controls and above lower chrome.
    var placement: Placement = .inline
    /// Visible status text beside a small arc (a form's "Adding media…" row); it is
    /// also the spoken name. Nil for every other spinner, which shows no text.
    var status: String?

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
                    .controlSize(.large)
                    .position(x: region.midX, y: region.midY)
            }
        }
    }

    /// One busy indicator; its placement wrapper adds no accessibility element.
    @ViewBuilder
    private var indicator: some View {
        if let status {
            ProgressView { Text(status) }
                .progressViewStyle(FestivalArcProgressStyle())
                .controlSize(.small)
        } else {
            ProgressView()
                .progressViewStyle(FestivalArcProgressStyle())
                .accessibilityLabel(accessibilityLabel)
        }
    }
}

// MARK: - Arc metrics

/// Web `@festival/theme` `Spinner` tokens: the arc's diameter and stroke per size, its
/// track opacity and one rotation's duration.
enum FestivalArcMetrics {
    /// Diameter and stroke width, in points.
    struct Size: Equatable, Sendable {
        let diameter: CGFloat
        let lineWidth: CGFloat
    }

    /// Web `SpinnerSize.SM`: status rows, artwork tiles and other small rows.
    static let small = Size(diameter: 24, lineWidth: 3)
    /// Web `SpinnerSize.MD`: cards, rows and footers (Android's default).
    static let medium = Size(diameter: 36, lineWidth: 3)
    /// Web `SpinnerSize.LG`: page and result gates (web `LoadGate`, `Page`).
    static let large = Size(diameter: 48, lineWidth: 4)
    /// Web `Spinner.duration`: one full turn, in seconds.
    static let period: TimeInterval = 0.8
    /// The arc's sweep, a quarter turn like the web's coloured top border.
    static let sweep: Double = 0.25

    /// The web size for a SwiftUI control size.
    ///
    /// - Parameter controlSize: The environment's control size.
    /// - Returns: Small for mini/small, medium for regular and large for large/extra large.
    static func size(for controlSize: ControlSize) -> Size {
        switch controlSize {
        case .mini, .small: small
        case .large, .extraLarge: large
        default: medium
        }
    }

    /// Web `Spinner.trackColor` (10% white); 25% under Increase Contrast so the ring
    /// stays visible while the white arc keeps its contrast against it.
    ///
    /// - Parameter contrast: The environment's color-scheme contrast.
    /// - Returns: The track's white opacity.
    static func trackOpacity(_ contrast: ColorSchemeContrast) -> Double {
        contrast == .increased ? 0.25 : 0.10
    }

    /// The arc's rotation at `time`, synced to the wall clock so every spinner on screen
    /// turns in phase (the web's negative `animationDelay`).
    ///
    /// - Parameter time: Seconds since the reference date.
    /// - Returns: Degrees in `0..<360`, clockwise.
    static func angle(at time: TimeInterval) -> Double {
        let phase = time.truncatingRemainder(dividingBy: period) / period
        return (phase < 0 ? phase + 1 : phase) * 360
    }
}

// MARK: - FestivalArcProgressStyle

/// Draws an indeterminate `ProgressView` as the cross-platform arc spinner: a white
/// quarter arc turning once every 0.8 s on a faint full-circle track. Only
/// ``FestivalLoadingView`` applies it; the progress view keeps its busy-indicator role
/// and label. A configuration label (status text) sits beside the arc.
struct FestivalArcProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        Group {
            if let label = configuration.label {
                HStack(spacing: 12) {
                    FestivalArc()
                    label.foregroundStyle(FestivalText.primary)
                }
            } else {
                FestivalArc()
            }
        }
        // A custom style's drawing exposes no busy indicator, so assistive technology
        // meets the system circular indicator for the same configuration instead (#431).
        .accessibilityRepresentation {
            ProgressView(configuration).progressViewStyle(.circular)
        }
    }
}

/// The arc and its track at the environment's control size.
private struct FestivalArc: View {
    @Environment(\.controlSize) private var controlSize
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let size = FestivalArcMetrics.size(for: controlSize)
        TimelineView(.animation) { context in
            let inset = size.lineWidth / 2
            ZStack {
                Circle()
                    .inset(by: inset)
                    .stroke(Color.white.opacity(FestivalArcMetrics.trackOpacity(contrast)), lineWidth: size.lineWidth)
                Circle()
                    .inset(by: inset)
                    .trim(from: 0, to: FestivalArcMetrics.sweep)
                    .stroke(Color.white, lineWidth: size.lineWidth)
                    // Centre the quarter arc on 12 o'clock at phase 0, like a top border.
                    .rotationEffect(.degrees(-135 + FestivalArcMetrics.angle(
                        at: context.date.timeIntervalSinceReferenceDate
                    )))
            }
        }
        .frame(width: size.diameter, height: size.diameter)
    }
}
