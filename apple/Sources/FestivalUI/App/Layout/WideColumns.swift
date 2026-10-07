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
