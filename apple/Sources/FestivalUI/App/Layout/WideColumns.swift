import SwiftUI

// MARK: - WideColumns

/// The app-wide rule for page content in wide landscape (pattern `wide-columns`,
/// issue #350): two columns of rows when the window is landscape and regular in both
/// dimensions (iPad landscape, iPhone Duo inner display in landscape, a wide Mac sheet
/// or window), one column otherwise (iPhone, any portrait window, folded Duo, compact
/// Split View or Stage Manager windows).
///
/// Rows flow row-major (left then right, then down) under full-width section headers;
/// a short last row keeps its card at column width. Rows draw through ``HingeRow``,
/// so on iPhone Duo the gutter sits on the hinge in book pose
/// and at the midpoint of the free space when flat (owner #361,
/// `.agents/patterns/wide-columns.md`).
///
/// HIG Layout: "Choose layout from size classes, not device type/idiom or orientation"
/// (the size classes and measured width gate it; landscape-only is the owner's explicit
/// choice, #350). HIG Designing for iPhone Duo: "Expand the existing layout with space".
enum WideColumns {
    /// Gap between the two cards of a row (the Songs grid's gutter).
    static let spacing: CGFloat = 12

    /// Narrowest column worth splitting into: a result or song card keeps its title,
    /// subtitle and trailing chips at this width.
    static let minimumColumnWidth: CGFloat = 320

    /// Leading plus trailing row margin (the 16 pt list-row insets).
    static let rowMargins: CGFloat = 32

    /// Narrowest content width (inside the row margins) that holds two columns.
    static var minimumTwoColumnWidth: CGFloat { minimumColumnWidth * 2 + spacing }

    /// Columns for a page in a device window (iOS, iPadOS, iPhone Duo).
    ///
    /// Landscape comes from the window (``DeviceLayout/orientation``), never from the
    /// page's own frame: the iPad keyboard shortens a portrait page into a wide box, and
    /// that must not flip it to two columns.
    ///
    /// - Parameters:
    ///   - layout: The page's device layout.
    ///   - width: The page's measured width in points (row margins included), or nil to
    ///     use the window's width inside its safe area.
    /// - Returns: 1 or 2.
    static func count(layout: DeviceLayout, width: CGFloat? = nil) -> Int {
        guard layout.orientation == .landscape, layout.windowWidthClass == .regular,
              layout.heightClass == .regular else { return 1 }
        let available = width ?? (layout.size.width - layout.safeAreaInsets.leading - layout.safeAreaInsets.trailing)
        return fits(width: available) ? 2 : 1
    }

    /// Columns for a resizable Mac surface (the Search sheet or a window), from its own
    /// measured size: two when it is wider than tall and wide enough.
    ///
    /// - Parameter size: The surface's size in points (zero before measurement).
    /// - Returns: 1 or 2.
    static func count(size: CGSize) -> Int {
        size.width > size.height && fits(width: size.width) ? 2 : 1
    }

    /// Whether a page width (row margins included) holds two columns.
    ///
    /// - Parameter width: The page's width in points.
    /// - Returns: True at or above ``minimumTwoColumnWidth`` plus ``rowMargins``.
    static func fits(width: CGFloat) -> Bool {
        width - rowMargins >= minimumTwoColumnWidth
    }

    /// Columns for a page from its own measured size, on either platform: the device
    /// window rule (``count(layout:width:)``) on iOS, iPadOS and iPhone Duo, the surface
    /// rule (``count(size:)``) on the Mac, and always one on a split's sub-page (R1;
    /// issue #353: a page in a split's trailing pane is never two columns, however wide).
    ///
    /// - Parameters:
    ///   - layout: The page's device layout.
    ///   - size: The page's measured size (zero before measurement).
    ///   - subPage: Whether the page is a split's sub-page
    ///     (``SwiftUI/EnvironmentValues/splitPaneSubPage``).
    /// - Returns: 1 or 2.
    static func count(layout: DeviceLayout, size: CGSize, subPage: Bool) -> Int {
        guard !subPage else { return 1 }
        #if os(macOS)
        return count(size: size)
        #else
        return count(layout: layout, width: size.width > 0 ? size.width : nil)
        #endif
    }

