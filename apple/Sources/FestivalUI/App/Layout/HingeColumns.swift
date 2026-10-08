import CoreGraphics
import SwiftUI

// MARK: - Geometry (pure)

/// A container's horizontal extent in window coordinates (leading-edge x, like
/// ``DeviceLayout/splitHinge``). Measured instead of the whole frame so vertical
/// scrolling never reports a change.
struct HorizontalSpan: Sendable, Equatable {
    /// Leading edge in window coordinates.
    var minX: CGFloat
    /// Trailing edge in window coordinates.
    var maxX: CGFloat

    /// The span's width.
    var width: CGFloat { maxX - minX }

    /// Create a span.
    ///
    /// - Parameters:
    ///   - minX: Leading edge in window coordinates.
    ///   - maxX: Trailing edge in window coordinates.
    init(minX: CGFloat, maxX: CGFloat) {
        self.minX = minX
        self.maxX = maxX
    }

    /// The horizontal extent of a frame.
    ///
    /// - Parameter frame: A frame in window coordinates.
    init(_ frame: CGRect) {
        self.init(minX: frame.minX, maxX: frame.maxX)
    }
}

/// Where a vertical fold divides a container, in the container's own coordinates:
/// the leading side, the clearance over the fold, and the trailing side.
struct HingeBand: Sendable, Equatable {
    /// Container leading edge to the start of the fold clearance.
    let leadingWidth: CGFloat
    /// The fold clearance: the fold's own width, at least the container's gutter.
    let gap: CGFloat
    /// End of the fold clearance to the container trailing edge.
    let trailingWidth: CGFloat

    /// The whole container width.
    var width: CGFloat { leadingWidth + gap + trailingWidth }
}

/// Column widths for a grid whose centre gutter sits on a fold.
struct HingeColumnSpec: Sendable, Equatable {
    /// Columns on the leading side of the fold.
    let leadingCount: Int
    /// Width of each leading column.
    let leadingColumnWidth: CGFloat
    /// Columns on the trailing side of the fold (always ``leadingCount``: even totals).
    let trailingCount: Int
    /// Width of each trailing column.
    let trailingColumnWidth: CGFloat
    /// Gap between columns on the same side.
    let spacing: CGFloat
    /// Gap over the fold, between the last leading and first trailing column.
    let gap: CGFloat

    /// Every column's width, leading to trailing.
    var widths: [CGFloat] {
        Array(repeating: leadingColumnWidth, count: leadingCount)
            + Array(repeating: trailingColumnWidth, count: trailingCount)
    }

    /// Total number of columns.
    var count: Int { leadingCount + trailingCount }

    /// The space after each column (the last is 0).
    var gaps: [CGFloat] {
        (0..<count).map { index in
            if index == count - 1 { return 0 }
            return index == leadingCount - 1 ? gap : spacing
        }
    }

    /// Each column's leading x, relative to the container's leading edge.
    var offsets: [CGFloat] {
        var x: CGFloat = 0
        return zip(widths, gaps).map { width, gap in
            defer { x += width + gap }
            return x
        }
    }

    /// The whole width the columns fill.
    var width: CGFloat { widths.reduce(0, +) + gaps.reduce(0, +) }
}

