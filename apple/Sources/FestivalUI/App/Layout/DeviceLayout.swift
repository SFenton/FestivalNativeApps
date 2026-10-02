import CoreGraphics
import SwiftUI

// MARK: - Signals (inputs)

/// Hinge status, mirrored from SwiftUI's `DeviceHinge.Status` (iOS 27.1+) so the pure
/// layout model compiles and tests on every deployment target (iOS 17, macOS 14).
enum HingeState: Sendable, Equatable {
    /// iPhone Duo closed: the app runs on the compact outer display.
    case closed
    /// Between closed and fully open (book, tent or laptop pose, or mid-transition).
    case partiallyOpen
    /// Open as far as the device allows: the app runs on the inner display.
    case fullyOpen
}

/// Horizontal size class reduced to the two values layout decisions use.
enum WidthClass: Sendable, Equatable {
    case compact
    case regular
}

/// Everything the shell can observe about the current window, gathered by
/// `DeviceLayoutPublisher` and resolved by ``DeviceLayout/resolve(_:)``.
///
/// All rectangles are in the window's coordinate space with leading-edge x
/// (SwiftUI mirrors reserved-region geometry for right-to-left by default).
struct LayoutSignals: Sendable, Equatable {
    /// Window size in points.
    var size: CGSize
    /// Horizontal size class (`compact` outer display / iPhone, `regular` inner display / iPad).
    var widthClass: WidthClass
    /// Vertical size class: `regular` on the iPhone Duo inner display (both orientations),
    /// iPad and iPhone portrait; `compact` on iPhone landscape and the Duo outer display
    /// in landscape. Defaults to `regular` for fixtures that only describe width.
    var heightClass: WidthClass = .regular
    /// Window safe-area insets. On iPhone Duo these already include the system vertical bar.
    var safeAreaInsets: EdgeInsets = EdgeInsets()
    /// `EnvironmentValues.toolbarVerticalEdge` (iOS 27.1+): the edge where the system places
    /// the vertical bar, or nil where no vertical bar is ever used (other devices, Duo inner portrait).
    var verticalBarEdge: HorizontalEdge?
    /// Hinge status from `onHingeChange` (iOS 27.1+); nil on devices without a hinge.
    var hinge: HingeState?
    /// Active `ReservedRegion.Kind.occlusion` frames (outer camera / Dynamic Island, active inner camera).
    var occlusions: [CGRect] = []
    /// Active `ReservedRegion.Kind.division` frames (the fold while partially open).
    var divisions: [CGRect] = []
    /// True while the platform shell is the iPad/macOS `NavigationSplitView` sidebar.
    /// Phones (including iPhone Duo) keep the tab shell; see `.agents/design/apple/duo.md`.
    var usesSidebarShell = false
}

// MARK: - Layout (outputs)

/// Pure description of how the shell and its pages should lay out for the current
/// window, derived from size class, safe areas, the system vertical bar, the hinge and
/// reserved regions — never from device names or fixed pixel sizes.
///
/// Decisions (justified in `.agents/design/apple/duo.md`):
/// - Section navigation stays the system `TabView` on every phone pose. On iPhone Duo the
///   system moves it into the vertical bar (folded, and unfolded landscape); the app never
///   draws its own rail.
/// - Regular width (Duo inner display, iPad) shows list/detail pages as two columns.
/// - Custom floating overlays (drawer, scrubber, pinned footers) inset by ``overlayInsets``,
///   which adds camera/Dynamic Island occlusions that the safe area does not cover.
struct DeviceLayout: Sendable, Equatable {
    /// Physical arrangement of the device, as far as the app can observe it.
    enum Pose: Sendable, Equatable {
        /// No hinge and no vertical bar: an ordinary iPhone, iPad or Mac window.
        case standard
        /// iPhone Duo closed (outer display).
        case folded
        /// iPhone Duo fully open (inner display, flat).
        case unfolded
        /// iPhone Duo inner display with an active fold division (book/tent/laptop).
        case partiallyFolded
    }

    /// Window aspect.
    enum Orientation: Sendable, Equatable {
        case portrait
        case landscape
    }

    /// Where root sections (Songs, Leaderboards, …) are presented.
    enum SectionChrome: Sendable, Equatable {
        /// Horizontal system tab bar (iPhone; Duo inner portrait).
        case tabBar
        /// System vertical bar on the given edge (Duo folded, Duo inner landscape).
        case verticalBar(HorizontalEdge)
        /// `NavigationSplitView` sidebar (iPad/macOS shell).
        case sidebar

        /// True for the system vertical bar on either edge.
        var isVerticalBar: Bool {
            if case .verticalBar = self { return true }
            return false
        }
    }

