import SwiftUI
import FestivalCore
import FestivalDesign

#if os(iOS)
import UIKit
#endif

// MARK: - Section index scrubber

/// Contacts-style "drag to jump" strip for the Songs list's right edge.
///
/// Shown only while the active sort has more than one `SongSection` (Title,
/// Artist or Year); the caller animates it in and out as the sort changes.
struct SongSectionIndexScrubber: View {
    /// Padding above the first label and below the last, inside the capsule.
    static let labelInset: CGFloat = 6

    let sections: [SongSection]
    let onSelect: (Int) -> Void
    @Environment(\.deviceLayout) private var deviceLayout
    @State private var activeIndex: Int = 0
    @State private var isActive = false
    /// The section under the current touch; nil between touches, so every new touch
    /// jumps, even to the section the previous touch chose (issue #9: tapping the last
    /// chosen letter again after scrolling by hand did nothing).
    @State private var touchIndex: Int?
    /// The strip's own rendered height, read back only to map a touch's Y position
    /// to a section — never fed back into the strip's own frame. Using the List's
    /// proposed height there (previously `GeometryReader { geometry in … .frame(height:
    /// geometry.size.height) }`) stretched the capsule to the full list height and
    /// re-measured it whenever that height changed, e.g. when a large title collapses
    /// and hands the List more room: the strip grew and its centered content visibly
    /// crept upward, spilling past the first/last label and over the rows underneath.
    @State private var measuredHeight: CGFloat = 0
    #if os(iOS)
    private let feedback = UISelectionFeedbackGenerator()
    #endif

    /// The strip sits inside the content's safe area, which on iPhone Duo already
    /// ends at the system vertical bar; only a hardware cutout beyond it needs extra
    /// room (`cutoutInsets`). `overlayInsets` here counted the bar twice and left a
    /// bar-wide gap between the strip and the rail.
    private var trailingMargin: CGFloat {
        max(2, deviceLayout.cutoutInsets.trailing)
    }

    var body: some View {
        VStack(spacing: 1) {
            ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                Text(section.label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(
                        isActive && index == activeIndex
                            ? BrandTokens.gold : FestivalText.primary
                    )
            }
        }
        .padding(.vertical, Self.labelInset)
        // Intrinsic size — as tall as its own letters, never the full list height.
        // The caller centers it in a region with a fixed top, so a collapsing large
        // title does not move it.
        .frame(width: 22)
        .festivalCardCapsule()
        .contentShape(Rectangle())
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { measuredHeight = geometry.size.height }
                    .onChange(of: geometry.size.height) { _, newValue in
                        measuredHeight = newValue
                    }
            }
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    update(for: value.location.y, height: measuredHeight)
                }
                .onEnded { _ in
                    isActive = false
                    touchIndex = nil
                }
        )
        .padding(.vertical, 8)
        .padding(.trailing, trailingMargin)
        .accessibilityElement()
        .accessibilityLabel("Jump to section")
        .accessibilityValue(sections[safeIndex: activeIndex]?.label ?? "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(by: 1)
            case .decrement: move(by: -1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("fst.songs.section-index")
    }

    /// Resolve and announce the section under a drag location.
    ///
    /// - Parameters:
    ///   - y: Vertical touch position relative to the scrubber's own frame.
    ///   - height: Current measured height of the scrubber's own content (not the
    ///     enclosing list), so the mapping stays accurate at its intrinsic size.
    private func update(for y: CGFloat, height: CGFloat) {
        guard let index = Self.sectionIndex(
            at: y, height: height, inset: Self.labelInset, count: sections.count
        ) else { return }
        isActive = true
        guard index != touchIndex else { return }
        touchIndex = index
        if index != activeIndex {
            activeIndex = index
            #if os(iOS)
            feedback.selectionChanged()
            #endif
        }
        onSelect(sections[index].id)
    }

    /// The section label under a touch.
    ///
    /// Maps over the labels only, not the capsule's padding above and below them:
    /// mapping over the whole height (issue #9) chose a neighbouring section for up to
    /// ~40% of a label near either end (a tap on "W" jumped to "V").
    ///
    /// - Parameters:
    ///   - y: Touch position in the scrubber's own space, padding included.
    ///   - height: The scrubber's measured height, padding included.
    ///   - inset: Padding above the first label and below the last.
    ///   - count: Number of sections (labels, evenly stacked).
    /// - Returns: The section index, clamped to the labels, or nil without sections.
    static func sectionIndex(at y: CGFloat, height: CGFloat, inset: CGFloat, count: Int) -> Int? {
        guard count > 0, y.isFinite, height.isFinite, inset.isFinite else { return nil }
        let span = max(height - 2 * inset, 1)
        let position = (y - inset) / span * CGFloat(count)
        return Int(min(CGFloat(count - 1), max(0, position)).rounded(.down))
    }

    /// Move the VoiceOver adjustable cursor by one section and jump to it.
    ///
    /// - Parameter delta: +1 for increment, -1 for decrement.
    private func move(by delta: Int) {
        guard !sections.isEmpty else { return }
        let index = min(sections.count - 1, max(0, activeIndex + delta))
        activeIndex = index
        onSelect(sections[index].id)
    }
}

private extension Array {
    subscript(safeIndex index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
