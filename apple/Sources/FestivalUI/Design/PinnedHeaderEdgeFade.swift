import FestivalCore
import SwiftUI

// MARK: - Pinned header edge fade

/// The one way rows fade out under a pinned section title, on every Apple platform
/// (`.agents/patterns/scroll-edge.md` R2, R5; issue #308).
///
/// Rows are fully transparent at the pinned title's bottom edge and fully drawn
/// ``height`` points below it, on a linear ramp (the web's `useScrollMask`, 40 px). The
/// title itself is never masked or dimmed. At rest nothing is dimmed: the fade's depth
/// grows 1:1 with how far rows have scrolled under the title, like the web's `atTop`
/// switch and the system soft scroll-edge effect. Reduce Transparency and Increase
/// Contrast (system or in-app) turn the ramp into a hard edge (R7).
///
/// Two layouts draw pinned titles, and both mask rows with ``PinnedHeaderFadeMask``:
///
/// - **Songs** (iOS 26 and later) draws its own floating section bar over the List and
///   masks the whole List under it (``SwiftUI/View/pinnedHeaderEdgeFadeMask(edge:active:depthLimit:)``,
///   issues #10, #298).
/// - **Sheet lists** (Notifications) use the List's native pinned section headers, so
///   each row masks itself (``SwiftUI/View/pinnedHeaderEdgeFadeRow(_:first:background:)``,
///   issue #301). A single mask over the whole List cannot show the header while hiding
///   the rows behind it. ``ModalTopEdgeFadeModifier`` yields to that row fade with a hard
///   edge under the sheet header, so its own ramp never dims the pinned header.
///
/// For native pinned headers iOS also puts a gap (22 pt on iOS 26) above the first
/// header, so that header rested lower and slid up through the gap before pinning.
/// ``lift(contentTop:pinLine:layout:)`` draws the first header at its pinned position
/// from the start while the empty gap scrolls away; the List's layout is unchanged.
///
/// Sheet-list positions are measured from the top of the List's scroll view, which
/// reaches up under the sheet header by the pin line (its top content inset). The pin
/// line and scroll offset come from `onScrollGeometryChange` on iOS 18 / macOS 15 and
/// later, and from the List's platform scroll view (``PlatformScrollObserver``) on
/// iOS 17 / macOS 14, so every supported system grows the same 40 pt ramp.
enum PinnedHeaderEdgeFade {
    /// Distance below the pinned title's bottom edge over which rows fade in, in points:
    /// ``ScrollEdgeFade/topDistance`` (web `useScrollMask`, 40 px).
    static let height = CGFloat(ScrollEdgeFade.topDistance)

    /// Whether sheet lists read their scroll position from the platform scroll view
    /// (``PlatformScrollObserver``) because `onScrollGeometryChange` is missing: iOS 17
    /// and macOS 14, or `FST_DEBUG_LEGACY_SCROLL_GEOMETRY=1` in Debug builds, which
    /// exercises that path on a newer simulator.
    static var usesLegacyScrollTracking: Bool { ScrollEdgeTracking.usesLegacyPath }

    /// The fade height for the current accessibility settings.
    ///
    /// - Parameter hardEdge: Reduce Transparency or Increase Contrast (system or in-app)
    ///   is on (``ScrollEdgeHardEdge``).
    /// - Returns: ``height``, or 0 (a hard edge).
    static func height(hardEdge: Bool) -> CGFloat {
        CGFloat(ScrollEdgeFade.ramp(ScrollEdgeFade.topDistance, hardEdge: hardEdge))
    }

    /// Row opacity at a fraction of the way through the fade: linear, like the web mask.
    ///
    /// - Parameter progress: 0 at the title's bottom edge, 1 at the end of the fade;
    ///   clamped to that range.
    /// - Returns: The mask opacity, 0 to 1.
    static func opacity(at progress: CGFloat) -> Double {
        progress.isFinite ? Double(min(max(progress, 0), 1)) : 0
    }

    /// The mask gradient's stops: clear at the title's edge, opaque at the fade's end.
    static let gradientStops: [Gradient.Stop] = [
        Gradient.Stop(color: .black.opacity(opacity(at: 0)), location: 0),
        Gradient.Stop(color: .black.opacity(opacity(at: 1)), location: 1),
    ]

    /// Largest believable system padding around a header's content.
    static let maximumHeaderInset: CGFloat = 24
    /// Largest believable gap above the first header.
    static let maximumHeaderGap: CGFloat = 48

    /// How the List lays out its first section header, read at rest.
    struct HeaderLayout: Equatable {
        /// System padding above (and, centred, below) a header's content: the pinned band
        /// is the content plus this on each side.
        var inset: CGFloat
        /// Empty space the List leaves above the first header's band.
        var gap: CGFloat
    }