    /// How a page with a list and a detail (Songs → Song Detail, …) is presented.
    enum ContentArrangement: Sendable, Equatable {
        /// One column; the detail is pushed.
        case stack
        /// Two columns side by side (`NavigationSplitView` list/detail).
        case listDetail
        /// Two stacked regions, top and bottom: the page's own content above a second,
        /// related source of information (`DualSourceLayout`). iPhone Duo inner display
        /// in portrait only. **Shelved** (operator, 2026-09-28): produced only while
        /// ``DualSourcePolicy/isEnabled`` is true.
        case dualSource
    }

    let pose: Pose
    let orientation: Orientation
    let widthClass: WidthClass
    let sectionChrome: SectionChrome
    let contentArrangement: ContentArrangement
    /// Insets that keep custom floating overlays clear of system bars *and* hardware
    /// occlusions (the outer camera sits outside the top safe area on iPhone Duo).
    let overlayInsets: EdgeInsets
    /// The active fold region, if the inner display is partially folded.
    let foldFrame: CGRect?
    /// Window safe-area insets (on iPhone Duo they already include the vertical bar).
    var safeAreaInsets = EdgeInsets()
    /// Window size in points (zero before the first geometry pass).
    var size: CGSize = .zero
    /// Vertical size class (see ``LayoutSignals/heightClass``).
    var heightClass: WidthClass = .regular

    /// Regular width *and* regular height: the iPhone Duo inner display in either
    /// orientation, flat or partially folded (HIG Designing for iPhone Duo: "Use size
    /// classes: compact width outer, regular width inner"). A large iPhone in landscape
    /// is regular width but compact height, so it keeps its portrait layout.
    var isRegularInBothDimensions: Bool {
        widthClass == .regular && heightClass == .regular
    }

    /// The part of ``overlayInsets`` that the safe area does not already cover: only
    /// hardware occlusions (the outer camera). Use it for controls laid out *inside*
    /// the safe area (a scrubber in a page's content), where ``overlayInsets`` would
    /// count the vertical bar twice and leave dead space beside it.
    var cutoutInsets: EdgeInsets {
        EdgeInsets(
            top: max(0, overlayInsets.top - safeAreaInsets.top),
            leading: max(0, overlayInsets.leading - safeAreaInsets.leading),
            bottom: max(0, overlayInsets.bottom - safeAreaInsets.bottom),
            trailing: max(0, overlayInsets.trailing - safeAreaInsets.trailing)
        )
    }

    /// Whether `FestivalTabPolicy` should use its regular-width section set
    /// (Leaderboards and Rivals as separate sections, like the web at ≥ 600 px).
    ///
    /// Only the sidebar shell (iPad/macOS) and an iPhone Duo inner display qualify
    /// (operator, 2026-09-28): a large iPhone in landscape is regular width too, but
    /// keeps its portrait tabs (compact height). Decided by size classes, not the
    /// hinge pose (`/duo` D2, 2026-10-02). Only the shelved dual-source arrangement
    /// (``ContentArrangement/dualSource``) would keep the compact set.
    var usesRegularSectionSet: Bool {
        sectionChrome == .sidebar
            || (isRegularInBothDimensions && contentArrangement != .dualSource)
    }

    /// Narrowest column that pages treat as regular width (two-column dashboards,
    /// readable-width containers) inside the iPad sidebar shell.
    static let regularColumnWidth: CGFloat = 600

    /// This layout re-classified for one column of the iPad sidebar shell.
    ///
    /// The window's size class stays regular beside the sidebar and in a list/detail
    /// detail column, but the column may be ~500 pt: pages that pick two card columns
    /// from ``widthClass`` (Leaderboards, Profile) would squeeze them. Each column
    /// instead gets a width class from its own width and never splits again.
    ///
    /// - Parameter width: The column's width in points.
    /// - Returns: The same layout with `widthClass` from `width` and a stack arrangement.
    func column(width: CGFloat) -> DeviceLayout {
        DeviceLayout(
            pose: pose, orientation: orientation,
            widthClass: width >= Self.regularColumnWidth ? .regular : .compact,
            sectionChrome: sectionChrome, contentArrangement: .stack,
            overlayInsets: overlayInsets, foldFrame: foldFrame,
            safeAreaInsets: safeAreaInsets, size: size, heightClass: heightClass
        )
    }

    /// Default before the first geometry pass: an ordinary compact phone.
    static let standardPhone = DeviceLayout(
        pose: .standard, orientation: .portrait, widthClass: .compact,
        sectionChrome: .tabBar, contentArrangement: .stack,
        overlayInsets: EdgeInsets(), foldFrame: nil
    )

    // MARK: Resolution