/// Hinge-aligned columns (pattern `hinge-columns`, issue #343): while an iPhone Duo
/// is partially folded with a vertical fold (book pose), two-column layouts put their
/// centre gutter on the fold (``DeviceLayout/splitHinge``: the reported fold, else the
/// inner display's middle) instead of at half their own width, and full-width titles
/// stay on the side they start on. Fully open, folded and every other device keep the
/// flat layout; the same views reflow, nothing reloads.
///
/// Mirrors Android `core/rivals/HingeColumns.kt` and `core/shop/ShopColumns.kt`: the
/// clearance is the fold's width but at least the layout's own gutter, centred on the
/// fold, and the leading side ends where it starts (so the iPhone Duo vertical bar stays
/// inside the trailing side, like ``OnDemandSplitPolicy``). Apple keeps the same column
/// count on both sides (HIG Designing for iPhone Duo: "Prefer … even grid column counts").
enum HingeColumns {
    /// Narrowest side worth splitting a fixed-count grid for; a fold nearer a container
    /// edge leaves the flat layout alone (HIG: "move only what's necessary").
    static let minimumSide: CGFloat = 120
    /// Narrowest leading side a title is limited to; nearer the fold, it keeps its width.
    static let minimumTitleSide: CGFloat = 160
    /// Clearance a title keeps from the fold's centre line when the fold is narrower.
    static let titleClearance: CGFloat = 16

    /// How many columns a grid places on each side of the fold.
    enum PerSide: Sendable, Equatable {
        /// A fixed number per side (a two-column grid has one).
        case columns(Int)
        /// As many as fit the narrower side at this minimum width (an adaptive grid).
        case fit(minimum: CGFloat)
    }

    /// The vertical fold crossing a container, if any.
    ///
    /// - Parameters:
    ///   - span: The container's horizontal extent in window coordinates; nil before it is measured.
    ///   - fold: The book-pose hinge (``DeviceLayout/splitHinge``) in window coordinates, or nil.
    ///   - gutter: The container's normal gap between columns (the narrowest clearance).
    ///   - minimumSide: Narrowest side the split is worth making.
    /// - Returns: The band, or nil without a vertical fold through the container's interior
    ///   or when either side would be narrower than `minimumSide`.
    static func band(span: HorizontalSpan?, fold: CGRect?, gutter: CGFloat, minimumSide: CGFloat) -> HingeBand? {
        guard let span, let fold, span.width > 0, fold.height > fold.width,
              fold.midX > span.minX, fold.midX < span.maxX else { return nil }
        let gap = max(fold.width, gutter)
        let leading = fold.midX - gap / 2 - span.minX
        let trailing = span.width - leading - gap
        guard leading >= minimumSide, trailing >= minimumSide else { return nil }
        return HingeBand(leadingWidth: leading, gap: gap, trailingWidth: trailing)
    }

    /// The vertical fold crossing an adaptive grid, if the grid splits there.
    ///
    /// An adaptive grid that already shows two or more flat columns always splits at the
    /// fold (one column a side at least, even a little under `minimum`): otherwise its
    /// flat gutter sits beside the fold and a card straddles it. A grid that is one flat
    /// column stays one column (R4).
    ///
    /// - Parameters:
    ///   - span: The grid's horizontal extent in window coordinates; nil before it is measured.
    ///   - fold: The active fold in window coordinates, or nil.
    ///   - gutter: Gap between columns (the narrowest clearance).
    ///   - minimum: The adaptive grid's narrowest column.
    /// - Returns: The band, or nil when the grid keeps its flat layout.
    static func adaptiveBand(span: HorizontalSpan?, fold: CGRect?, gutter: CGFloat, minimum: CGFloat) -> HingeBand? {
        guard let span, fitCount(width: span.width, minimum: minimum, spacing: gutter) >= 2 else { return nil }
        return band(span: span, fold: fold, gutter: gutter, minimumSide: minimumSide)
    }

    /// Columns that meet at the fold, the same count on each side.
    ///
    /// - Parameters:
    ///   - band: Where the fold divides the container.
    ///   - spacing: Gap between columns on one side.
    ///   - perSide: Columns per side.
    /// - Returns: The column widths.
    static func spec(band: HingeBand, spacing: CGFloat, perSide: PerSide) -> HingeColumnSpec {
        let count: Int
        switch perSide {
        case let .columns(fixed):
            count = max(1, fixed)
        case let .fit(minimum):
            count = min(
                fitCount(width: band.leadingWidth, minimum: minimum, spacing: spacing),
                fitCount(width: band.trailingWidth, minimum: minimum, spacing: spacing)
            )
        }
        func columnWidth(_ side: CGFloat) -> CGFloat {
            max(0, (side - spacing * CGFloat(count - 1)) / CGFloat(count))
        }
        return HingeColumnSpec(
            leadingCount: count, leadingColumnWidth: columnWidth(band.leadingWidth),
            trailingCount: count, trailingColumnWidth: columnWidth(band.trailingWidth),
            spacing: spacing, gap: band.gap
        )
    }

