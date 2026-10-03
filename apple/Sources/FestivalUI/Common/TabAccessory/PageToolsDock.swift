import SwiftUI
import FestivalDesign
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Tab-bar geometry

/// Where the iPhone tab bar's visible glass sits, in window coordinates (pure,
/// unit-tested; issue #89).
///
/// On iOS 26 scrolling down minimizes the tab bar to a circle at the leading edge
/// (`tabBarMinimizeBehavior(.onScrollDown)`), but no public property reports it: the
/// `UITabBar` frame, the content layout guide and the safe areas stay put (measured on
/// iOS 26.5). Only the bar's content platter, its largest visible subview, changes
/// shape: a wide capsule while expanded, a circle while minimized.
struct TabBarGeometry: Equatable, Sendable {
    /// The `UITabBar` frame (full width, including the home-indicator area).
    var bar: CGRect
    /// The visible glass platter holding the tabs.
    var platter: CGRect

    /// Whether the tab bar is minimized to a single round tab.
    ///
    /// The minimized platter is a circle (48 × 48 pt on iOS 26.5); even a two-tab
    /// expanded bar is far wider than tall.
    var isMinimized: Bool {
        platter.width > 0 && platter.width <= platter.height * 1.5
    }

    /// Whether the minimized tab sits on the left edge (left-to-right layouts).
    var platterOnLeft: Bool { platter.midX <= bar.midX }

    /// The platter among a tab bar's direct subviews: the largest visible one.
    ///
    /// - Parameter frames: The visible direct subviews' frames (window coordinates).
    /// - Returns: The largest non-empty frame, or nil when there is none.
    static func platter(among frames: [CGRect]) -> CGRect? {
        frames
            .filter { !$0.isEmpty && $0.width.isFinite && $0.height.isFinite }
            .max { $0.width * $0.height < $1.width * $1.height }
    }

    /// Round to half points so sub-pixel layout noise never re-renders the dock.
    ///
    /// - Returns: The geometry with every edge rounded to 0.5 pt.
    func rounded() -> Self {
        func round(_ rect: CGRect) -> CGRect {
            CGRect(
                x: (rect.minX * 2).rounded() / 2, y: (rect.minY * 2).rounded() / 2,
                width: (rect.width * 2).rounded() / 2, height: (rect.height * 2).rounded() / 2
            )
        }
        return Self(bar: round(bar), platter: round(platter))
    }
}

// MARK: - Dock layout

/// Where the page-tools row sits (pure, unit-tested; issue #89).
///
/// Expanded, the row (search field plus round Sort, Filter and Quick Links buttons) sits
/// just above the tab bar across the width. When scrolling minimizes the tab bar it moves
/// into the tab-bar row beside the minimized tab, like Music's MiniPlayer (HIG Tab bars,
/// iOS: "when minimized, the current tab is at the leading bottom, the accessory is
/// centered"). Coordinates are physical window points (left to right in every language).
struct PageToolsDockLayout: Equatable {
    /// Left edge of the row.
    var minX: CGFloat
    /// Right edge of the row.
    var maxX: CGFloat
    /// Vertical centre of the row.
    var midY: CGFloat
    /// The row sits beside the minimized tab bar.
    var collapsed: Bool

    /// Height of the row and diameter of each round tool (also its square hit region).
    /// Matches the minimized tab's circle; HIG Buttons: "the hit region is at least 44x44 pt".
    static let rowHeight: CGFloat = 48
    /// Gap between neighbouring controls; it keeps their hit regions apart.
    static let spacing: CGFloat = 12
    /// Gap between the expanded row and the tab bar's glass.
    static let gap: CGFloat = 10
    /// Side margins of the expanded row.
    static let margin: CGFloat = 20
    /// Height of the classic tab bar above the home indicator, for the fallback.
    static let fallbackTabBarHeight: CGFloat = 49
    /// Room a page keeps at its bottom for the expanded row (its scroll content ends
    /// above it; trailing overlays such as the A–Z rail stop above it).
    static let pageInset: CGFloat = rowHeight + gap

    /// Row width.
    var width: CGFloat { max(0, maxX - minX) }
    /// Horizontal centre of the row.
    var midX: CGFloat { (minX + maxX) / 2 }

