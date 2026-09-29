import Foundation

// MARK: - Reorder math

/// Pure helpers behind Settings' inline drag-to-reorder lists (Song Row Visual Order and
/// CHOpt Text Path Column Order), the native form of the web's `ReorderList`
/// (`components/sort/ReorderList.tsx`) and its `onReorder` callbacks in `SettingsPage.tsx`.
public enum SettingsReorder {
    /// Index a dragged row lands on, from its vertical drag distance.
    ///
    /// A row moves one slot for every full row height dragged, rounding at the half-row
    /// point like dnd-kit's `closestCenter` collision detection.
    ///
    /// - Parameters:
    ///   - index: Row's index when the drag began.
    ///   - translation: Vertical drag distance in points (negative = up).
    ///   - rowHeight: Height of one row, including any spacing between rows.
    ///   - count: Number of rows in the list.
    /// - Returns: Destination index clamped to `0..<count`, or `index` for invalid input.
    public static func destination(
        from index: Int, translation: Double, rowHeight: Double, count: Int
    ) -> Int {
        guard count > 0, index >= 0, index < count, rowHeight > 0, translation.isFinite else {
            return index
        }
        let steps = Int((translation / rowHeight).rounded())
        return min(count - 1, max(0, index + steps))
    }

    /// Move one element, like dnd-kit's `arrayMove`.
    ///
    /// - Parameters:
    ///   - items: Current order.
    ///   - from: Index of the element to move.
    ///   - to: Index the element occupies afterwards.
    /// - Returns: The reordered list, or `items` unchanged for an out-of-range index.
    public static func moved<T>(_ items: [T], from: Int, to: Int) -> [T] {
        guard items.indices.contains(from), items.indices.contains(to), from != to else {
            return items
        }
        var result = items
        let element = result.remove(at: from)
        result.insert(element, at: to)
        return result
    }

    /// Fold a reordered visible subset back into the full saved order.
    ///
    /// The web's Song Row Visual Order list shows only metadata fields that are currently
    /// visible; hidden fields keep their relative order and follow the visible ones
    /// (`[...items.map(i => i.key), ...hiddenKeys]`).
    ///
    /// - Parameters:
    ///   - visible: Visible items in their new order.
    ///   - full: Previous full order, including hidden items.
    /// - Returns: Visible items first, then every hidden item in its previous order.
    public static func merging<T: Hashable>(visible: [T], into full: [T]) -> [T] {
        let shown = Set(visible)
        return visible + full.filter { !shown.contains($0) }
    }

    /// VoiceOver label for a row's position, e.g. "Score, 1 of 8".
    ///
    /// - Parameters:
    ///   - label: Row title.
    ///   - index: Zero-based position.
    ///   - count: Number of rows.
    /// - Returns: Spoken position value.
    public static func positionDescription(_ label: String, index: Int, count: Int) -> String {
        "\(label), \(index + 1) of \(count)"
    }
}