    /// Read the first header's layout while the List rests at its top.
    ///
    /// The List centres a header's content in a taller band (10 pt above and below on
    /// iOS 26, 7 pt in macOS 26's 28 pt minimum) and starts the section's first row cell
    /// right under that band.
    ///
    /// - Parameters:
    ///   - headerTop: Top of the first header's content.
    ///   - headerHeight: Height of that content.
    ///   - firstRowTop: Top of the section's first row cell (its row background; the row
    ///     content itself starts lower, by the row insets), or nil before it is measured
    ///     (then the band is assumed to start on the pin line, with no gap).
    ///   - pinLine: Where headers pin (the scroll view's top content inset).
    /// - Returns: The layout, or nil for an unbelievable reading.
    static func headerLayout(
        headerTop: CGFloat, headerHeight: CGFloat, firstRowTop: CGFloat?, pinLine: CGFloat
    ) -> HeaderLayout? {
        guard headerTop.isFinite, headerHeight.isFinite, headerHeight > 0, pinLine.isFinite else { return nil }
        let inset: CGFloat
        if let firstRowTop {
            guard firstRowTop.isFinite else { return nil }
            inset = firstRowTop - headerTop - headerHeight
        } else {
            inset = headerTop - pinLine
        }
        let gap = headerTop - inset - pinLine
        guard inset >= -0.5, inset <= maximumHeaderInset, gap >= -0.5, gap <= maximumHeaderGap else { return nil }
        return HeaderLayout(inset: max(0, inset), gap: max(0, gap))
    }

    /// Bottom edge of the pinned section header band.
    ///
    /// - Parameters:
    ///   - pinLine: Where headers pin.
    ///   - headerHeight: Height of a header's content; 0 when the List has no visible
    ///     headers.
    ///   - headerInset: The system padding above (and below) that content.
    /// - Returns: The edge rows must have faded out by; negative or non-finite readings
    ///   count as 0, and the inset only counts with a header.
    static func edge(pinLine: CGFloat, headerHeight: CGFloat, headerInset: CGFloat = 0) -> CGFloat {
        let line = pinLine.isFinite ? max(0, pinLine) : 0
        let header = headerHeight.isFinite ? max(0, headerHeight) : 0
        let inset = header > 0 && headerInset.isFinite ? min(max(0, headerInset), maximumHeaderInset) : 0
        return line + header + 2 * inset
    }

    /// How far to draw the first header above its laid-out position, so it sits where it
    /// will pin while the gap above it scrolls away.
    ///
    /// - Parameters:
    ///   - contentTop: Laid-out top of the first header's content.
    ///   - pinLine: Where headers pin.
    ///   - layout: The first header's layout.
    /// - Returns: 0 once pinned (or with no gap), at most `layout.gap`; 0 for non-finite
    ///   readings.
    static func lift(contentTop: CGFloat, pinLine: CGFloat, layout: HeaderLayout) -> CGFloat {
        guard contentTop.isFinite, pinLine.isFinite else { return 0 }
        return min(max(0, layout.gap), max(0, contentTop - layout.inset - pinLine))
    }

    /// How deep the fade below the edge has grown.
    ///
    /// - Parameters:
    ///   - scrollOffset: Distance scrolled from the List's resting top (content offset
    ///     plus top inset); negative while pulled down past the top.
    ///   - fade: Full fade height for the current accessibility settings
    ///     (``height(hardEdge:)``).
    /// - Returns: 0 at rest, growing 1:1 with scrolling up to `fade`; 0 for non-finite
    ///   readings.
    static func depth(scrollOffset: CGFloat, fade: CGFloat) -> CGFloat {
        guard scrollOffset.isFinite, fade.isFinite else { return 0 }
        return min(max(scrollOffset, 0), max(fade, 0))
    }

    /// Where a row's mask starts, in the row's own coordinates.
    ///
    /// - Parameters:
    ///   - rowTop: The row's top edge.
    ///   - edge: The pinned header's bottom edge (``edge(pinLine:headerHeight:headerInset:)``).
    ///   - depth: Current fade depth (``depth(scrollOffset:fade:)``).
    /// - Returns: Points from the row's top down to the edge (negative when the edge is
    ///   above the row), or nil when no part of the row reaches the edge or the fade, so
    ///   the row needs no mask.
    static func cut(rowTop: CGFloat, edge: CGFloat, depth: CGFloat) -> CGFloat? {
        guard rowTop.isFinite, edge.isFinite else { return nil }
        let cut = edge - rowTop
        return cut > -max(depth, 0) && (cut > 0 || depth > 0) ? cut : nil
    }

    /// Thickness of a row separator, in points: the system List separator's (1 pt on iOS
    /// 26 and macOS 26 alike, measured on both).
    static let separatorThickness: CGFloat = 1