    /// Map observed window signals to a layout.
    ///
    /// - Parameters:
    ///   - signals: Geometry, size class, vertical bar, hinge and reserved regions.
    ///   - dualSource: Whether inner-display portrait uses the shelved dual-source
    ///     arrangement (``DualSourcePolicy/isEnabled``, off; tests pass true).
    /// - Returns: The layout the shell and pages should adopt.
    static func resolve(_ signals: LayoutSignals, dualSource: Bool = DualSourcePolicy.isEnabled) -> DeviceLayout {
        let bounds = CGRect(origin: .zero, size: signals.size)
        let fold = signals.divisions.first { $0.intersects(bounds) }
        return DeviceLayout(
            pose: pose(for: signals, fold: fold),
            orientation: signals.size.width > signals.size.height ? .landscape : .portrait,
            widthClass: signals.widthClass,
            sectionChrome: chrome(for: signals),
            contentArrangement: arrangement(for: signals, fold: fold, dualSource: dualSource),
            overlayInsets: overlayInsets(
                safeArea: signals.safeAreaInsets, occlusions: signals.occlusions, bounds: bounds
            ),
            foldFrame: fold,
            safeAreaInsets: signals.safeAreaInsets,
            size: signals.size,
            heightClass: signals.heightClass
        )
    }

    /// Derive the pose from the hinge, falling back to the vertical bar when the hinge
    /// is unreported (the bar exists only on iPhone Duo).
    ///
    /// - Parameters:
    ///   - signals: Observed signals.
    ///   - fold: Active division intersecting the window, if any.
    /// - Returns: The observed pose.
    private static func pose(for signals: LayoutSignals, fold: CGRect?) -> Pose {
        if fold != nil { return .partiallyFolded }
        switch signals.hinge {
        case .closed: return .folded
        case .partiallyOpen:
            // Still compact means the outer display mid-transition (or tent mode): keep
            // the folded layout until the inner display takes over.
            return signals.widthClass == .regular ? .partiallyFolded : .folded
        case .fullyOpen: return .unfolded
        case nil:
            guard signals.verticalBarEdge != nil else { return .standard }
            return signals.widthClass == .compact ? .folded : .unfolded
        }
    }

    /// Choose how pages with two related sources arrange them.
    ///
    /// Regular width is list/detail and compact width is one stack. Only with the
    /// shelved dual-source flag does the iPhone Duo inner display in portrait (flat, or
    /// partially open with its fold across the screen) stack two regions instead.
    ///
    /// - Parameters:
    ///   - signals: Observed signals.
    ///   - fold: Active division intersecting the window, if any.
    ///   - dualSource: Whether the dual-source arrangement is enabled.
    /// - Returns: Content arrangement.
    private static func arrangement(for signals: LayoutSignals, fold: CGRect?, dualSource: Bool) -> ContentArrangement {
        let portrait = signals.size.height > signals.size.width
        let inner = pose(for: signals, fold: fold)
        let horizontalFold = fold.map { $0.width >= $0.height } ?? true
        if dualSource, !signals.usesSidebarShell, portrait, horizontalFold, inner == .unfolded || inner == .partiallyFolded {
            return .dualSource
        }
        return signals.widthClass == .regular ? .listDetail : .stack
    }

    /// Choose the section chrome: the platform sidebar shell wins, then the system
    /// vertical bar, otherwise the horizontal tab bar.
    ///
    /// - Parameter signals: Observed signals.
    /// - Returns: Section chrome.
    private static func chrome(for signals: LayoutSignals) -> SectionChrome {
        if signals.usesSidebarShell { return .sidebar }
        if let edge = signals.verticalBarEdge { return .verticalBar(edge) }
        return .tabBar
    }

    /// Grow the safe-area insets so custom overlays also clear each occlusion.
    ///
    /// Each occlusion pushes the edge it is nearest to (by its centre) inward past the
    /// occlusion's far side. Occlusions outside the window are ignored.
    ///
    /// - Parameters:
    ///   - safeArea: Window safe-area insets.
    ///   - occlusions: Active occlusion frames in window coordinates.
    ///   - bounds: Window bounds.
    /// - Returns: Cutout-safe insets.
    static func overlayInsets(safeArea: EdgeInsets, occlusions: [CGRect], bounds: CGRect) -> EdgeInsets {
        var insets = safeArea
        for rect in occlusions {
            let visible = rect.intersection(bounds)
            guard !visible.isNull, !visible.isEmpty else { continue }
            let distances: [(Edge, CGFloat)] = [
                (.top, visible.midY - bounds.minY),
                (.bottom, bounds.maxY - visible.midY),
                (.leading, visible.midX - bounds.minX),
                (.trailing, bounds.maxX - visible.midX),
            ]
            guard let nearest = distances.min(by: { $0.1 < $1.1 })?.0 else { continue }
            switch nearest {
            case .top: insets.top = max(insets.top, visible.maxY - bounds.minY)
            case .bottom: insets.bottom = max(insets.bottom, bounds.maxY - visible.minY)
            case .leading: insets.leading = max(insets.leading, visible.maxX - bounds.minX)
            case .trailing: insets.trailing = max(insets.trailing, bounds.maxX - visible.minX)
            }
        }
        return insets
    }
}
