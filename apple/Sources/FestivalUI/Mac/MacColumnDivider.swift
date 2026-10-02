#if os(macOS)
import AppKit
import SwiftUI

// MARK: - Column divider

/// The draggable divider between the list and detail columns.
///
/// HIG Split views › macOS: panes side by side "draggable dividers resize them …
/// Prefer the 1 pt thin divider". It draws the system 1 pt `Divider` with an 8 pt
/// invisible grab area and the column-resize pointer (HIG Pointing devices › macOS:
/// "Resize left/right … Resize or move a window, view or element"). Dragging updates
/// the width live; the clamped width is remembered when the drag ends. A double click
/// returns to the automatic width. Assistive technologies see a slider that adjusts it
/// in 20 pt steps.
struct MacColumnDivider: View {
    /// The list column width currently drawn.
    let listWidth: CGFloat
    /// Widths the divider can take at the current content width.
    let range: ClosedRange<CGFloat>
    /// Live width while dragging (nil when idle).
    @Binding var dragWidth: CGFloat?
    /// Called with the width to remember when a drag or adjustment ends (nil resets
    /// to automatic).
    let commit: (CGFloat?) -> Void
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var dragStart: CGFloat?
    @State private var cursorPushed = false

    /// Grab area width (points) centred on the 1 pt line.
    static let hitWidth: CGFloat = 8

    var body: some View {
        Divider()
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: Self.hitWidth)
                    .contentShape(Rectangle())
                    .onHover { inside in updateCursor(inside) }
                    .gesture(drag)
                    .onTapGesture(count: 2) { commit(nil) }
            }
            .onDisappear { updateCursor(false) }
            .help("Drag to resize the list. Double-click to reset.")
            // A slider to assistive technologies: "Column Divider", its width in
            // points, adjustable in 20 pt steps.
            .accessibilityRepresentation {
                Slider(
                    value: Binding(get: { Double(listWidth) }, set: { commit(CGFloat($0)) }),
                    in: Double(range.lowerBound)...Double(max(range.lowerBound + 1, range.upperBound)),
                    step: Double(MacLayoutPolicy.dividerStep)
                ) {
                    Text("Column Divider")
                }
                .accessibilityValue("\(Int(listWidth.rounded())) points")
            }
            .accessibilityIdentifier("fst.nav.column-divider")
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let start = dragStart ?? listWidth
                dragStart = start
                let delta = layoutDirection == .rightToLeft ? -value.translation.width : value.translation.width
                dragWidth = start + delta
            }
            .onEnded { _ in
                let final = dragWidth
                dragStart = nil
                dragWidth = nil
                if let final { commit(final) }
            }
    }

    /// Show the column-resize pointer while over the grab area.
    private func updateCursor(_ inside: Bool) {
        guard inside != cursorPushed else { return }
        cursorPushed = inside
        if inside {
            Self.resizeCursor.push()
        } else {
            NSCursor.pop()
        }
    }

    /// The system column-resize pointer (`NSCursor.columnResize` from macOS 15; the
    /// older left/right resize pointer before).
    private static var resizeCursor: NSCursor {
        if #available(macOS 15.0, *) {
            return NSCursor.columnResize(directions: .all)
        }
        return NSCursor.resizeLeftRight
    }
}
#endif