    /// Where a row's separator runs across its row background, in the background's own
    /// coordinates (issue #322).
    ///
    /// The system List draws the separator from the row's separator-leading guide (the
    /// leading edge of its text) to its separator-trailing guide (the content's trailing
    /// edge) on iOS, and on to the row's own trailing edge on macOS. The row draws it the
    /// same way, inside its masked background, so the separator fades with its row instead
    /// of passing under a pinned title.
    ///
    /// - Parameters:
    ///   - leading: Global x of the row content's `.listRowSeparatorLeading` guide.
    ///   - trailing: Global x of its `.listRowSeparatorTrailing` guide.
    ///   - background: Global frame of the row background (the whole cell).
    ///   - toRowEdge: Whether the separator runs on to the row's trailing edge (macOS).
    ///   - rightToLeft: Whether the row lays out right to left (its trailing edge is the
    ///     background's left edge).
    /// - Returns: The separator's left and right ends in the background's coordinates
    ///   (left to right in either layout direction), or nil for non-finite or empty
    ///   readings.
    static func separatorSpan(
        leading: CGFloat, trailing: CGFloat, background: CGRect,
        toRowEdge: Bool = false, rightToLeft: Bool = false
    ) -> ClosedRange<CGFloat>? {
        guard leading.isFinite, trailing.isFinite, background.minX.isFinite, background.width.isFinite
        else { return nil }
        let end = toRowEdge ? (rightToLeft ? background.minX : background.maxX) : trailing
        let left = min(leading, end) - background.minX
        let right = max(leading, end) - background.minX
        return right - left >= 1 ? left...right : nil
    }

    /// Whether this platform's List runs a row separator on to the row's trailing edge
    /// (AppKit table rows do; UIKit list cells stop at the content's trailing edge).
    static var separatorRunsToRowEdge: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }
}

// MARK: - Shared state

/// Live readings shared by a List, its pinned headers and its rows (issue #301).
///
/// Rows and headers measure themselves in global coordinates and subtract ``origin``:
/// inside an iOS List's cells the `.scrollView` coordinate space does not reach the
/// List's scroll view. Only the row masks and the first header read it, so a scroll or a
/// measurement re-renders those small modifiers, never the rows themselves.
@MainActor @Observable
final class PinnedHeaderEdgeFadeState {
    /// Whether the scroll position comes from the List's platform scroll view
    /// (``PinnedHeaderEdgeFade/usesLegacyScrollTracking``) instead of
    /// `onScrollGeometryChange`.
    let legacyScrollTracking: Bool
    /// The scroll view's top content inset, where headers pin.
    fileprivate(set) var pinLine: CGFloat = 0
    /// The List's top edge in global coordinates. SwiftUI lays the List out inside the
    /// safe area, so this is where headers pin; its scroll view reaches up under the
    /// modal header by the top content inset.
    fileprivate(set) var listTop: CGFloat = 0
    /// Height of a header's content, or 0 while the List shows none.
    fileprivate(set) var headerHeight: CGFloat = 0
    /// The first header's layout, once read at rest.
    fileprivate(set) var headerLayout = PinnedHeaderEdgeFade.HeaderLayout(inset: 0, gap: 0)
    /// Current fade depth below the header.
    fileprivate(set) var depth: CGFloat = 0
    /// Last measured content height, kept while headers are hidden.
    @ObservationIgnored fileprivate var measuredHeaderHeight: CGFloat = 0
    /// Whether the List currently shows section headers.
    @ObservationIgnored fileprivate var showsHeaders = true
    /// Last scroll offset from the List's resting top, or nil where it cannot be read.
    @ObservationIgnored private var scrollOffset: CGFloat?
    /// Last laid-out global top of the first header's content.
    @ObservationIgnored private var firstHeaderTop: CGFloat?
    /// Last global top of the first section's first row cell.
    @ObservationIgnored private var firstRowTop: CGFloat?
    /// Whether ``headerLayout`` has been read, and whether with a first row.
    @ObservationIgnored private var layoutMeasured = false
    @ObservationIgnored private var layoutMeasuredWithRow = false
    /// Full fade height for the current accessibility settings.
    @ObservationIgnored private var fade = PinnedHeaderEdgeFade.height
    /// Follows the List's platform scroll view when ``legacyScrollTracking`` is on.
    @ObservationIgnored private var legacyObserver: PlatformScrollObserver?
    /// Rows report their top only above this global line (the edge plus the full fade and
    /// some slack), so rows far below the header never update while scrolling.
    let rowLimit = TopInset()

    /// Shared readings for one List.
    ///
    /// - Parameter legacyScrollTracking: Read the scroll position from the List's platform
    ///   scroll view; tests set it to cover the iOS 17 / macOS 14 path on newer systems.
    init(legacyScrollTracking: Bool = PinnedHeaderEdgeFade.usesLegacyScrollTracking) {
        self.legacyScrollTracking = legacyScrollTracking
    }

    /// The scroll view's top edge in global coordinates: positions in
    /// ``PinnedHeaderEdgeFade`` are measured from here.
    var origin: CGFloat { listTop - pinLine }

    /// The pinned header band's bottom edge, below ``origin``.
    var edge: CGFloat {
        PinnedHeaderEdgeFade.edge(pinLine: pinLine, headerHeight: headerHeight, headerInset: headerLayout.inset)
    }

    fileprivate func setPinLine(_ value: CGFloat) {
        guard value.isFinite else { return }
        if value != pinLine { pinLine = value }
        updateLayout()
    }

