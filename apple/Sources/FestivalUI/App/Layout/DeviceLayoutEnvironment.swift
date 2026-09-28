import CoreGraphics
import SwiftUI

// MARK: - Environment

extension EnvironmentValues {
    /// Current window layout (pose, section chrome, list/detail, cutout-safe insets).
    ///
    /// Published once at the root by ``SwiftUI/View/publishesDeviceLayout(usesSidebarShell:)``;
    /// defaults to ``DeviceLayout/standardPhone`` in previews and hosted tests.
    @Entry var deviceLayout: DeviceLayout = .standardPhone
}

extension View {
    /// Observe window geometry, size class, the iPhone Duo hinge, the system vertical bar
    /// and reserved regions, and publish the resolved ``DeviceLayout`` to descendants.
    ///
    /// Apply once, at the shell root. It adds only a zero-content background probe, so it
    /// does not change layout, hit testing or the accessibility tree.
    ///
    /// - Parameter usesSidebarShell: True while the platform shell is the iPad/macOS sidebar.
    /// - Returns: The view with `\.deviceLayout` set for its descendants.
    func publishesDeviceLayout(usesSidebarShell: Bool) -> some View {
        modifier(DeviceLayoutPublisher(usesSidebarShell: usesSidebarShell))
    }
}

// MARK: - Publisher

/// Gathers ``LayoutSignals`` and injects the resolved layout.
struct DeviceLayoutPublisher: ViewModifier {
    let usesSidebarShell: Bool

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @State private var geometry = WindowGeometry()
    @State private var verticalBarEdge: HorizontalEdge?
    @State private var hinge: HingeState?

    /// Signals assembled from the latest observations.
    private var signals: LayoutSignals {
        #if os(iOS)
        let widthClass: WidthClass = sizeClass == .regular ? .regular : .compact
        #else
        let widthClass: WidthClass = .regular
        #endif
        let observed = LayoutSignals(
            size: geometry.size, widthClass: widthClass, safeAreaInsets: geometry.safeAreaInsets,
            verticalBarEdge: verticalBarEdge, hinge: hinge,
            occlusions: geometry.occlusions, divisions: geometry.divisions,
            usesSidebarShell: usesSidebarShell
        )
        #if DEBUG
        return DebugDuoPose.launch?.apply(to: observed) ?? observed
        #else
        return observed
        #endif
    }

    func body(content: Content) -> some View {
        content
            .environment(\.deviceLayout, DeviceLayout.resolve(signals))
            .background {
                Color.clear
                    .ignoresSafeArea()
                    .onGeometryChange(for: WindowGeometry.self, of: WindowGeometry.init(proxy:)) {
                        geometry = $0
                    }
                    .modifier(DuoSignalProbe(verticalBarEdge: $verticalBarEdge, hinge: $hinge))
                    .accessibilityHidden(true)
            }
    }
}

/// Equatable geometry snapshot taken from the full-window probe.
struct WindowGeometry: Sendable, Equatable {
    var size: CGSize = .zero
    var safeAreaInsets = EdgeInsets()
    var occlusions: [CGRect] = []
    var divisions: [CGRect] = []

    init() {}

    /// Read size, safe area and (iOS 27.1+) active reserved regions from a proxy that
    /// spans the whole window.
    ///
    /// - Parameter proxy: Geometry of a probe that ignores the safe area.
    init(proxy: GeometryProxy) {
        size = proxy.size
        safeAreaInsets = proxy.safeAreaInsets
        #if os(iOS)
        if #available(iOS 27.1, *) {
            occlusions = proxy.reservedRegions(kind: .occlusion).filter(\.isActive).map(\.frame)
            divisions = proxy.reservedRegions(kind: .division).filter(\.isActive).map(\.frame)
        }
        #endif
    }
}

/// Reads the iOS 27.1 vertical-bar edge and hinge; a no-op on earlier systems.
private struct DuoSignalProbe: ViewModifier {
    @Binding var verticalBarEdge: HorizontalEdge?
    @Binding var hinge: HingeState?

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 27.1, *) {
            content.modifier(DuoSignalProbe27(verticalBarEdge: $verticalBarEdge, hinge: $hinge))
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if os(iOS)
/// iOS 27.1 implementation of ``DuoSignalProbe``.
@available(iOS 27.1, *)
private struct DuoSignalProbe27: ViewModifier {
    @Binding var verticalBarEdge: HorizontalEdge?
    @Binding var hinge: HingeState?
    @Environment(\.toolbarVerticalEdge) private var edge

    func body(content: Content) -> some View {
        content
            .onChange(of: edge, initial: true) { _, newEdge in verticalBarEdge = newEdge }
            .onHingeChange { _, context in hinge = context.hinge.map(HingeState.init) }
    }
}

@available(iOS 27.1, *)
extension HingeState {
    /// Map SwiftUI's hinge status.
    ///
    /// - Parameter hinge: Current hinge reported by `onHingeChange`.
    init(_ hinge: DeviceHinge) {
        switch hinge.status {
        case .closed: self = .closed
        case .fullyOpen: self = .fullyOpen
        default: self = .partiallyOpen
        }
    }
}
#endif

// MARK: - Debug pose override

/// Launch-time hinge override for captures while Device Hub's pose controls cannot be
/// scripted (no Accessibility grant): `FST_DEBUG_DUO_POSE=half-portrait` or
/// `unfolded-portrait` (Debug builds only; `.agents/platforms/apple/duo.md`).
///
/// It replaces only the hinge and the fold, keeping the real window, size class,
/// safe area and vertical bar. On the folded outer display (466×678) it therefore
/// previews the dual-source regions at outer-display size inside the outer display's
/// chrome; it is layout evidence, not a capture of the inner display.
enum DebugDuoPose: String, Sendable {
    /// Partially open, portrait: a horizontal division across the window's middle.
    case halfPortrait = "half-portrait"
    /// Fully open, portrait: no division.
    case unfoldedPortrait = "unfolded-portrait"

    /// Height of the synthesized fold (points), close to the inner display's crease margin.
    static let foldHeight: CGFloat = 24

    /// The override named by the launch environment, if any.
    static let launch: DebugDuoPose? = parse(ProcessInfo.processInfo.environment["FST_DEBUG_DUO_POSE"])

    /// Parse an override value.
    ///
    /// - Parameter raw: `FST_DEBUG_DUO_POSE` value.
    /// - Returns: The override, or nil when absent or unknown.
    static func parse(_ raw: String?) -> DebugDuoPose? {
        raw.flatMap(DebugDuoPose.init(rawValue:))
    }

    /// Replace the hinge and fold in observed signals.
    ///
    /// - Parameter signals: Signals observed from the real window.
    /// - Returns: Signals with the overridden hinge (and synthesized fold).
    func apply(to signals: LayoutSignals) -> LayoutSignals {
        var result = signals
        guard signals.size.width > 0, signals.size.height > 0 else { return result }
        switch self {
        case .halfPortrait:
            result.hinge = .partiallyOpen
            result.divisions = [CGRect(
                x: 0, y: (signals.size.height - Self.foldHeight) / 2,
                width: signals.size.width, height: Self.foldHeight
            )]
        case .unfoldedPortrait:
            result.hinge = .fullyOpen
            result.divisions = []
        }
        return result
    }
}
