import CoreGraphics
import SwiftUI
#if os(iOS)
import UIKit
#endif

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
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
    @State private var geometry = WindowGeometry()
    @State private var verticalBarEdge: HorizontalEdge?
    @State private var hinge: HingeState?

    /// Signals assembled from the latest observations.
    private var signals: LayoutSignals {
        #if os(iOS)
        let widthClass: WidthClass = sizeClass == .regular ? .regular : .compact
        let heightClass: WidthClass = verticalSizeClass == .compact ? .compact : .regular
        #else
        // macOS has no size classes: each Mac pane derives one from its width.
        let widthClass: WidthClass = MacLayoutPolicy.widthClass(forWidth: geometry.size.width)
        let heightClass: WidthClass = .regular
        #endif
        let observed = LayoutSignals(
            size: geometry.size, widthClass: widthClass, heightClass: heightClass,
            safeAreaInsets: geometry.safeAreaInsets,
            verticalBarEdge: verticalBarEdge, hinge: hinge,
            occlusions: geometry.occlusions, divisions: geometry.divisions,
            hinges: geometry.hinges,
            usesSidebarShell: usesSidebarShell
        )
        #if DEBUG
        let posed = DebugDuoPose.launch?.apply(to: observed) ?? observed
        #if os(iOS)
        return DebugDuoWindowRemote.shared.window?.apply(to: posed) ?? posed
        #else
        return posed
        #endif
        #else
        return observed
        #endif
    }

    func body(content: Content) -> some View {
        let layout = DeviceLayout.resolve(signals)
        content
            .environment(\.deviceLayout, layout)
            #if DEBUG && os(iOS)
            .overlay(alignment: .bottomLeading) { DebugDuoWindowRemote.Readout(layout: layout) }
            .onAppear { DebugDuoWindowRemote.shared.start() }
            #endif
            .background {
                Color.clear
                    .ignoresSafeArea()
                    .onGeometryChange(for: WindowGeometry.self, of: WindowGeometry.init(proxy:)) {
                        geometry = $0
                    }
                    .modifier(DuoSignalProbe(verticalBarEdge: $verticalBarEdge, hinge: $hinge))
                    .accessibilityHidden(true)
            }
            // A real hinge (not the debug pose override) lets the outer display rotate (O1).
            .onChange(of: hinge, initial: true) { _, newHinge in
                HingePresence.shared.record(hinge: newHinge, verticalBarEdge: verticalBarEdge)
            }
            .onChange(of: verticalBarEdge) { _, newEdge in
                HingePresence.shared.record(hinge: hinge, verticalBarEdge: newEdge)
            }
    }
}

/// Equatable geometry snapshot taken from the full-window probe.
struct WindowGeometry: Sendable, Equatable {
    var size: CGSize = .zero
    var safeAreaInsets = EdgeInsets()
    var occlusions: [CGRect] = []
    var divisions: [CGRect] = []
    /// Every division, active or not: the hinge even while the inner display is flat.
    var hinges: [CGRect] = []

    init() {}

    /// Read size, safe area and (iOS 27.1+) active reserved regions from a proxy that
    /// spans the whole window.
    ///
    /// - Parameter proxy: Geometry of a probe that ignores the safe area.
    init(proxy: GeometryProxy) {
        size = proxy.size
        safeAreaInsets = proxy.safeAreaInsets
        #if os(iOS) && !FST_IOS_SDK_BEFORE_27_1
        if #available(iOS 27.1, *) {
            occlusions = proxy.reservedRegions(kind: .occlusion).filter(\.isActive).map(\.frame)
            divisions = proxy.reservedRegions(kind: .division).filter(\.isActive).map(\.frame)
            hinges = proxy.reservedRegions(kind: .division, options: [.includeInactive]).map(\.frame)
        }
        #endif
    }
}

/// Reads the iOS 27.1 vertical-bar edge and hinge; a no-op on earlier systems.
private struct DuoSignalProbe: ViewModifier {
    @Binding var verticalBarEdge: HorizontalEdge?
    @Binding var hinge: HingeState?