    fileprivate func setListTop(_ value: CGFloat) {
        guard value.isFinite else { return }
        if value != listTop { listTop = value }
        updateLayout()
    }

    fileprivate func setScrollOffset(_ value: CGFloat) {
        scrollOffset = value
        updateLayout()
        applyDepth()
    }

    /// Apply one scroll reading: the pin line and the distance scrolled from the top.
    fileprivate func setScroll(inset: CGFloat, offset: CGFloat) {
        setPinLine(inset)
        setScrollOffset(offset)
    }

    /// Use the top safe-area inset as the pin line until the scroll position is known.
    fileprivate func setFallbackPinLine(_ value: CGFloat) {
        guard scrollOffset == nil else { return }
        setPinLine(value)
    }

    fileprivate func setFade(_ value: CGFloat) {
        fade = value
        applyDepth()
    }

    private func applyDepth() {
        let value = PinnedHeaderEdgeFade.depth(scrollOffset: scrollOffset ?? 0, fade: fade)
        if value != depth { depth = value }
    }

    /// Follow the List's platform scroll view (``legacyScrollTracking`` only).
    fileprivate func attachLegacyScrollView(_ scrollView: ListPlatformScrollView) {
        guard legacyScrollTracking else { return }
        let observer = legacyObserver ?? PlatformScrollObserver { [weak self] reading in
            self?.setScroll(inset: reading.inset, offset: reading.offset)
        }
        legacyObserver = observer
        observer.attach(scrollView)
    }

    fileprivate func setHeaderHeight(_ value: CGFloat) {
        measuredHeaderHeight = value
        applyHeaderHeight()
    }

    fileprivate func setFirstHeaderTop(_ value: CGFloat) {
        firstHeaderTop = value
        updateLayout()
    }

    fileprivate func setFirstRowTop(_ value: CGFloat) {
        firstRowTop = value
        updateLayout()
    }

    fileprivate func setShowsHeaders(_ value: Bool) {
        showsHeaders = value
        applyHeaderHeight()
    }

    /// Test seam: apply readings as the modifiers would. Positions are global.
    ///
    /// - Parameters:
    ///   - pinLine: Scroll view top content inset.
    ///   - headerHeight: A header content measurement, or nil for none.
    ///   - showsHeaders: Whether the List shows headers.
    ///   - listTop: The List's global top, or nil to keep the last one.
    ///   - scrollOffset: Scroll offset from the resting top, or nil for no reading.
    ///   - firstHeaderTop: The first header content's laid-out top, or nil for no reading.
    ///   - firstRowTop: The first row cell's top, or nil for no reading.
    ///   - fade: The full fade height, or nil to keep the current one.
    func testSet(
        pinLine: CGFloat, headerHeight: CGFloat?, showsHeaders: Bool, listTop: CGFloat? = nil,
        scrollOffset: CGFloat? = nil, firstHeaderTop: CGFloat? = nil, firstRowTop: CGFloat? = nil,
        fade: CGFloat? = nil
    ) {
        if let fade { setFade(fade) }
        if let listTop { setListTop(listTop) }
        setPinLine(pinLine)
        if let headerHeight { setHeaderHeight(headerHeight) }
        setShowsHeaders(showsHeaders)
        if let scrollOffset { setScrollOffset(scrollOffset) }
        if let firstRowTop { setFirstRowTop(firstRowTop) }
        if let firstHeaderTop { setFirstHeaderTop(firstHeaderTop) }
    }

    private func applyHeaderHeight() {
        let value = showsHeaders ? measuredHeaderHeight : 0
        if value != headerHeight { headerHeight = value }
        updateLayout()
    }

    /// Re-read the first header's layout while the List rests at its top. Where the scroll
    /// offset is unknown (iOS 17 / macOS 14) only the first readings count, as the sheet
    /// opens at its top: the first one, then the first one with the first row.
    private func updateLayout() {
        defer { updateRowLimit() }
        guard let firstHeaderTop else { return }
        if let scrollOffset {
            guard abs(scrollOffset) <= 0.5 else { return }
        } else if layoutMeasuredWithRow || (layoutMeasured && firstRowTop == nil) {
            return
        }
        guard let layout = PinnedHeaderEdgeFade.headerLayout(
            headerTop: firstHeaderTop - origin, headerHeight: measuredHeaderHeight,
            firstRowTop: firstRowTop.map { $0 - origin }, pinLine: pinLine
        ) else { return }
        layoutMeasured = true
        if firstRowTop != nil { layoutMeasuredWithRow = true }
        if layout != headerLayout { headerLayout = layout }
    }

    private func updateRowLimit() {
        rowLimit.value = origin + PinnedHeaderEdgeFade.edge(
            pinLine: pinLine, headerHeight: max(headerHeight, measuredHeaderHeight),
            headerInset: headerLayout.inset
        ) + PinnedHeaderEdgeFade.height + 24
    }
}

// MARK: - Modifiers