    /// How many columns of at least `minimum` fit a width.
    ///
    /// - Parameters:
    ///   - width: Available width.
    ///   - minimum: Narrowest column.
    ///   - spacing: Gap between columns.
    /// - Returns: At least 1.
    static func fitCount(width: CGFloat, minimum: CGFloat, spacing: CGFloat) -> Int {
        guard minimum > 0, width > 0 else { return 1 }
        return max(1, Int(((width + spacing) / (minimum + spacing)).rounded(.down)))
    }

    /// Lazy-grid columns whose centre gutter sits on the fold: fixed leading columns,
    /// flexible trailing ones (they absorb a one-frame width change instead of overflowing).
    ///
    /// - Parameters:
    ///   - spec: Hinge-aligned widths.
    ///   - alignment: Each item's alignment within its cell, as in the flat columns.
    /// - Returns: `GridItem`s, leading to trailing.
    static func gridItems(_ spec: HingeColumnSpec, alignment: Alignment?) -> [GridItem] {
        let gaps = spec.gaps
        return (0..<spec.count).map { index in
            let size: GridItem.Size = index < spec.leadingCount
                ? .fixed(spec.leadingColumnWidth)
                : .flexible(minimum: 1)
            return GridItem(size, spacing: gaps[index], alignment: alignment)
        }
    }

    /// The widest a full-width title may be so it stays on the fold side it starts on.
    ///
    /// - Parameters:
    ///   - span: The title's horizontal extent in window coordinates, or nil.
    ///   - fold: The active fold in window coordinates, or nil.
    /// - Returns: The leading side's width, or nil (no limit) without a vertical fold
    ///   through the title, or when the title starts too close to the fold.
    static func titleWidth(span: HorizontalSpan?, fold: CGRect?) -> CGFloat? {
        band(span: span, fold: fold, gutter: titleClearance * 2, minimumSide: 0)
            .flatMap { $0.leadingWidth >= minimumTitleSide ? $0.leadingWidth : nil }
    }

    /// Columns per side implied by a flat grid's columns: the adaptive minimum, else half
    /// the fixed count (one for a two-column grid).
    ///
    /// - Parameter columns: The grid's flat columns.
    /// - Returns: Columns per side.
    static func perSide(for columns: [GridItem]) -> PerSide {
        if columns.count == 1, case let .adaptive(minimum, _) = columns[0].size {
            return .fit(minimum: minimum)
        }
        return .columns(max(1, columns.count / 2))
    }

    /// Columns whose cells start at the top of their row (R8): a column without an
    /// explicit alignment gets `.top` instead of `GridItem`'s default `.center`, which
    /// would push a shorter cell down to the middle of its taller neighbour's row (#365).
    ///
    /// - Parameter columns: The grid's columns.
    /// - Returns: The same columns, top-aligned where they named no alignment.
    static func topAligned(_ columns: [GridItem]) -> [GridItem] {
        columns.map { column in
            guard column.alignment == nil else { return column }
            var aligned = column
            aligned.alignment = .top
            return aligned
        }
    }
}

// MARK: - Measuring

extension View {
    /// Report this view's horizontal extent in window coordinates (only when it changes,
    /// so vertical scrolling costs nothing).
    ///
    /// - Parameter span: Receives the extent.
    /// - Returns: The view, measured.
    func measuresHorizontalSpan(_ span: Binding<HorizontalSpan?>) -> some View {
        onGeometryChange(for: HorizontalSpan.self, of: { HorizontalSpan($0.frame(in: .global)) }) { value in
            if span.wrappedValue != value { span.wrappedValue = value }
        }
    }

