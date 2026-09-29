import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - SettingsReorderList

/// An inline drag-to-reorder list inside a Settings card, the native form of the web's
/// `ReorderList` (`components/sort/ReorderList.tsx`, `SortableRow.tsx`): bordered rows with
/// a grip glyph and a semibold label, reordered by dragging.
///
/// Drag a row by its grip handle; swiping elsewhere on the list scrolls the page. The page
/// stops scrolling only while a row is lifted (`SettingsReorderDragActiveKey`). Each row also offers **Move Up** / **Move Down** accessibility
/// actions and announces its position, so VoiceOver and Switch Control can reorder without
/// a drag. The math lives in `SettingsReorder` (FestivalCore) so it is unit-tested.
struct SettingsReorderList<Item: Hashable>: View {
    let items: [Item]
    let label: (Item) -> String
    let key: (Item) -> String
    /// Accessibility identifier prefix; each row is `<identifier>.<key>`.
    let identifier: String
    let onMove: ([Item]) -> Void

    /// The lifted row and its vertical drag distance. `@GestureState` resets itself when the
    /// system cancels a drag (no stuck lifted row or disabled page scrolling).
    @GestureState private var drag: DragState?
    @State private var rowHeight: CGFloat = 48
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Create a list.
    ///
    /// - Parameters:
    ///   - items: Rows in their current order.
    ///   - identifier: Accessibility identifier prefix for the list and its rows.
    ///   - label: Visible row title.
    ///   - key: Stable identifier suffix for a row.
    ///   - onMove: Receives the complete new order after a drag or accessibility move.
    init(
        items: [Item], identifier: String,
        label: @escaping (Item) -> String, key: @escaping (Item) -> String,
        onMove: @escaping ([Item]) -> Void
    ) {
        self.items = items
        self.identifier = identifier
        self.label = label
        self.key = key
        self.onMove = onMove
    }

    private struct DragState: Equatable {
        let item: Item
        var translation: CGFloat
    }

    private var dragging: Item? { drag?.item }
    private var translation: CGFloat { drag?.translation ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                row(item, index: index)
                    .zIndex(dragging == item ? 1 : 0)
                if index < items.count - 1 {
                    Rectangle()
                        .fill(BrandTokens.glassBorder)
                        .frame(height: 1)
                        .accessibilityHidden(true)
                }
            }
        }
        .background(BrandTokens.surfaceMuted.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(BrandTokens.glassBorder, lineWidth: 1))
        .sensoryFeedback(.selection, trigger: currentDestination)
        .preference(key: SettingsReorderDragActiveKey.self, value: dragging != nil)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Row

    private func row(_ item: Item, index: Int) -> some View {
        let isDragging = dragging == item
        return HStack(spacing: 14) {
            // The grip is the drag handle (44 pt target). Only touches that start on it
            // reorder; anywhere else on the row scrolls the page — a drag gesture over the
            // whole row, even a simultaneous or long-press one, stops a SwiftUI ScrollView
            // from scrolling on iOS 26.
            Image(systemName: "line.3.horizontal")
                .font(.body.weight(.semibold))
                .foregroundStyle(FestivalText.deemphasized)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .gesture(dragGesture(for: item, at: index))
                .padding(.vertical, -10)
                .padding(.leading, -12)
                .accessibilityHidden(true)
            Text(label(item))
                .font(.body.weight(.semibold))
                .foregroundStyle(FestivalText.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 48)
        .background {
            if isDragging {
                RoundedRectangle(cornerRadius: 8)
                    .fill(BrandTokens.surfaceFrosted)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
            }
        }
        .background {
            if index == 0 {
                GeometryReader { proxy in
                    Color.clear.preference(key: ReorderRowHeightKey.self, value: proxy.size.height)
                }
            }
        }
        .onPreferenceChange(ReorderRowHeightKey.self) { height in
            // Rows are separated by a 1 pt hairline.
            if height > 0 { rowHeight = height + 1 }
        }
        .contentShape(Rectangle())
        .offset(y: offset(for: item, at: index))
        .scaleEffect(isDragging ? 1.02 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(item))
        .accessibilityValue("\(index + 1) of \(items.count)")
        .accessibilityHint("Drag the handle to reorder, or use the Move actions.")
        .accessibilityAction(named: "Move Up") { move(from: index, to: index - 1) }
        .accessibilityAction(named: "Move Down") { move(from: index, to: index + 1) }
        .accessibilityIdentifier("\(identifier).\(key(item))")
    }

    // MARK: - Dragging

    /// The dragged row follows the finger; rows it passes slide one slot the other way.
    private func offset(for item: Item, at index: Int) -> CGFloat {
        guard let dragging, let from = items.firstIndex(of: dragging) else { return 0 }
        if item == dragging { return translation }
        let to = destination(from: from)
        if from < to, index > from, index <= to { return -rowHeight }
        if from > to, index < from, index >= to { return rowHeight }
        return 0
    }

    private func destination(from index: Int) -> Int {
        SettingsReorder.destination(
            from: index, translation: translation, rowHeight: rowHeight, count: items.count
        )
    }

    /// Destination of the row being dragged, for the selection haptic.
    private var currentDestination: Int? {
        guard let dragging, let from = items.firstIndex(of: dragging) else { return nil }
        return destination(from: from)
    }

    private func dragGesture(for item: Item, at index: Int) -> some Gesture {
        // Global space: the row (and its handle) moves with the finger, so a local
        // translation would feed back into itself.
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .updating($drag) { value, state, transaction in
                transaction.animation = reduceMotion ? nil : .interactiveSpring
                state = DragState(item: item, translation: value.translation.height)
            }
            .onEnded { value in
                let to = SettingsReorder.destination(
                    from: index, translation: value.translation.height,
                    rowHeight: rowHeight, count: items.count
                )
                guard to != index else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    onMove(SettingsReorder.moved(items, from: index, to: to))
                }
            }
    }

    private var animation: Animation? { reduceMotion ? nil : .easeOut(duration: 0.15) }

    /// Accessibility / programmatic move by one slot.
    private func move(from: Int, to: Int) {
        guard items.indices.contains(to) else { return }
        onMove(SettingsReorder.moved(items, from: from, to: to))
    }
}

/// True while any reorder row is lifted; the enclosing page disables scrolling so the
/// drag moves the row instead of the page.
struct SettingsReorderDragActiveKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// First row's measured height, so a drag moves one slot per row at any text size.
private struct ReorderRowHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