extension View {
    /// Keep this `List`'s pinned section headers still and fade its rows out before they
    /// reach them, inside a ``FestivalModal`` (issue #301). Pair it with
    /// ``pinnedHeaderEdgeFadeHeader(_:first:)`` on each header and
    /// ``pinnedHeaderEdgeFadeRow(_:first:background:)`` on each row.
    ///
    /// Turns the modal's own top fade into a hard edge (the rows fade themselves, and the
    /// modal's ramp would otherwise dim the pinned header).
    ///
    /// - Parameters:
    ///   - state: Readings shared with the headers and rows.
    ///   - showsHeaders: Whether any section header is visible.
    /// - Returns: The List with its pin line and scroll depth tracked.
    func pinnedHeaderEdgeFadeList(_ state: PinnedHeaderEdgeFadeState, showsHeaders: Bool) -> some View {
        modifier(PinnedHeaderListModifier(state: state, showsHeaders: showsHeaders))
    }

    /// Measure this pinned section header for ``pinnedHeaderEdgeFadeList(_:showsHeaders:)``;
    /// the first header is also drawn at its pinned position from the start.
    ///
    /// - Parameters:
    ///   - state: Readings shared with the List and its rows.
    ///   - first: Whether this is the List's first header.
    /// - Returns: The header, reporting its content's height (and, when first, its top).
    func pinnedHeaderEdgeFadeHeader(_ state: PinnedHeaderEdgeFadeState, first: Bool) -> some View {
        modifier(PinnedSectionHeaderModifier(state: state, first: first))
    }

    /// Fade this row, its row background and its separator out before they reach the
    /// List's pinned section header.
    ///
    /// The system separator is drawn outside any SwiftUI mask, so it would pass under the
    /// pinned header (issue #322). The row hides it and draws the same line, from its
    /// `.listRowSeparatorLeading` to its `.listRowSeparatorTrailing` guide at the bottom
    /// of its cell, in its masked row background.
    ///
    /// - Parameters:
    ///   - state: Readings shared with the List and its headers.
    ///   - first: Whether this is the first row of the List's first section. Its row
    ///     background, which fills the row's whole cell, measures where the cell starts:
    ///     right under the first header's band.
    ///   - background: The row background (`listRowBackground`).
    /// - Returns: The row, masked near the header.
    func pinnedHeaderEdgeFadeRow(
        _ state: PinnedHeaderEdgeFadeState, first: Bool = false, background: some View = Color.clear
    ) -> some View {
        modifier(PinnedHeaderRowModifier(state: state, first: first, background: background))
    }
}

/// One row of a pinned-header sheet list: masks the row content and its background (with
/// the row's own separator) under the pinned header.
private struct PinnedHeaderRowModifier<Background: View>: ViewModifier {
    let state: PinnedHeaderEdgeFadeState
    let first: Bool
    let background: Background
    /// Global x of the content's `.listRowSeparatorLeading` guide.
    @State private var leadingGuide: CGFloat?
    /// Global x of the content's `.listRowSeparatorTrailing` guide.
    @State private var trailingGuide: CGFloat?
    /// Global frame of the row background (the whole cell).
    @State private var backgroundFrame: CGRect?
    @Environment(\.layoutDirection) private var layoutDirection

    func body(content: Content) -> some View {
        let span = leadingGuide.flatMap { leading in
            trailingGuide.flatMap { trailing in
                backgroundFrame.flatMap {
                    PinnedHeaderEdgeFade.separatorSpan(
                        leading: leading, trailing: trailing, background: $0,
                        toRowEdge: PinnedHeaderEdgeFade.separatorRunsToRowEdge,
                        rightToLeft: layoutDirection == .rightToLeft
                    )
                }
            }
        }
        content
            .overlay(alignment: Alignment(horizontal: .listRowSeparatorLeading, vertical: .top)) {
                SeparatorGuideMarker { leadingGuide = $0 }
            }
            .overlay(alignment: Alignment(horizontal: .listRowSeparatorTrailing, vertical: .top)) {
                SeparatorGuideMarker { trailingGuide = $0 }
            }
            .modifier(PinnedHeaderRowMask(state: state))
            .listRowSeparator(.hidden)
            .listRowBackground(
                background
                    .overlay(alignment: .bottomLeading) { PinnedHeaderRowSeparator(span: span) }
                    .modifier(PinnedHeaderRowMask(state: state, locatesScrollView: false))
                    .background {
                        Color.clear
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                                backgroundFrame = $0
                            }
                            .accessibilityHidden(true)
                    }
                    .background {
                        if first {
                            Color.clear
                                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: {
                                    state.setFirstRowTop($0)
                                }
                                .accessibilityHidden(true)
                        }
                    }
            )
    }
}

