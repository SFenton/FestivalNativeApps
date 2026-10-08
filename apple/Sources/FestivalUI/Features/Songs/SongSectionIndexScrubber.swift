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
///
/// The strip is never taller than the height it is offered (issue #336). Where all
/// labels don't fit, such as the iPhone Duo outer display in landscape, it shows evenly
/// spaced labels with a bullet between them, as the system table index does; a drag
/// still spans the whole range and the VoiceOver adjustable action still steps through
/// every section. A rigid strip there forced the whole Songs page
/// taller than the window: rows slid under the title and the bottom Filter field left
/// the screen (HIG Designing for iPhone Duo: "The outer display is wider and shorter
/// than other iPhone displays"; "use margins/safe-area insets and avoid fixed widths
/// or display-specific dependencies").
struct SongSectionIndexScrubber: View {
    /// Padding above the first label and below the last, inside the capsule.
    static let labelInset: CGFloat = 6
    /// Space between two labels.
    static let labelSpacing: CGFloat = 1
    /// Margin above and below the capsule, inside the strip's frame.
    static let outerPadding: CGFloat = 8
    /// The label line height before the first label is measured (caption2 rounded).
    static let defaultLabelHeight: CGFloat = 12
    /// The largest text size the labels follow: caption2 reaches 24 pt there, over
    /// 200% of its 11 pt default (issue #391), while the strip stays a narrow column.
    static let largestTextSize = DynamicTypeSize.accessibility2
    /// What stands in for the labels a condensed strip skips.
    static let bullet = "•"

    /// One row of the strip: a section's label, or a bullet for skipped sections.
    struct Entry: Equatable {
        /// The text drawn: the section label or ``SongSectionIndexScrubber/bullet``.
        let label: String
        /// The sections (indices into `sections`) this row stands for: one for a label,
        /// the skipped run for a bullet.
        let sections: ClosedRange<Int>

        /// Creates a row.
        ///
        /// - Parameters:
        ///   - label: The text drawn.
        ///   - sections: The sections the row stands for.
        init(label: String, sections: ClosedRange<Int>) {
            self.label = label
            self.sections = sections
        }

        /// Creates a row for one section's label.
        ///
        /// - Parameters:
        ///   - label: The section's label.
        ///   - section: The section's index.
        init(label: String, section: Int) {
            self.init(label: label, sections: section...section)
        }

        /// The middle section this row stands for.
        var section: Int { (sections.lowerBound + sections.upperBound) / 2 }
    }

    let sections: [SongSection]
    /// How far below the top of its region the strip's capsule must start: the part of
    /// the region the expanded navigation bar covers (``topClearance(chromeBottom:regionTop:)``).
    /// The strip stays centered in its region and only moves down when it would
    /// otherwise start under that bar.
    var topClearance: CGFloat = 0
    let onSelect: (Int) -> Void
    @Environment(\.deviceLayout) private var deviceLayout
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
    /// The height offered to the strip (nil until measured); bounds its row count.
    @State private var availableHeight: CGFloat?
    /// One label's rendered line height, measured from the first row.
    @State private var labelHeight = Self.defaultLabelHeight
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

    /// The rows that fit the offered height.
    private var entries: [Entry] {
        Self.entries(
            labels: sections.map(\.label),
            capacity: Self.capacity(
                availableHeight: availableHeight.map { max(0, $0 - topClearance) },
                labelHeight: labelHeight
            )
        )
    }