    /// Keep a full-width title on the side of an iPhone Duo fold it starts on, wrapping
    /// before the fold (section-headers R10, hinge-columns R3). No effect without an
    /// active vertical fold through it.
    ///
    /// - Returns: The view, filling the proposed width with its content limited to one side.
    func staysOnHingeSide() -> some View {
        modifier(HingeSideTitle())
    }
}

/// Limits a leading-aligned title to the leading side of a fold that crosses it.
private struct HingeSideTitle: ViewModifier {
    @Environment(\.deviceLayout) private var layout
    @State private var span: HorizontalSpan?

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: HingeColumns.titleWidth(span: span, fold: layout.splitHinge) ?? .infinity, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .measuresHorizontalSpan($span)
    }
}

// MARK: - Lazy grid

/// A `LazyVGrid` whose centre gutter sits on an iPhone Duo fold (book pose) and that is
/// otherwise exactly the grid its flat `columns` describe. The canonical hinge-aware
/// grid (pattern `hinge-columns`): pages pass their flat columns and never measure the
/// fold themselves. Cells start at the top of their row, like ``HingeEagerGrid`` and
/// ``HingeRow``, unless a column names another alignment (R8, #365).
struct HingeGrid<Content: View>: View {
    private let columns: [GridItem]
    private let alignment: HorizontalAlignment
    private let spacing: CGFloat?
    private let perSide: HingeColumns.PerSide
    private let content: Content
    @Environment(\.deviceLayout) private var layout
    @State private var span: HorizontalSpan?

    /// Create a hinge-aware grid.
    ///
    /// - Parameters:
    ///   - columns: The flat layout's columns (two flexible, or one adaptive).
    ///   - alignment: Horizontal alignment of the grid.
    ///   - spacing: Row spacing.
    ///   - perSide: Columns per side of the fold; derived from `columns` when nil.
    ///   - content: The cells.
    init(
        columns: [GridItem], alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
        perSide: HingeColumns.PerSide? = nil, @ViewBuilder content: () -> Content
    ) {
        self.columns = HingeColumns.topAligned(columns)
        self.alignment = alignment
        self.spacing = spacing
        self.perSide = perSide ?? HingeColumns.perSide(for: columns)
        self.content = content()
    }

    /// The gap between flat columns (also the narrowest clearance over the fold).
    private var gutter: CGFloat { columns.first?.spacing ?? 8 }

    private var band: HingeBand? {
        if case let .fit(minimum) = perSide {
            return HingeColumns.adaptiveBand(span: span, fold: layout.splitHinge, gutter: gutter, minimum: minimum)
        }
        return HingeColumns.band(
            span: span, fold: layout.splitHinge, gutter: gutter, minimumSide: HingeColumns.minimumSide
        )
    }

    private var resolvedColumns: [GridItem] {
        guard let band else { return columns }
        let spec = HingeColumns.spec(band: band, spacing: gutter, perSide: perSide)
        return HingeColumns.gridItems(spec, alignment: columns.first?.alignment)
    }

    var body: some View {
        LazyVGrid(columns: resolvedColumns, alignment: alignment, spacing: spacing) {
            content
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        .measuresHorizontalSpan($span)
    }
}

// MARK: - Eager grid

/// The eager counterpart of an adaptive ``HingeGrid``: every cell is built at once, in
/// rows as tall as their tallest cell, for content a lazy grid cannot lay out (Song
/// Detail's tall, unequal instrument cards at accessibility sizes hung `LazyVGrid` in a
/// lazy-layout loop). Flat, as many equal columns of at least `minimum` as fit; in an
/// iPhone Duo book pose, the same count on each side with the gutter on the fold.
struct HingeEagerGrid<Content: View>: View {
    private let minimum: CGFloat
    private let spacing: CGFloat
    private let rowSpacing: CGFloat
    private let content: Content
    @Environment(\.deviceLayout) private var layout
    @State private var span: HorizontalSpan?