    /// The page width one of `columns` columns lays out like: what remains of `width`
    /// after the row margins and gutters, split evenly, with one column's margins back.
    /// Width-driven row plans (a leaderboard's season and stars columns, its songs fit)
    /// read this, so a column fits its rows exactly as a page of that width would.
    ///
    /// - Parameters:
    ///   - width: The page's width in points (row margins included).
    ///   - columns: Columns across the page (at least 1).
    /// - Returns: `width` for one column, else one column's page-equivalent width.
    static func columnPageWidth(_ width: CGFloat, columns: Int) -> CGFloat {
        guard columns > 1, width > 0 else { return width }
        let count = CGFloat(columns)
        return (width - rowMargins - spacing * (count - 1)) / count + rowMargins
    }

    /// Columns for a page of readable text sections (Settings, R7): accessibility text
    /// sizes stack into one column whatever the width, so rows, toggles and long
    /// descriptions keep a full readable line (HIG Layout: "horizontal views may stack").
    ///
    /// - Parameters:
    ///   - columns: The width-based count from ``count(layout:width:)`` or
    ///     ``count(size:)``.
    ///   - typeSize: The page's Dynamic Type size.
    /// - Returns: 1 at an accessibility size, otherwise `columns`.
    static func readable(_ columns: Int, typeSize: DynamicTypeSize) -> Int {
        typeSize.isAccessibilitySize ? 1 : columns
    }

    /// Chunk items into rows of `columns`, keeping order (row-major).
    ///
    /// - Parameters:
    ///   - items: The section's items, in order.
    ///   - columns: Cards per row (at least 1).
    /// - Returns: The rows; only the last may be short.
    static func rows<Item>(_ items: [Item], columns: Int) -> [[Item]] {
        let size = max(1, columns)
        return stride(from: 0, to: items.count, by: size).map { Array(items[$0..<min($0 + size, items.count)]) }
    }

    /// Chunk identifiable items into rows that remember each item's position in the
    /// whole list, for staggered fades and scroll targets (row-major, R2).
    ///
    /// - Parameters:
    ///   - items: The section's items, in order.
    ///   - columns: Items per row (at least 1).
    /// - Returns: The rows; one per item in one column, so each keeps the item's identity.
    static func indexedRows<Item: Identifiable>(_ items: [Item], columns: Int) -> [WideColumnsRowItems<Item>] {
        let size = max(1, columns)
        return stride(from: 0, to: items.count, by: size).map {
            WideColumnsRowItems(start: $0, items: Array(items[$0..<min($0 + size, items.count)]))
        }
    }

    /// The flattened index of the first item in the row holding `index`: the row a
    /// scroll-to-item targets, since a row's identity is its first item's.
    ///
    /// - Parameters:
    ///   - index: An item's position in the whole list.
    ///   - columns: Items per row (at least 1).
    /// - Returns: The row's first position.
    static func rowStart(of index: Int, columns: Int) -> Int {
        let size = max(1, columns)
        return index - index % size
    }

    // MARK: Balanced columns

    /// Where two column-major columns split a page of unequal sections (R7): the left
    /// column takes `0..<split`, the right `split...`, choosing the split that makes the
    /// taller column shortest (the earliest on a tie). Neither column is empty.
    ///
    /// - Parameters:
    ///   - leading: Each section's height at the left column's width, in order.
    ///   - trailing: Each section's height at the right column's width, in order.
    ///   - spacing: Vertical gap between stacked sections.
    /// - Returns: The first index of the right column, in `1..<count`; 0 or 1 for fewer
    ///   than two sections.
    static func balancedSplit(leading: [CGFloat], trailing: [CGFloat], spacing: CGFloat) -> Int {
        let count = min(leading.count, trailing.count)
        guard count >= 2 else { return count }
        func stacked(_ heights: ArraySlice<CGFloat>) -> CGFloat {
            heights.reduce(0, +) + spacing * CGFloat(max(0, heights.filter { $0 > 0 }.count - 1))
        }
        var best = 1
        var bestHeight = CGFloat.infinity
        for split in 1..<count {
            let tallest = max(stacked(leading[0..<split]), stacked(trailing[split..<count]))
            if tallest < bestHeight - 0.5 {
                best = split
                bestHeight = tallest
            }
        }
        return best
    }