    var body: some View {
        let entries = self.entries
        // Never taller than offered: a rigid strip pushed the page past the window
        // (issue #336). The rows above fit what this frame measures, less the clearance.
        ClearedCenterLayout(clearance: topClearance) { strip(entries) }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if height != availableHeight { availableHeight = height }
            }
    }

    /// The capsule with its rows, gesture and accessibility.
    ///
    /// - Parameter entries: The rows to draw (``entries(labels:capacity:)``).
    /// - Returns: The strip at its intrinsic height.
    private func strip(_ entries: [Entry]) -> some View {
        VStack(spacing: Self.labelSpacing) {
            ForEach(Array(entries.enumerated()), id: \.offset) { row, entry in
                Text(entry.label)
                    .font(.caption2.weight(.semibold))
                    .fontDesign(.rounded)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(
                        isActive && entry.sections.contains(activeIndex)
                            ? BrandTokens.gold : FestivalText.primary
                    )
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        if row == 0, height > 0, height != labelHeight { labelHeight = height }
                    }
            }
        }
        // The labels follow Dynamic Type up to `largestTextSize` (issue #391: a fixed
        // 10 pt never grew); R8 condenses the taller rows to fit.
        .dynamicTypeSize(...Self.largestTextSize)
        .padding(.vertical, Self.labelInset)
        // Intrinsic size — as tall as its own letters, never the full list height.
        // The caller centers it in a region with a fixed top, so a collapsing large
        // title does not move it.
        .frame(width: Self.stripWidth(for: dynamicTypeSize))
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
                    update(for: value.location.y, height: measuredHeight, entries: entries)
                }
                .onEnded { _ in
                    isActive = false
                    touchIndex = nil
                }
        )
        .padding(.vertical, Self.outerPadding)
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
    ///   - entries: The rows drawn (``section(at:height:inset:entries:)``).
    private func update(for y: CGFloat, height: CGFloat, entries: [Entry]) {
        guard let index = Self.section(
            at: y, height: height, inset: Self.labelInset, entries: entries
        ), sections.indices.contains(index) else { return }
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
    nonisolated static func sectionIndex(at y: CGFloat, height: CGFloat, inset: CGFloat, count: Int) -> Int? {
        guard count > 0, y.isFinite, height.isFinite, inset.isFinite else { return nil }
        let span = max(height - 2 * inset, 1)
        let position = (y - inset) / span * CGFloat(count)
        return Int(min(CGFloat(count - 1), max(0, position)).rounded(.down))
    }

    /// The section under a touch on a strip drawing `entries`.
    ///
    /// A label row selects its own section, so a tap lands on the letter drawn. A
    /// bullet row spreads the sections it skipped evenly across its own height, so a
    /// drag still passes through every section, as the system table index does.
    ///
    /// - Parameters:
    ///   - y: Touch position in the scrubber's own space, padding included.
    ///   - height: The scrubber's measured height, padding included.
    ///   - inset: Padding above the first row and below the last.
    ///   - entries: The rows drawn, top to bottom.
    /// - Returns: The section index, clamped to the rows, or nil without rows.
    nonisolated static func section(
        at y: CGFloat, height: CGFloat, inset: CGFloat, entries: [Entry]
    ) -> Int? {
        guard let row = sectionIndex(at: y, height: height, inset: inset, count: entries.count)
        else { return nil }
        let sections = entries[row].sections
        guard sections.count > 1 else { return sections.lowerBound }
        let span = max(height - 2 * inset, 1)
        let position = (y - inset) / span * CGFloat(entries.count) - CGFloat(row)
        let step = Int((min(1, max(0, position)) * CGFloat(sections.count)).rounded(.down))
        return sections.lowerBound + min(sections.count - 1, step)
    }

    /// The part of the strip's region that the expanded navigation bar covers.
    ///
    /// The region's top is fixed below the collapsed bar so a collapsing large title
    /// never moves the strip. At the largest text sizes the *expanded* bar (large title
    /// and Filter field) reaches past the centered strip's top: on iOS 27 at AX3XL it
    /// ends at 323 pt while the strip started at 240 pt, so "#" to "D" sat under the bar,
    /// could not be touched and a tap there focused the search field (issue #391).
    ///
    /// - Parameters:
    ///   - chromeBottom: The List's top content inset while it rests at its top: the
    ///     expanded bar's bottom edge, in the region's (window) space; 0 when unknown.
    ///   - regionTop: The region's top edge in the same space.
    /// - Returns: The clearance, at least 0; ``outerPadding`` already spaces the capsule
    ///   from the bar.
    nonisolated static func topClearance(chromeBottom: CGFloat, regionTop: CGFloat) -> CGFloat {
        guard chromeBottom.isFinite, regionTop.isFinite else { return 0 }
        return max(0, (chromeBottom - regionTop).rounded(.up))
    }

    /// Where the strip's top sits inside its region: centered, but never above
    /// `clearance`.
    ///
    /// - Parameters:
    ///   - regionHeight: The region's height.
    ///   - stripHeight: The strip's height, outer padding included.
    ///   - clearance: ``topClearance(chromeBottom:regionTop:)``.
    /// - Returns: The strip's top offset from the region's top.
    nonisolated static func stripTop(
        regionHeight: CGFloat, stripHeight: CGFloat, clearance: CGFloat
    ) -> CGFloat {
        max((regionHeight - stripHeight) / 2, clearance)
    }

    /// The capsule's width for a text size: 22 pt up to Large, then wide enough for
    /// the caption2 labels, which grow until ``largestTextSize``.
    ///
    /// - Parameter size: The environment's Dynamic Type size.
    /// - Returns: 8 pt of padding plus a 14 pt label column scaled like caption2.
    nonisolated static func stripWidth(for size: DynamicTypeSize) -> CGFloat {
        let caption2: CGFloat = switch min(size, largestTextSize) {
        case .xSmall, .small, .medium, .large: 11
        case .xLarge: 13
        case .xxLarge: 15
        case .xxxLarge: 17
        case .accessibility1: 20
        default: 24
        }
        return (8 + 14 * caption2 / 11).rounded(.up)
    }

    /// How many rows fit the height offered to the strip.
    ///
    /// - Parameters:
    ///   - availableHeight: The strip's offered height, its outer padding included;
    ///     nil (not yet measured) or non-finite means unbounded.
    ///   - labelHeight: One label's line height.
    /// - Returns: The row count that fits, or nil when unbounded.
    nonisolated static func capacity(availableHeight: CGFloat?, labelHeight: CGFloat) -> Int? {
        guard let availableHeight, availableHeight.isFinite, availableHeight > 0,
              labelHeight.isFinite, labelHeight > 0 else { return nil }
        let rows = availableHeight - 2 * outerPadding - 2 * labelInset + labelSpacing
        return max(1, Int((rows / (labelHeight + labelSpacing)).rounded(.down)))
    }

    /// The rows to draw for a strip that fits `capacity` rows.
    ///
    /// Every label when they fit. Otherwise the first and last labels and evenly spaced
    /// ones between them, each skipped run shown as one bullet standing for those
    /// sections, so no more than `capacity` rows are drawn (the system table index's
    /// condensed form).
    ///
    /// - Parameters:
    ///   - labels: Every section's label, in order.
    ///   - capacity: Rows that fit (``capacity(availableHeight:labelHeight:)``); nil
    ///     draws every label.
    /// - Returns: The rows, top to bottom.
    nonisolated static func entries(labels: [String], capacity: Int?) -> [Entry] {
        let all = labels.enumerated().map { Entry(label: $1, section: $0) }
        guard let capacity, labels.count > capacity, labels.count > 1 else { return all }
        let shown = capacity >= 3 ? (capacity + 1) / 2 : max(1, capacity)
        guard shown > 1 else { return [all[0]] }
        let last = labels.count - 1
        let picks = (0..<shown).map { Int((Double($0 * last) / Double(shown - 1)).rounded()) }
        var rows: [Entry] = []
        for (position, section) in picks.enumerated() {
            if position > 0, capacity >= 3 {
                let previous = picks[position - 1]
                if section - previous > 1 {
                    rows.append(Entry(label: bullet, sections: (previous + 1)...(section - 1)))
                }
            }
            rows.append(all[section])
        }
        return rows
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

// MARK: - Placement

/// Centers its one subview vertically in the offered height, but never starts it above
/// `clearance` (``SongSectionIndexScrubber/stripTop(regionHeight:stripHeight:clearance:)``).
/// Like `.frame(minHeight: 0, maxHeight: .infinity)` it takes the whole offered height.
private struct ClearedCenterLayout: Layout {
    let clearance: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let ideal = subview.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: ideal.width, height: proposal.height ?? ideal.height + clearance)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        let room = max(0, bounds.height - clearance)
        let height = min(subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: room)).height, room)
        let top = SongSectionIndexScrubber.stripTop(
            regionHeight: bounds.height, stripHeight: height, clearance: clearance
        )
        subview.place(
            at: CGPoint(x: bounds.midX, y: bounds.minY + top), anchor: .top,
            proposal: ProposedViewSize(width: bounds.width, height: height)
        )
    }
}