    /// Create an eager hinge-aware grid.
    ///
    /// - Parameters:
    ///   - minimum: Narrowest column (the adaptive minimum).
    ///   - spacing: Gap between columns (and the narrowest clearance over the fold).
    ///   - rowSpacing: Gap between rows.
    ///   - content: The cells, in reading order.
    init(minimum: CGFloat, spacing: CGFloat, rowSpacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.minimum = minimum
        self.spacing = spacing
        self.rowSpacing = rowSpacing
        self.content = content()
    }

    var body: some View {
        HingeEagerGridLayout(
            minimum: minimum, spacing: spacing, rowSpacing: rowSpacing,
            band: HingeColumns.adaptiveBand(span: span, fold: layout.splitHinge, gutter: spacing, minimum: minimum)
        ) { content }
            .measuresHorizontalSpan($span)
    }
}

/// Places cells row by row in adaptive columns, or per side of a ``HingeBand`` when the
/// band matches the proposed width; each cell keeps its own height, top-aligned.
struct HingeEagerGridLayout: Layout {
    /// Narrowest column.
    var minimum: CGFloat
    /// Gap between columns.
    var spacing: CGFloat
    /// Gap between rows.
    var rowSpacing: CGFloat
    /// The fold's band across the grid, or nil.
    var band: HingeBand?

    /// Every column's leading x and width for a width.
    ///
    /// - Parameter width: The grid's width.
    /// - Returns: One (x, width) per column: hinge-aligned when ``band`` matches the
    ///   width, otherwise equal columns of at least ``minimum``.
    func columns(width: CGFloat) -> [(x: CGFloat, width: CGFloat)] {
        if let band, abs(band.width - width) < 0.5 {
            let spec = HingeColumns.spec(band: band, spacing: spacing, perSide: .fit(minimum: minimum))
            return Array(zip(spec.offsets, spec.widths)).map { (x: $0.0, width: $0.1) }
        }
        let count = HingeColumns.fitCount(width: width, minimum: minimum, spacing: spacing)
        let cell = max(0, (width - spacing * CGFloat(count - 1)) / CGFloat(count))
        return (0..<count).map { (x: CGFloat($0) * (cell + spacing), width: cell) }
    }

