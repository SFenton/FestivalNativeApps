import SwiftUI

// MARK: - Pinned header geometry

/// Geometry that keeps a modal `List`'s pinned section headers still and legible
/// (issue #301).
///
/// A plain `List` pins each section header at the top of its scroll view, just below the
/// modal's own header. Two things went wrong there:
///
/// - iOS puts a gap (22 pt on iOS 26) above the first header, so that header rested
///   lower and slid up through the gap before pinning. ``lift(contentTop:pinLine:layout:)``
///   draws the first header at its pinned position from the start while the empty gap
///   scrolls away; the List's layout is unchanged.
/// - ``ModalTopEdgeFadeModifier`` fades content out under the modal header only, so a
///   pinned section header sat inside its 40 pt fade (dimmed) while rows scrolled on
///   underneath it, still half drawn. A single mask over the whole List cannot show the
///   header while hiding the rows behind it, so each row masks itself instead: it is fully
///   transparent above the pinned header's bottom edge and fades back in over
///   ``SectionBarEdgeFade/height`` below it, like the Songs section bar (issue #10). The
///   header itself is never masked.
///
/// At rest nothing is dimmed; the fade grows with the first points of scrolling (as the
/// modal's own fade and the system soft scroll-edge effect do), so the first row right
/// under the header is fully drawn until it starts to slide under it.
///
/// All positions are measured from the top of the List's scroll view, which reaches up
/// under the modal header by the pin line (its top content inset).
enum ModalPinnedHeaderFade {
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
    ///     (``SectionBarEdgeFade/height(reduceTransparency:increaseContrast:)``).
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
}

// MARK: - Shared state

/// Live readings shared by a List, its pinned headers and its rows (issue #301).
///
/// Rows and headers measure themselves in global coordinates and subtract ``origin``:
/// inside an iOS List's cells the `.scrollView` coordinate space does not reach the
/// List's scroll view. Only the row masks and the first header read it, so a scroll or a
/// measurement re-renders those small modifiers, never the rows themselves.
@MainActor @Observable
final class ModalPinnedHeaderFadeState {
    /// The scroll view's top content inset, where headers pin.
    fileprivate(set) var pinLine: CGFloat = 0
    /// The List's top edge in global coordinates. SwiftUI lays the List out inside the
    /// safe area, so this is where headers pin; its scroll view reaches up under the
    /// modal header by the top content inset.
    fileprivate(set) var listTop: CGFloat = 0
    /// Height of a header's content, or 0 while the List shows none.
    fileprivate(set) var headerHeight: CGFloat = 0
    /// The first header's layout, once read at rest.
    fileprivate(set) var headerLayout = ModalPinnedHeaderFade.HeaderLayout(inset: 0, gap: 0)
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
    /// Rows report their top only above this global line (the edge plus the full fade and
    /// some slack), so rows far below the header never update while scrolling.
    let rowLimit = TopInset()

    /// The scroll view's top edge in global coordinates: positions in
    /// ``ModalPinnedHeaderFade`` are measured from here.
    var origin: CGFloat { listTop - pinLine }

    /// The pinned header band's bottom edge, below ``origin``.
    var edge: CGFloat {
        ModalPinnedHeaderFade.edge(pinLine: pinLine, headerHeight: headerHeight, headerInset: headerLayout.inset)
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
    }

    fileprivate func setDepth(_ value: CGFloat) {
        if value != depth { depth = value }
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
    func modalPinnedHeaderTestSet(
        pinLine: CGFloat, headerHeight: CGFloat?, showsHeaders: Bool, listTop: CGFloat? = nil,
        scrollOffset: CGFloat? = nil, firstHeaderTop: CGFloat? = nil, firstRowTop: CGFloat? = nil
    ) {
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
        guard let layout = ModalPinnedHeaderFade.headerLayout(
            headerTop: firstHeaderTop - origin, headerHeight: measuredHeaderHeight,
            firstRowTop: firstRowTop.map { $0 - origin }, pinLine: pinLine
        ) else { return }
        layoutMeasured = true
        if firstRowTop != nil { layoutMeasuredWithRow = true }
        if layout != headerLayout { headerLayout = layout }
    }

    private func updateRowLimit() {
        rowLimit.value = origin + ModalPinnedHeaderFade.edge(
            pinLine: pinLine, headerHeight: max(headerHeight, measuredHeaderHeight),
            headerInset: headerLayout.inset
        ) + SectionBarEdgeFade.height + 24
    }
}

// MARK: - Modifiers

extension View {
    /// Keep this `List`'s pinned section headers still and fade its rows out before they
    /// reach them, inside a ``FestivalModal`` (issue #301). Pair it with
    /// ``modalPinnedSectionHeader(_:first:)`` on each header and
    /// ``modalPinnedHeaderRow(_:first:background:)`` on each row.
    ///
    /// Turns the modal's own top fade into a hard edge (the rows fade themselves, and the
    /// modal's ramp would otherwise dim the pinned header).
    ///
    /// - Parameters:
    ///   - state: Readings shared with the headers and rows.
    ///   - showsHeaders: Whether any section header is visible.
    /// - Returns: The List with its pin line and scroll depth tracked.
    func modalPinnedHeaderList(_ state: ModalPinnedHeaderFadeState, showsHeaders: Bool) -> some View {
        modifier(ModalPinnedHeaderListModifier(state: state, showsHeaders: showsHeaders))
    }