/// A zero-width marker that reports its global x: placed on one of a row's separator
/// guides, it reads where the List would start or end the row's separator. The x does
/// not change while scrolling, so it settles once per row layout.
private struct SeparatorGuideMarker: View {
    let onChange: (CGFloat) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { onChange($0) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The row separator drawn inside a pinned-header row's masked background.
private struct PinnedHeaderRowSeparator: View {
    /// Left and right ends in the background's coordinates; nil draws nothing.
    let span: ClosedRange<CGFloat>?

    var body: some View {
        PinnedHeaderRowSeparatorShape(span: span)
            .fill(Self.color)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The system separator color (the List's own separator color).
    static var color: Color {
        #if canImport(UIKit)
        Color(uiColor: .separator)
        #else
        Color(nsColor: .separatorColor)
        #endif
    }
}

/// A ``PinnedHeaderEdgeFade/separatorThickness`` line along the bottom of its frame,
/// across `span`. Shapes are not mirrored in right-to-left layouts, so the span's
/// left-to-right ends stay true in both directions.
private struct PinnedHeaderRowSeparatorShape: Shape {
    let span: ClosedRange<CGFloat>?

    func path(in rect: CGRect) -> Path {
        guard let span else { return Path() }
        let thickness = PinnedHeaderEdgeFade.separatorThickness
        return Path(CGRect(
            x: rect.minX + span.lowerBound, y: rect.maxY - thickness,
            width: span.upperBound - span.lowerBound, height: thickness
        ))
    }
}

/// Tracks the List's position, pin line and fade depth, and hands the modal a hard top
/// edge.
private struct PinnedHeaderListModifier: ViewModifier {
    let state: PinnedHeaderEdgeFadeState
    let showsHeaders: Bool
    @ScrollEdgeHardEdge private var hardEdge

    private var fade: CGFloat { PinnedHeaderEdgeFade.height(hardEdge: hardEdge) }

    func body(content: Content) -> some View {
        content
            .modifier(PinnedHeaderScrollReader(state: state))
            .onChange(of: fade, initial: true) { _, fade in
                state.setFade(fade)
            }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: {
                state.setListTop($0)
            }
            .preference(key: ModalTopEdgeFadeRampKey.self, value: 0)
            .onChange(of: showsHeaders, initial: true) { _, shows in
                state.setShowsHeaders(shows)
            }
    }
}

/// Reads the pin line and scroll offset from the scroll geometry on iOS 18 / macOS 15
/// and later. Otherwise (``PinnedHeaderEdgeFadeState/legacyScrollTracking``) the rows'
/// locators hand the List's platform scroll view to the state, which follows it; until
/// then the top safe-area inset stands in for the pin line.
private struct PinnedHeaderScrollReader: ViewModifier {
    let state: PinnedHeaderEdgeFadeState

    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *), !state.legacyScrollTracking {
            content.onScrollGeometryChange(for: ScrollReading.self) { geometry in
                ScrollReading(
                    inset: geometry.contentInsets.top,
                    offset: geometry.contentOffset.y + geometry.contentInsets.top
                )
            } action: { _, reading in
                state.setScroll(inset: reading.inset, offset: reading.offset)
            }
        } else {
            content.background {
                Color.clear
                    .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: {
                        state.setFallbackPinLine($0)
                    }
                    .accessibilityHidden(true)
            }
        }
    }
}

/// One scroll-geometry sample.
private struct ScrollReading: Equatable {
    let inset: CGFloat
    let offset: CGFloat
}

/// One header measurement: its content's laid-out global top (first header only) and
/// height.
private struct HeaderReading: Equatable {
    let top: CGFloat?
    let height: CGFloat
}

/// Measures a header and, for the first one, draws it lifted over the gap above it.
///
/// The lift is a visual effect, so it moves neither the header's layout nor the
/// measurement taken outside it.
private struct PinnedSectionHeaderModifier: ViewModifier {
    let state: PinnedHeaderEdgeFadeState
    let first: Bool

    func body(content: Content) -> some View {
        let first = first
        let pinTop = state.listTop
        let layout = state.headerLayout
        content
            .visualEffect { effect, proxy in
                effect.offset(y: first ? -PinnedHeaderEdgeFade.lift(
                    contentTop: proxy.frame(in: .global).minY, pinLine: pinTop, layout: layout
                ) : 0)
            }
            .onGeometryChange(for: HeaderReading.self) { proxy in
                let frame = proxy.frame(in: .global)
                return HeaderReading(top: first ? frame.minY : nil, height: frame.height)
            } action: { reading in
                state.setHeaderHeight(reading.height)
                if let top = reading.top { state.setFirstHeaderTop(top) }
            }
            .modifier(MacHeaderSeparator())
    }
}

/// Keeps the full-width line an AppKit List draws under each section header (#322).
///
/// The table draws that line only while some row in it shows a separator; pinned-header
/// rows hide theirs (they draw their own inside the fade), so the header asks for it.
/// UIKit headers never draw one, so iOS and iPadOS are unchanged.
private struct MacHeaderSeparator: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content.listRowSeparator(.visible)
        #else
        content
        #endif
    }
}