    private func rowHeights(_ subviews: Subviews, columns: [(x: CGFloat, width: CGFloat)]) -> [CGFloat] {
        stride(from: 0, to: subviews.count, by: columns.count).map { start in
            zip(subviews[start ..< min(start + columns.count, subviews.count)], columns)
                .map { $0.sizeThatFits(ProposedViewSize(width: $1.width, height: nil)).height }
                .max() ?? 0
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? minimum
        let heights = rowHeights(subviews, columns: columns(width: width))
        return CGSize(width: width, height: heights.reduce(0, +) + rowSpacing * CGFloat(max(0, heights.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columns = columns(width: bounds.width)
        var y = bounds.minY
        for (row, height) in rowHeights(subviews, columns: columns).enumerated() {
            for (column, frame) in columns.enumerated() {
                let index = row * columns.count + column
                guard index < subviews.count else { break }
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + frame.x, y: y), anchor: .topLeading,
                    proposal: ProposedViewSize(width: frame.width, height: nil)
                )
            }
            y += height + rowSpacing
        }
    }
}

// MARK: - One row

/// One row of equal cells whose gutter sits on an iPhone Duo hinge in book pose
/// (``DeviceLayout/splitHinge``: the fold, else the inner display's middle); equal
/// widths otherwise, like an `HStack` of `.frame(maxWidth: .infinity)` cells. Flat, the
/// cells are equal, so a full-width row's gutter sits at the midpoint of its free space
/// (pattern `hinge-columns` R7, owner #361). Page columns in wide landscape (Songs' and
/// Search's two-card rows, pattern `wide-columns` R3) and halves inside a page use it alike.
/// Side-by-side panes (the feedback form and its photo library, #373) pass `fillsHeight`
/// so each pane takes the row's whole height.
struct HingeRow<Content: View>: View {
    private let spacing: CGFloat
    private let fillsHeight: Bool
    private let content: Content
    @Environment(\.deviceLayout) private var layout
    @State private var span: HorizontalSpan?

    /// Create a row.
    ///
    /// - Parameters:
    ///   - spacing: Gap between cells (and the narrowest clearance over the hinge).
    ///   - fillsHeight: Give every cell the row's proposed height (side-by-side panes)
    ///     instead of its own (default false: cards, top-aligned).
    ///   - content: The cells, an even count (pad a short row with clear cells); one cell
    ///     alone fills the row.
    init(spacing: CGFloat, fillsHeight: Bool = false, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.fillsHeight = fillsHeight
        self.content = content()
    }

    var body: some View {
        let band = HingeColumns.band(
            span: span, fold: layout.splitHinge, gutter: spacing, minimumSide: HingeColumns.minimumSide
        )
        HingeRowLayout(spacing: spacing, band: band, fillsHeight: fillsHeight) { content }
            .measuresHorizontalSpan($span)
    }
}

/// Places its subviews in one top-aligned row: equal widths, or per side of a
/// ``HingeBand`` (half the cells each side) when the band matches the proposed width.
struct HingeRowLayout: Layout {
    /// Gap between cells.
    var spacing: CGFloat
    /// The fold's band across the row, or nil.
    var band: HingeBand?
    /// Every cell takes the row's proposed height (side-by-side panes).
    var fillsHeight = false

    /// What a cell is offered.
    ///
    /// - Parameters:
    ///   - width: The cell's width.
    ///   - rowHeight: The row's proposed height, if any.
    /// - Returns: The width, and the row's height when ``fillsHeight`` (otherwise the
    ///   cell's own height).
    func cellProposal(width: CGFloat, rowHeight: CGFloat?) -> ProposedViewSize {
        ProposedViewSize(width: width, height: fillsHeight ? rowHeight : nil)
    }

    /// Cell widths and leading offsets for a width.
    ///
    /// - Parameters:
    ///   - width: The row's width.
    ///   - count: Number of cells.
    /// - Returns: One (x, width) per cell.
    func cells(width: CGFloat, count: Int) -> [(x: CGFloat, width: CGFloat)] {
        guard count > 0 else { return [] }
        if let band, count.isMultiple(of: 2), abs(band.width - width) < 0.5 {
            let spec = HingeColumns.spec(band: band, spacing: spacing, perSide: .columns(count / 2))
            return Array(zip(spec.offsets, spec.widths)).map { (x: $0.0, width: $0.1) }
        }
        let cell = max(0, (width - spacing * CGFloat(count - 1)) / CGFloat(count))
        return (0..<count).map { (x: CGFloat($0) * (cell + spacing), width: cell) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.reduce(0, +)
            + spacing * CGFloat(max(0, subviews.count - 1))
        if fillsHeight, let height = proposal.height { return CGSize(width: width, height: height) }
        let height = zip(subviews, cells(width: width, count: subviews.count))
            .map { $0.sizeThatFits(cellProposal(width: $1.width, rowHeight: proposal.height)).height }
            .max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, cell) in zip(subviews, cells(width: bounds.width, count: subviews.count)) {
            subview.place(
                at: CGPoint(x: bounds.minX + cell.x, y: bounds.minY), anchor: .topLeading,
                proposal: cellProposal(width: cell.width, rowHeight: bounds.height)
            )
        }
    }
}