    /// Lay the row out for the tab bar's current shape.
    ///
    /// - Parameters:
    ///   - tabBar: The tab bar's glass, or nil when it was not found (then the row rests
    ///     where a standard tab bar would put it, never over the tabs).
    ///   - container: The window-sized container (window coordinates).
    ///   - bottomSafeArea: The container's bottom safe-area inset (home indicator).
    /// - Returns: The row's frame.
    static func resolve(
        tabBar: TabBarGeometry?, container: CGRect, bottomSafeArea: CGFloat
    ) -> Self {
        guard let tabBar, !tabBar.platter.isEmpty else {
            let barTop = container.maxY - bottomSafeArea - fallbackTabBarHeight
            return Self(
                minX: container.minX + margin, maxX: container.maxX - margin,
                midY: barTop - gap - rowHeight / 2, collapsed: false
            )
        }
        let bar = tabBar.bar
        let platter = tabBar.platter
        guard tabBar.isMinimized else {
            return Self(
                minX: bar.minX + margin, maxX: bar.maxX - margin,
                midY: platter.minY - gap - rowHeight / 2, collapsed: false
            )
        }
        // The far margin mirrors the minimized tab's own inset from its edge.
        if tabBar.platterOnLeft {
            return Self(
                minX: platter.maxX + spacing, maxX: bar.maxX - (platter.minX - bar.minX),
                midY: platter.midY, collapsed: true
            )
        }
        return Self(
            minX: bar.minX + (bar.maxX - platter.maxX), maxX: platter.minX - spacing,
            midY: platter.midY, collapsed: true
        )
    }
}

// MARK: - Dock

/// The front page's tools as one row of separate Liquid Glass controls: a search field
/// capsule (Songs) followed by round icon-only buttons (Sort, Filter, Quick Links), on
/// iOS 26.1+ iPhone (issue #89).
///
/// It overlays the root `TabView` rather than living in the system
/// `tabViewBottomAccessory`: the accessory is always one full-width capsule, so tools
/// beside the search field ended up inside it. Each page shows only the controls it
/// registered; with no field the buttons align trailing.
///
/// Like the tab bar and the system bottom accessory it replaces, the row is
/// fixed-height, so text stops growing at ``maxTypeSize``; long-pressing a control
/// shows the Large Content Viewer instead (`accessibilityShowsLargeContentViewer`).
struct PageToolsDock: View {
    let registry: TabAccessoryRegistry

    /// The largest Dynamic Type size the fixed-height row lays out.
    static let maxTypeSize = DynamicTypeSize.xxxLarge

    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false

    var body: some View {
        let items = registry.dockSuppressed ? [] : registry.frontItems
        let style = PageToolsHandOff.style(
            systemReduceMotion: systemReduceMotion, appReduceMotion: appReduceMotion
        )
        GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            let layout = PageToolsDockLayout.resolve(
                tabBar: registry.tabBar, container: frame,
                bottomSafeArea: proxy.safeAreaInsets.bottom
            )
            row(items, style: style)
                .environment(\.layoutDirection, layoutDirection)
                .frame(width: layout.width, height: PageToolsDockLayout.rowHeight)
                .position(x: layout.midX - frame.minX, y: layout.midY - frame.minY)
                // Follows the tab bar as it minimizes and expands; under Reduce Motion
                // it moves without animating (HIG Accessibility: "reduce automatic and
                // repetitive animation, including zooming, scaling, and peripheral motion").
                .animation(style == .motion ? .smooth(duration: 0.35) : nil, value: layout)
        }
        .ignoresSafeArea()
        // Positions are physical window points; the row restores the reading direction.
        .environment(\.layoutDirection, .leftToRight)
        .animation(PageToolsHandOff.animation(style), value: items.map(\.id))
        .dynamicTypeSize(...Self.maxTypeSize)
    }

    /// The controls, leading to trailing.
    @ViewBuilder
    private func row(_ items: [TabAccessoryRegistry.Entry], style: PageToolsHandOff.Style) -> some View {
        let hasField = items.contains { $0.kind == .field }
        FestivalGlassGroup(spacing: PageToolsDockLayout.spacing) {
            HStack(spacing: PageToolsDockLayout.spacing) {
                if !hasField { Spacer(minLength: 0) }
                ForEach(items, id: \.id) { item in
                    switch item.kind {
                    case .field:
                        // A field sets its own identifiers: one applied here would
                        // replace its inner buttons' (open, clear).
                        item.content
                            .font(.body)
                            .padding(.horizontal, 6)
                            .frame(maxWidth: .infinity)
                            .frame(height: PageToolsDockLayout.rowHeight)
                            .festivalGlassCapsule(.control, interactive: true)
                            .transition(.opacity)
                    case .tool:
                        let side = PageToolsDockLayout.rowHeight
                        item.content
                            .labelStyle(FloatingPageToolLabelStyle(side: side))
                            .font(.title3)
                            .frame(width: side, height: side)
                            .contentShape(Rectangle())
                            .festivalGlassCapsule(.control, interactive: true)
                            .accessibilityIdentifier(item.accessibilityID ?? "")
                            .accessibilityShowsLargeContentViewer()
                            .transition(PageToolsHandOff.dockTransition(style))
                    }
                }
            }
        }
        .tint(BrandTokens.textPrimary)
    }
}