/// Masks one row (its content, or its background with the row's separator) above the
/// pinned header's bottom edge, with the fade below it.
///
/// The row reports its global top only while it is near the edge
/// (``PinnedHeaderEdgeFadeState/rowLimit``, read from a lock box because SwiftUI may keep
/// an earlier geometry closure), and the cut is computed here from the observed edge and
/// depth. A row clear of the edge reads neither, so the scroll-driven depth re-renders
/// only the rows near the header (issue #553). The mask keeps the same structure in every
/// state (a gradient band under a shape that covers everything below it, or the whole
/// row when the row is clear of the edge), so a row crossing the edge never rebuilds.
private struct PinnedHeaderRowMask: ViewModifier {
    let state: PinnedHeaderEdgeFadeState
    /// Whether this view hands the List's platform scroll view to the state on the legacy
    /// path (the row content does; its background need not).
    var locatesScrollView = true
    @State private var rowTop: CGFloat?

    func body(content: Content) -> some View {
        let limit = state.rowLimit
        let mask = rowTop.map { top in
            let depth = state.depth
            return (cut: PinnedHeaderEdgeFade.cut(rowTop: top - state.origin, edge: state.edge, depth: depth), depth: depth)
        }
        let depth = mask?.depth ?? PinnedHeaderEdgeFade.height
        let cut = mask?.cut
        content
            .onGeometryChange(for: CGFloat?.self) { proxy in
                let top = proxy.frame(in: .global).minY
                return top < limit.value ? top : nil
            } action: { top in
                rowTop = top
            }
            .mask { PinnedHeaderFadeMask(cut: cut, depth: depth) }
            .background {
                if locatesScrollView && state.legacyScrollTracking {
                    ListScrollViewLocator { state.attachLegacyScrollView($0) }
                        .accessibilityHidden(true)
                }
            }
    }
}

// MARK: - Floating section bar (Songs)

extension View {
    /// Fade this `List` row out under a section title drawn over the List (Songs' floating
    /// section bar, iOS 26 and later; issues #10, #298), with the shared ramp. Apply it to
    /// every row's content, inside the row's `listRow…` traits.
    ///
    /// Each row masks itself, never the whole List: an alpha mask around a `List` makes
    /// SwiftUI drive the scroll view's insets from its own safe area, which lags UIKit's
    /// during the large-title and tab-bar transitions. Near the top the large title then
    /// snapped closed as the tab bar expanded, jumped back and forth under the finger and
    /// came to rest part-way (issue #383, iOS 26 and 27). A cell's own mask leaves the
    /// List's scroll view alone, like the Notifications rows
    /// (``pinnedHeaderEdgeFadeRow(_:first:background:)``).
    ///
    /// Inactive (at rest, or with no sections) nothing is masked, so the first rows stay
    /// fully drawn.
    ///
    /// - Parameters:
    ///   - edge: The title's bottom edge in global coordinates.
    ///   - active: Rows have scrolled under the title.
    ///   - depthLimit: Reads the deepest the fade may reach, so it never dims an incoming
    ///     title or a landed section's first row (R8); nil for the full ramp. Only rows
    ///     near the edge call it.
    ///   - rowLimit: Box shared by the List's rows: a row reports its global top only
    ///     above this line (``PinnedHeaderEdgeFade/rowLimit(edge:active:)``), read from a
    ///     lock box because SwiftUI may keep an earlier geometry closure.
    /// - Returns: The masked row.
    func pinnedHeaderEdgeFadeRowMask(
        edge: CGFloat, active: Bool, depthLimit: PinnedHeaderEdgeFade.RowMaskDepth, rowLimit: TopInset
    ) -> some View {
        modifier(PinnedTitleRowMask(edge: edge, active: active, depthLimit: depthLimit, rowLimit: rowLimit))
    }
}

extension PinnedHeaderEdgeFade {
    /// Reads a floating title's fade depth limit for one row mask
    /// (``SwiftUI/View/pinnedHeaderEdgeFadeRowMask(edge:active:depthLimit:rowLimit:)``).
    ///
    /// The mask calls it only while its row is near the title's edge, so only those rows
    /// observe a limit that moves every frame while a section title passes (issue #553).
    struct RowMaskDepth {
        /// The deepest the fade may reach, or nil for its full height.
        let read: () -> CGFloat?
    }

    /// The fade depth one row mask under a floating title draws.
    ///
    /// A row clear of the edge draws no cut, so its band depth changes nothing on screen;
    /// it stays at the full `fade` there and never reads the moving `limit`.
    ///
    /// - Parameters:
    ///   - near: The row reports a top near the title's edge.
    ///   - fade: The full fade height for the current settings.
    ///   - limit: Reads the depth limit (nil for the full fade); called only when `near`.
    /// - Returns: The depth in points.
    static func rowMaskDepth(near: Bool, fade: CGFloat, limit: () -> CGFloat?) -> CGFloat {
        guard near, let limit = limit() else { return fade }
        return depth(scrollOffset: limit, fade: fade)
    }
}

extension PinnedHeaderEdgeFade {
    /// The line above which a row under a floating title reports its global top: the
    /// title's bottom edge plus the full fade, or nowhere while rows have not scrolled
    /// under the title.
    ///
    /// - Parameters:
    ///   - edge: The title's bottom edge in global coordinates.
    ///   - active: Rows have scrolled under the title.
    /// - Returns: The line in global points; `-infinity` when inactive or not finite.
    static func rowLimit(edge: CGFloat, active: Bool) -> CGFloat {
        guard active, edge.isFinite else { return -.infinity }
        return edge + height
    }
}