    // MARK: Mac sheet size

    /// Default Search sheet size in a wide landscape Mac window: room for two columns.
    static let macWideSheet = CGSize(width: 880, height: 640)

    /// Default Search sheet size otherwise: one readable column (the web modal's shape).
    static let macNarrowSheet = CGSize(width: 620, height: 680)

    /// The Mac Search sheet's opening size for its window (HIG Sheets, macOS: "Present
    /// a sheet in a reasonable default size"); it stays resizable either way.
    ///
    /// - Parameter window: The presenting window's content size (zero before measurement).
    /// - Returns: ``macWideSheet`` when the window is landscape and wide enough to hold
    ///   it with room around it, else ``macNarrowSheet``.
    static func macSheetSize(window: CGSize) -> CGSize {
        window.width > window.height && window.width >= macWideSheet.width + 80
            && window.height >= macWideSheet.height + 60 ? macWideSheet : macNarrowSheet
    }
}

// MARK: - Board rows

/// One row of a two-column list: up to `columns` consecutive items and the position of
/// the first in the whole list. Its identity is its first item's, so in one column each
/// row keeps its item's identity and a scroll-to-item targets the row's first item
/// (``WideColumns/rowStart(of:columns:)``).
struct WideColumnsRowItems<Item: Identifiable>: Identifiable {
    /// The first item's position in the whole list.
    let start: Int
    /// The row's items, in order.
    let items: [Item]

    var id: Item.ID { items[0].id }

    /// Each item with its position in the whole list (fade stagger, keyboard order).
    var indexed: [(index: Int, item: Item)] {
        items.enumerated().map { (index: start + $0.offset, item: $0.element) }
    }
}

/// One row of a full-page list in wide landscape (pattern `wide-columns`, issue #353):
/// its cells side by side through ``HingeRow`` with the page hinge, padded with clear
/// cells to `columns`; in one column the single cell as is. Cells should fill their
/// width (`.frame(maxWidth: .infinity)`).
struct WideColumnsRow<Content: View>: View {
    private let columns: Int
    private let count: Int
    private let matchesHeights: Bool
    private let content: Content

    /// Create a row.
    ///
    /// - Parameters:
    ///   - columns: Columns across the page.
    ///   - count: Cells `content` draws (a short last row pads the rest).
    ///   - matchesHeights: Offer every cell the pair's height, for rows that are
    ///     segments of one group card per column (``FestivalGroupSegment``, #543).
    ///   - content: The cells.
    init(columns: Int, count: Int, matchesHeights: Bool = false, @ViewBuilder content: () -> Content) {
        self.columns = columns
        self.count = count
        self.matchesHeights = matchesHeights
        self.content = content()
    }

    var body: some View {
        if columns > 1 {
            HingeRow(spacing: WideColumns.spacing, matchesHeights: matchesHeights) {
                content
                ForEach(count..<max(count, columns), id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                }
            }
        } else {
            content
        }
    }
}

extension View {
    /// Keep `columns` at the page's wide-landscape column count
    /// (``WideColumns/count(layout:size:subPage:)``) from the page's own measured size,
    /// device layout and split role. Apply to the full-width page container.
    ///
    /// - Parameter columns: The page's column count.
    /// - Returns: The measured page.
    func wideColumnsCount(_ columns: Binding<Int>) -> some View {
        modifier(WideColumnsCountModifier(columns: columns))
    }
}

/// Implementation of ``SwiftUI/View/wideColumnsCount(_:)``.
private struct WideColumnsCountModifier: ViewModifier {
    @Binding var columns: Int
    @Environment(\.deviceLayout) private var layout
    @Environment(\.splitPaneSubPage) private var subPage
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .onChange(of: WideColumns.count(layout: layout, size: size, subPage: subPage), initial: true) { _, count in
                if columns != count { columns = count }
            }
    }
}

