import CoreGraphics
import Testing
@testable import FestivalUI

/// Issue #336: the A–Z strip fits the height it is offered, condensing its labels with
/// bullets where they don't all fit (iPhone Duo outer display in landscape).
struct SongSectionIndexScrubberFitTests {
    /// The Title sort's 27 buckets: "#" then A–Z.
    private let titleLabels = ["#"] + (65...90).map { String(UnicodeScalar($0)!) }

    @Test func unmeasuredOrInvalidHeightsAreUnbounded() {
        #expect(SongSectionIndexScrubber.capacity(availableHeight: nil, labelHeight: 12) == nil)
        #expect(SongSectionIndexScrubber.capacity(availableHeight: 0, labelHeight: 12) == nil)
        #expect(SongSectionIndexScrubber.capacity(availableHeight: .infinity, labelHeight: 12) == nil)
        #expect(SongSectionIndexScrubber.capacity(availableHeight: 300, labelHeight: 0) == nil)
        #expect(SongSectionIndexScrubber.entries(labels: titleLabels, capacity: nil).count == 27)
    }

    @Test func capacityCountsLabelsBetweenThePaddings() {
        // Live iPhone Duo outer landscape: a 300 pt region holds a 284 pt capsule,
        // 6 pt inset at each end and 21 rows of 12 pt labels 1 pt apart.
        #expect(SongSectionIndexScrubber.capacity(availableHeight: 300, labelHeight: 12) == 21)
        // The full Title strip (378 pt with its outer padding) fits exactly.
        #expect(SongSectionIndexScrubber.capacity(availableHeight: 378, labelHeight: 12) == 27)
        #expect(SongSectionIndexScrubber.capacity(availableHeight: 377, labelHeight: 12) == 26)
        // Never below one row.
        #expect(SongSectionIndexScrubber.capacity(availableHeight: 10, labelHeight: 12) == 1)
    }

    @Test func everyLabelShowsWhenTheyFit() {
        let rows = SongSectionIndexScrubber.entries(labels: titleLabels, capacity: 27)
        #expect(rows.map(\.label) == titleLabels)
        #expect(rows.map(\.section) == Array(0..<27))
    }

    @Test func condensedStripFitsAndKeepsBothEnds() {
        for capacity in 3..<27 {
            let rows = SongSectionIndexScrubber.entries(labels: titleLabels, capacity: capacity)
            #expect(rows.count <= capacity, "capacity \(capacity)")
            #expect(rows.first == .init(label: "#", section: 0))
            #expect(rows.last == .init(label: "Z", section: 26))
            // Top to bottom, every row selects a later section than the one above it.
            #expect(zip(rows, rows.dropFirst()).allSatisfy { $0.section < $1.section })
            // A bullet only ever stands between two labels.
            for (index, row) in rows.enumerated() where row.label == SongSectionIndexScrubber.bullet {
                #expect(index > 0 && index < rows.count - 1)
                #expect(rows[index - 1].label != SongSectionIndexScrubber.bullet)
                #expect(rows[index + 1].label != SongSectionIndexScrubber.bullet)
            }
        }
    }

    @Test func outerLandscapeAlternatesLabelsAndBullets() {
        let rows = SongSectionIndexScrubber.entries(labels: titleLabels, capacity: 21)
        #expect(rows.map(\.label) == [
            "#", "•", "C", "•", "E", "•", "H", "•", "J", "•", "M",
            "•", "P", "•", "R", "•", "U", "•", "W", "•", "Z",
        ])
        // A bullet stands for the sections it skips ("A" and "B" between "#" and "C").
        #expect(rows[1].sections == 1...2)
    }

    @Test func veryShortStripsDropTheBullets() {
        #expect(SongSectionIndexScrubber.entries(labels: titleLabels, capacity: 1).map(\.label) == ["#"])
        #expect(SongSectionIndexScrubber.entries(labels: titleLabels, capacity: 2).map(\.label) == ["#", "Z"])
    }

    @Test func threeRowsShowBothEndsAndOneBullet() {
        let rows = SongSectionIndexScrubber.entries(labels: ["#", "A", "B", "C"], capacity: 3)
        #expect(rows == [
            .init(label: "#", section: 0), .init(label: "•", sections: 1...2), .init(label: "C", section: 3),
        ])
    }

    @Test func rowsCoverEverySectionOnceInOrder() {
        for capacity in 3..<27 {
            let rows = SongSectionIndexScrubber.entries(labels: titleLabels, capacity: capacity)
            #expect(rows.flatMap { Array($0.sections) } == Array(0..<27), "capacity \(capacity)")
        }
    }

    /// A drag down the condensed outer-landscape strip passes through every section in
    /// order, and a touch on a drawn label selects that label (issue #9's rule).
    @Test func dragReachesEverySectionAndLabelsLandOnThemselves() {
        let rows = SongSectionIndexScrubber.entries(labels: titleLabels, capacity: 21)
        let inset = SongSectionIndexScrubber.labelInset
        let pitch: CGFloat = 13
        let height = CGFloat(rows.count) * pitch + 2 * inset
        var seen: [Int] = []
        var y: CGFloat = 0
        while y <= height {
            if let section = SongSectionIndexScrubber.section(
                at: y, height: height, inset: inset, entries: rows
            ), seen.last != section {
                seen.append(section)
            }
            y += 0.25
        }
        #expect(seen == Array(0..<27))
        for (row, entry) in rows.enumerated() where entry.label != SongSectionIndexScrubber.bullet {
            let centre = inset + (CGFloat(row) + 0.5) * pitch
            #expect(SongSectionIndexScrubber.section(
                at: centre, height: height, inset: inset, entries: rows
            ) == entry.section)
        }
        #expect(SongSectionIndexScrubber.section(at: 0, height: height, inset: inset, entries: []) == nil)
    }
}