    func body(content: Content) -> some View {
        #if os(iOS) && !FST_IOS_SDK_BEFORE_27_1
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

// App Store archives use the released iOS 27.0 SDK until Xcode 27.1 ships
// (tools/release/ios_appstore_build.sh defines FST_IOS_SDK_BEFORE_27_1).
#if os(iOS) && !FST_IOS_SDK_BEFORE_27_1
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

// MARK: - Debug simulated Duo window

/// A whole simulated iPhone Duo window (size, size classes, hinge and vertical bar) for
/// journeys that must fold and unfold while the app keeps running: neither `simctl` nor
/// XCTest can change the Duo pose, and Device Hub needs UI scripting
/// (`.agents/design/apple/duo.md`, B8). Debug builds only.
///
/// Unlike ``DebugDuoPose`` it replaces the window's geometry too, so the layout model
/// sees the inner display while the real window keeps its size. It is shell evidence
/// (tabs, selection, stacks, UIKit's tab-bar rebuild under real size-class changes), not
/// a capture of the inner display.
enum DebugDuoWindow: String, Sendable, CaseIterable {
    /// Outer display, portrait: compact width, vertical bar on the trailing edge.
    case folded
    /// Inner display, landscape: regular width, the vertical bar stays trailing.
    case unfoldedLandscape = "unfolded-landscape"
    /// Inner display, portrait: regular width, the system horizontal tab bar.
    case unfoldedPortrait = "unfolded-portrait"
    /// Inner display in book pose (partially open, landscape): regular width, the
    /// vertical bar trailing and a vertical fold through the real window's middle (#368).
    case book

    /// Darwin notification name prefix a UI test posts to switch the window.
    static let notificationPrefix = "com.festival.debug.duo-window."

    /// Darwin notification that selects this window.
    var notificationName: String { Self.notificationPrefix + rawValue }

    /// Window size in points (iPhone Duo outer 466×678, inner 951×669).
    var size: CGSize {
        switch self {
        case .folded: CGSize(width: 466, height: 678)
        case .unfoldedLandscape, .book: CGSize(width: 951, height: 669)
        case .unfoldedPortrait: CGSize(width: 669, height: 951)
        }
    }

    /// Horizontal size class: compact outer display, regular inner display.
    var widthClass: WidthClass { self == .folded ? .compact : .regular }

    /// Parse a launch value or a notification name.
    ///
    /// - Parameter raw: `FST_DEBUG_DUO_WINDOW` value, or a full notification name.
    /// - Returns: The window, or nil when absent or unknown.
    static func parse(_ raw: String?) -> DebugDuoWindow? {
        guard let raw else { return nil }
        let value = raw.hasPrefix(notificationPrefix) ? String(raw.dropFirst(notificationPrefix.count)) : raw
        return DebugDuoWindow(rawValue: value)
    }

    /// Replace the window geometry, size classes, hinge and vertical bar in observed signals.
    ///
    /// Book pose places its fold (``DebugDuoPose/foldHeight`` wide) down the middle of the
    /// *real* window's free span (inside its safe area, so beside the vertical bar), so
    /// hinge-aligned layouts (``HingePanes``, hinge columns) split inside the panel the
    /// test can see, with room on both sides, rather than at the simulated inner display's
    /// middle. The readout reports where it lies (`fold=<x>`).
    ///
    /// - Parameter signals: Signals observed from the real window (safe area and shell kept).
    /// - Returns: Signals describing this simulated window.
    func apply(to signals: LayoutSignals) -> LayoutSignals {
        var result = signals
        result.size = size
        result.widthClass = widthClass
        result.heightClass = .regular
        result.verticalBarEdge = self == .unfoldedPortrait ? nil : .trailing
        result.occlusions = []
        result.divisions = []
        result.hinges = []
        switch self {
        case .folded:
            result.hinge = .closed
        case .unfoldedLandscape, .unfoldedPortrait:
            result.hinge = .fullyOpen
        case .book:
            result.hinge = .partiallyOpen
            let measured = signals.size.width > 0 && signals.size.height > 0
            let real = measured ? signals.size : size
            let insets = measured ? signals.safeAreaInsets : EdgeInsets()
            let middle = (max(0, insets.leading) + real.width - max(0, insets.trailing)) / 2
            let fold = CGRect(
                x: middle - DebugDuoPose.foldHeight / 2, y: 0,
                width: DebugDuoPose.foldHeight, height: real.height
            )
            result.divisions = [fold]
            result.hinges = [fold]
        }
        return result
    }
}

#if DEBUG && os(iOS)
/// Switches the simulated ``DebugDuoWindow`` while the app runs, from Darwin
/// notifications a UI test posts (`DuoShellJourneyTests`).
///
/// Enabled by `FST_DEBUG_DUO_WINDOW_REMOTE=1`; `FST_DEBUG_DUO_WINDOW=<window>` picks the
/// first one. Each switch also overrides the root view controllers' size classes, so
/// SwiftUI and the `UITabBarController` behind the `TabView` go through the same trait
/// change a real fold or unfold pushes (the 2026-10-04 tab-rebuild crash path).
@MainActor @Observable
final class DebugDuoWindowRemote {
    /// The process-wide switch.
    static let shared = DebugDuoWindowRemote()

    /// Whether the launch environment enabled the switch.
    static let isEnabled = ProcessInfo.processInfo.environment["FST_DEBUG_DUO_WINDOW_REMOTE"] == "1"

    /// The simulated window, or nil to use the real one.
    private(set) var window: DebugDuoWindow?
    @ObservationIgnored private var started = false

    private init() {
        window = Self.isEnabled ? DebugDuoWindow.parse(ProcessInfo.processInfo.environment["FST_DEBUG_DUO_WINDOW"]) : nil
    }

    /// Observe the switch notifications and apply the launch window's traits (once).
    func start() {
        guard Self.isEnabled, !started else { return }
        started = true
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for window in DebugDuoWindow.allCases {
            CFNotificationCenterAddObserver(center, nil, { _, _, name, _, _ in
                guard let window = DebugDuoWindow.parse(name?.rawValue as String?) else { return }
                Task { @MainActor in DebugDuoWindowRemote.shared.select(window) }
            }, window.notificationName as CFString, nil, .deliverImmediately)
        }
        if let window { applyTraits(window) }
    }

    /// Switch to a simulated window.
    ///
    /// - Parameter window: The window to simulate.
    func select(_ window: DebugDuoWindow) {
        self.window = window
        applyTraits(window)
    }

    /// Override every root view controller's size classes to the window's.
    private func applyTraits(_ window: DebugDuoWindow) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for root in scenes.flatMap(\.windows).compactMap(\.rootViewController) {
            root.traitOverrides.horizontalSizeClass = window.widthClass == .regular ? .regular : .compact
            root.traitOverrides.verticalSizeClass = .regular
        }
    }

    /// The applied window and resolved layout, readable by UI tests
    /// (`fst.shell.debug.duo-window`); empty unless the switch is enabled.
    struct Readout: View {
        let layout: DeviceLayout

        /// ` fold=<x>`: the book-pose fold's centre in window points, when there is one.
        private var foldText: String {
            layout.splitHinge.map { " fold=\(Int($0.midX.rounded()))" } ?? ""
        }

        var body: some View {
            if DebugDuoWindowRemote.isEnabled, let window = DebugDuoWindowRemote.shared.window {
                Text("\(window.rawValue) width=\(layout.widthClass) chrome=\(String(describing: layout.sectionChrome)) regularSet=\(layout.usesRegularSectionSet)\(foldText)")
                    .font(.system(size: 6))
                    .foregroundStyle(.yellow)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("fst.shell.debug.duo-window")
            }
        }
    }
}
#endif