// MARK: - Balanced column stack

/// A page of unequal section cards (Settings) in one stacked column, or in two
/// column-major columns balanced by height in wide landscape (pattern `wide-columns`
/// R7, agent decision #355). Reading order stays top to bottom, then the next column,
/// so VoiceOver, Quick Links and the load-in stagger keep the one-column sequence. The
/// columns meet at the iPhone Duo book-pose hinge like ``HingeRow`` (R3; flat, at the
/// free space's midpoint, owner #361). One view for both
/// counts, so rotating reflows the same sections in place (R4).
struct WideColumnStack<Content: View>: View {
    private let columns: Int
    private let spacing: CGFloat
    private let content: Content
    @Environment(\.deviceLayout) private var layout
    @State private var span: HorizontalSpan?

    /// Create a stack.
    ///
    /// - Parameters:
    ///   - columns: 1 or 2, from ``WideColumns/count(layout:width:)``.
    ///   - spacing: Vertical gap between sections.
    ///   - content: The sections, in reading order.
    init(columns: Int, spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.columns = columns
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        let band = columns > 1 ? HingeColumns.band(
            span: span, fold: layout.splitHinge, gutter: WideColumns.spacing,
            minimumSide: HingeColumns.minimumSide
        ) : nil
        WideColumnStackLayout(columns: columns, spacing: spacing, gutter: WideColumns.spacing, band: band) {
            if #available(iOS 18.0, macOS 15.0, *) {
                // VoiceOver otherwise orders by geometry and would interleave the two
                // columns row by row; each section reads whole, in page order.
                Group(subviews: content) { sections in
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        section
                            .accessibilityElement(children: .contain)
                            .accessibilitySortPriority(Double(sections.count - index))
                    }
                }
            } else {
                content
            }
        }
        .accessibilityElement(children: .contain)
        .measuresHorizontalSpan($span)
    }
}

/// Places sections stacked (like a leading `VStack`), or in two columns split by
/// ``WideColumns/balancedSplit(leading:trailing:spacing:)``; each keeps its own height.
struct WideColumnStackLayout: Layout {
    /// 1 or 2.
    var columns: Int
    /// Vertical gap between sections.
    var spacing: CGFloat
    /// Gap between the two columns.
    var gutter: CGFloat
    /// The hinge's band across the stack, or nil.
    var band: HingeBand?

    /// Each section's frame for a width.
    ///
    /// - Parameters:
    ///   - width: The stack's width.
    ///   - subviews: The sections.
    /// - Returns: One frame per section, in the stack's coordinates: its column's width
    ///   (the section sizes itself within it, leading-aligned) and its own height.
    func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        guard columns > 1, subviews.count > 1 else {
            return stack(subviews.indices, x: 0, width: width, subviews: subviews)
        }
        let cells = HingeRowLayout(spacing: gutter, band: band).cells(width: width, count: 2)
        let leading = subviews.map { $0.sizeThatFits(ProposedViewSize(width: cells[0].width, height: nil)).height }
        let trailing = subviews.map { $0.sizeThatFits(ProposedViewSize(width: cells[1].width, height: nil)).height }
        let split = WideColumns.balancedSplit(leading: leading, trailing: trailing, spacing: spacing)
        return stack(0..<split, x: cells[0].x, width: cells[0].width, subviews: subviews)
            + stack(split..<subviews.count, x: cells[1].x, width: cells[1].width, subviews: subviews)
    }

    /// Stack a run of sections top-down at one column's position, skipping the gap
    /// around empty (zero-height) sections.
    private func stack(_ range: Range<Int>, x: CGFloat, width: CGFloat, subviews: Subviews) -> [CGRect] {
        var y: CGFloat = 0
        return range.map { index in
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            if size.height > 0, y > 0 { y += spacing }
            let frame = CGRect(x: x, y: y, width: width, height: size.height)
            y += size.height
            return frame
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let height = frames(width: width, subviews: subviews).map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: nil)
            )
        }
    }
}
