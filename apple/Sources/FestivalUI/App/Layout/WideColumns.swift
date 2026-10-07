import SwiftUI

// MARK: - WideColumns

/// The app-wide rule for page content in wide landscape (pattern `wide-columns`,
/// issue #350): two columns of rows when the window is landscape and regular in both
/// dimensions (iPad landscape, iPhone Duo inner display in landscape, a wide Mac sheet
/// or window), one column otherwise (iPhone, any portrait window, folded Duo, compact
/// Split View or Stage Manager windows).
///
/// Rows flow row-major (left then right, then down) under full-width section headers;
/// a short last row keeps its card at column width. Rows draw through ``HingeRow`` with
/// ``HingeRow/Hinge/page``, so on iPhone Duo the gutter sits on the hinge whether the
/// display is flat or folded (`.agents/patterns/wide-columns.md`).
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
    private let content: Content

    /// Create a row.
    ///
    /// - Parameters:
    ///   - columns: Columns across the page.
    ///   - count: Cells `content` draws (a short last row pads the rest).
    ///   - content: The cells.
    init(columns: Int, count: Int, @ViewBuilder content: () -> Content) {
        self.columns = columns
        self.count = count
        self.content = content()
    }

    var body: some View {
        if columns > 1 {
            HingeRow(spacing: WideColumns.spacing, hinge: .page) {
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