/// Masks one List row above a floating title's bottom edge, with the fade below it.
///
/// The row reports its global top only while it is above the shared
/// ``PinnedHeaderEdgeFade/rowLimit(edge:active:)`` line, so rows clear of the title never
/// re-render while scrolling. Only such a row reads the fade's depth limit, which moves
/// every frame while a section title passes the bar: read by every row, it re-rendered
/// and redrew every visible row's mask each of those frames (issue #553). The mask keeps
/// the same structure in every state, so a row crossing the edge or a settings change
/// never rebuilds it.
private struct PinnedTitleRowMask: ViewModifier {
    let edge: CGFloat
    let active: Bool
    /// The depth limit (``PinnedHeaderEdgeFade/RowMaskDepth``), read only near the edge.
    let depthLimit: PinnedHeaderEdgeFade.RowMaskDepth
    let rowLimit: TopInset
    @State private var rowTop: CGFloat?
    @ScrollEdgeHardEdge private var hardEdge

    func body(content: Content) -> some View {
        let fade = PinnedHeaderEdgeFade.height(hardEdge: hardEdge)
        let near = active ? rowTop : nil
        let depth = PinnedHeaderEdgeFade.rowMaskDepth(near: near != nil, fade: fade, limit: depthLimit.read)
        let cut = near.flatMap {
            PinnedHeaderEdgeFade.cut(rowTop: $0, edge: edge, depth: depth)
        }
        let limit = rowLimit
        let _ = limit.value = PinnedHeaderEdgeFade.rowLimit(edge: edge, active: active)
        content
            .onGeometryChange(for: CGFloat?.self) { proxy in
                let top = proxy.frame(in: .global).minY
                return top < limit.value ? top : nil
            } action: { top in
                rowTop = top
            }
            .mask { PinnedHeaderFadeMask(cut: cut, depth: depth) }
    }
}

// MARK: - Mask

/// The one row mask under a pinned section title: clear above `cut`, a linear ramp
/// ``PinnedHeaderEdgeFade/gradientStops`` `depth` points deep below it, opaque after.
/// With no `cut` everything is drawn. The gradient band sits under the opaque shape when
/// inactive, so it changes nothing there.
///
/// The band is never laid out empty (``bandHeight(depth:)``): a band that collapsed to
/// 0 pt whenever the fade had no depth (at the top, or a title landed on the bar) and
/// grew back made SwiftUI rebuild the masked List's layer, and the List briefly counted
/// its top inset twice (issue #383: 170 → 344 pt on iOS 27). Near the top that collapsed
/// the expanding large title again, so the header jumped back and forth under the
/// finger.
struct PinnedHeaderFadeMask: View {
    /// Where the pinned title's bottom edge crosses this view, in local points; nil when
    /// no part of the view reaches it.
    let cut: CGFloat?
    /// Current depth of the ramp below the edge (0: a hard edge).
    let depth: CGFloat

    /// The thinnest the gradient band is laid out, in points.
    static let minimumBandHeight: CGFloat = 1

    /// The gradient band's laid-out height for a ramp `depth` points deep.
    ///
    /// At least ``minimumBandHeight``, so the band never leaves the render tree. Any part
    /// below `depth` lies under the opaque shape (which starts at `cut + depth`), so a
    /// 0 pt depth still draws a hard edge.
    ///
    /// - Parameter depth: The ramp's depth; negative or non-finite counts as 0.
    /// - Returns: The band height.
    static func bandHeight(depth: CGFloat) -> CGFloat {
        max(minimumBandHeight, depth.isFinite ? depth : 0)
    }

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(stops: PinnedHeaderEdgeFade.gradientStops, startPoint: .top, endPoint: .bottom)
                .frame(height: Self.bandHeight(depth: depth))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, -BelowCutShape.far)
                .offset(y: cut ?? 0)
            BelowCutShape(cut: cut.map { $0 + max(0, depth) })
        }
        .accessibilityHidden(true)
    }
}

/// Everything from `cut` (local points) down, or everything when `cut` is nil. The path
/// reaches past the frame's sides and bottom so content drawn outside its frame (a
/// pressed highlight, a marquee) is not clipped.
private struct BelowCutShape: Shape {
    static let far: CGFloat = 10_000

    let cut: CGFloat?

    func path(in rect: CGRect) -> Path {
        let far = Self.far
        let top = cut.map { rect.minY + $0 } ?? (rect.minY - far)
        return Path(CGRect(
            x: rect.minX - far, y: top, width: rect.width + 2 * far, height: max(0, rect.maxY + far - top)
        ))
    }
}

// MARK: - Modal ramp override

/// Lets a modal's content replace the modal's top-fade ramp height (issue #301): a List
/// whose rows fade under its own pinned headers asks for 0, a hard edge under the modal
/// header, so the ramp never dims those headers.
struct ModalTopEdgeFadeRampKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() { value = min(value ?? next, next) }
    }
}