// MARK: - Tab-bar watcher

#if os(iOS)
/// Reports the iPhone tab bar's ``TabBarGeometry`` to the registry whenever it changes,
/// so ``PageToolsDock`` follows it as it minimizes and expands (issue #89).
///
/// Uses public `UIView` API only: it finds the window's visible `UITabBar` and reads its
/// largest visible subview's frame. The bar re-arranges its layers whenever it changes
/// shape, so key-value observing its layer's `sublayers` starts a short burst of
/// per-frame samples; a slow background sample is a safety net. Without a tab bar the
/// registry gets nil and the dock rests where a standard tab bar would put it.
struct TabBarWatcher: UIViewRepresentable {
    let report: @MainActor (TabBarGeometry?) -> Void

    func makeUIView(context: Context) -> TabBarWatcherView {
        let view = TabBarWatcherView()
        view.report = report
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: TabBarWatcherView, context: Context) {
        view.report = report
        view.beginBurst()
    }

    static func dismantleUIView(_ view: TabBarWatcherView, coordinator: ()) {
        view.stop()
    }
}

/// The UIKit half of ``TabBarWatcher``.
final class TabBarWatcherView: UIView {
    var report: (@MainActor (TabBarGeometry?) -> Void)?

    /// Samples per second while the tab bar is changing shape.
    static let burstRate: Float = 60
    /// Samples per second otherwise (the safety net for a missed change).
    static let idleRate: Float = 4
    /// How long a burst samples after its last trigger, in seconds.
    static let burstDuration: CFTimeInterval = 1.0

    private weak var tabBar: UITabBar?
    private var sublayersObservation: NSKeyValueObservation?
    private var displayLink: CADisplayLink?
    private var burstUntil: CFTimeInterval = 0
    private var lastSearch: CFTimeInterval = -.infinity
    private var lastReported: TabBarGeometry??

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stop()
        } else {
            beginBurst()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        beginBurst()
    }

    /// Sample every frame for a moment (the tab bar may be changing shape).
    func beginBurst() {
        guard window != nil else { return }
        burstUntil = CACurrentMediaTime() + Self.burstDuration
        if displayLink == nil {
            let link = CADisplayLink(target: DisplayLinkTarget(self), selector: #selector(DisplayLinkTarget.tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        setRate(Self.burstRate)
        sample()
    }

    /// Stop sampling and forget the tab bar.
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        sublayersObservation = nil
        tabBar = nil
        lastReported = nil
    }

    fileprivate func tick() {
        sample()
        if CACurrentMediaTime() > burstUntil { setRate(Self.idleRate) }
    }

    private func setRate(_ rate: Float) {
        guard let displayLink, displayLink.preferredFrameRateRange.preferred != rate else { return }
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
    }

    private func sample() {
        let geometry = currentTabBar().flatMap(Self.geometry(of:))
        if lastReported != .some(geometry) {
            lastReported = .some(geometry)
            report?(geometry)
        }
    }

    /// The window's visible tab bar, re-found when the cached one left the window.
    private func currentTabBar() -> UITabBar? {
        guard let window else { return nil }
        if let tabBar, tabBar.window === window { return tabBar }
        // Searching the whole window is cheap but not free: at most twice a second.
        let now = CACurrentMediaTime()
        guard now - lastSearch > 0.5 else { return nil }
        lastSearch = now
        let found = Self.findTabBar(in: window)
        tabBar = found
        sublayersObservation = found?.layer.observe(\.sublayers, options: []) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.beginBurst() }
        }
        return found
    }

    /// The first visible `UITabBar` below `root`, breadth first.
    private static func findTabBar(in root: UIView) -> UITabBar? {
        var queue: [UIView] = [root]
        var index = 0
        while index < queue.count {
            let view = queue[index]
            index += 1
            if let bar = view as? UITabBar, !bar.isHidden, bar.alpha > 0.01 { return bar }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }

    /// The bar and its platter in window coordinates; nil while hidden.
    private static func geometry(of bar: UITabBar) -> TabBarGeometry? {
        guard !bar.isHidden, bar.alpha > 0.01, bar.window != nil else { return nil }
        let frames = bar.subviews
            .filter { !$0.isHidden && $0.alpha > 0.01 }
            .map { $0.convert($0.bounds, to: nil) }
        guard let platter = TabBarGeometry.platter(among: frames) else { return nil }
        return TabBarGeometry(bar: bar.convert(bar.bounds, to: nil), platter: platter).rounded()
    }
}

/// Weak display-link target, so the link never keeps the watcher alive.
private final class DisplayLinkTarget: NSObject {
    weak var view: TabBarWatcherView?

    init(_ view: TabBarWatcherView) {
        self.view = view
    }

    @MainActor @objc func tick() {
        view?.tick()
    }
}
#endif