    /// Measure this pinned section header for ``modalPinnedHeaderList(_:showsHeaders:)``;
    /// the first header is also drawn at its pinned position from the start.
    ///
    /// - Parameters:
    ///   - state: Readings shared with the List and its rows.
    ///   - first: Whether this is the List's first header.
    /// - Returns: The header, reporting its content's height (and, when first, its top).
    func modalPinnedSectionHeader(_ state: ModalPinnedHeaderFadeState, first: Bool) -> some View {
        modifier(ModalPinnedSectionHeaderModifier(state: state, first: first))
    }

    /// Fade this row out before it reaches the List's pinned section header, and set its
    /// row background.
    ///
    /// - Parameters:
    ///   - state: Readings shared with the List and its headers.
    ///   - first: Whether this is the first row of the List's first section. Its row
    ///     background, which fills the row's whole cell, measures where the cell starts:
    ///     right under the first header's band.
    ///   - background: The row background (`listRowBackground`).
    /// - Returns: The row, masked near the header.
    func modalPinnedHeaderRow(
        _ state: ModalPinnedHeaderFadeState, first: Bool = false, background: some View = Color.clear
    ) -> some View {
        modifier(ModalPinnedHeaderRowMask(state: state))
            .listRowBackground(
                background.background {
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

/// Tracks the List's position, pin line and fade depth, and hands the modal a hard top
/// edge.
private struct ModalPinnedHeaderListModifier: ViewModifier {
    let state: ModalPinnedHeaderFadeState
    let showsHeaders: Bool
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.colorSchemeContrast) private var systemContrast
    @AppStorage("fst.accessibility.lessTransparency") private var lessTransparency = false
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false

    private var fade: CGFloat {
        SectionBarEdgeFade.height(
            reduceTransparency: systemReduceTransparency || lessTransparency,
            increaseContrast: moreContrast || systemContrast == .increased
        )
    }

    func body(content: Content) -> some View {
        content
            .modifier(PinnedHeaderScrollReader(state: state, fade: fade))
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: {
                state.setListTop($0)
            }
            .preference(key: ModalTopEdgeFadeRampKey.self, value: 0)
            .onChange(of: showsHeaders, initial: true) { _, shows in
                state.setShowsHeaders(shows)
            }
    }
}

/// Reads the pin line and scroll offset: from the scroll geometry on iOS 18 / macOS 15
/// and later, else the top safe-area inset with no fade (a hard edge, like the modal's
/// own fallback).
private struct PinnedHeaderScrollReader: ViewModifier {
    let state: ModalPinnedHeaderFadeState
    let fade: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.onScrollGeometryChange(for: ScrollReading.self) { geometry in
                ScrollReading(
                    inset: geometry.contentInsets.top,
                    offset: geometry.contentOffset.y + geometry.contentInsets.top
                )
            } action: { _, reading in
                state.setPinLine(reading.inset)
                state.setScrollOffset(reading.offset)
                state.setDepth(ModalPinnedHeaderFade.depth(scrollOffset: reading.offset, fade: fade))
            }
            .onChange(of: fade) { _, fade in
                state.setDepth(min(state.depth, fade))
            }
        } else {
            content.background {
                Color.clear
                    .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: {
                        state.setPinLine($0)
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
private struct ModalPinnedSectionHeaderModifier: ViewModifier {
    let state: ModalPinnedHeaderFadeState
    let first: Bool

    func body(content: Content) -> some View {
        let first = first
        let pinTop = state.listTop
        let layout = state.headerLayout
        content
            .visualEffect { effect, proxy in
                effect.offset(y: first ? -ModalPinnedHeaderFade.lift(
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
    }
}

/// Masks one row above the pinned header's bottom edge, with the fade below it.
///
/// The row reports its global top only while it is near the edge
/// (``ModalPinnedHeaderFadeState/rowLimit``, read from a lock box because SwiftUI may keep
/// an earlier geometry closure), and the cut is computed here from the observed edge and
/// depth. The mask keeps the same structure in every state (a gradient band under a shape
/// that covers everything below it, or the whole row when the row is clear of the edge),
/// so a row crossing the edge never rebuilds.
private struct ModalPinnedHeaderRowMask: ViewModifier {
    let state: ModalPinnedHeaderFadeState
    @State private var rowTop: CGFloat?

    func body(content: Content) -> some View {
        let limit = state.rowLimit
        let depth = state.depth
        let cut = rowTop.flatMap {
            ModalPinnedHeaderFade.cut(rowTop: $0 - state.origin, edge: state.edge, depth: depth)
        }
        content
            .onGeometryChange(for: CGFloat?.self) { proxy in
                let top = proxy.frame(in: .global).minY
                return top < limit.value ? top : nil
            } action: { top in
                rowTop = top
            }
            .mask {
                ZStack(alignment: .top) {
                    LinearGradient(
                        stops: SectionBarEdgeFade.gradientStops, startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: depth)
                    .frame(maxWidth: .infinity)
                    .offset(y: cut ?? 0)
                    BelowCutShape(cut: cut.map { $0 + depth })
                }
            }
    }
}

/// Everything from `cut` (local points) down, or everything when `cut` is nil. The path
/// reaches past the frame's sides and bottom so row content drawn outside its frame (a
/// pressed highlight, a marquee) is not clipped.
private struct BelowCutShape: Shape {
    private static let far: CGFloat = 10_000

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
