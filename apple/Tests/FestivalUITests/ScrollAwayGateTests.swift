import CoreGraphics
import Testing
@testable import FestivalUI

// MARK: - ScrollAwayGate (issue #5)

/// Feed `(offset, top inset)` samples at one width; returns each decision.
private func decisions(
    _ samples: [(CGFloat, CGFloat)], gate: inout ScrollAwayGate, width: CGFloat = 402
) -> [Bool] {
    samples.map { offset, top in
        gate.update(offsetY: offset, topInset: top, containerWidth: width)
        return gate.isScrolled
    }
}

/// While the large title collapses the inset tracks the offset, so the list is not
/// "scrolled" until it moves past the collapsed bar by the enter distance.
@Test func gateWaitsForTheCollapsedTitlePlusEnterDistance() {
    var gate = ScrollAwayGate()
    let result = decisions(
        [(-228, 228), (-200, 200), (-116, 116), (-100, 116), (-92, 116), (-91, 116)],
        gate: &gate
    )
    #expect(result == [false, false, false, false, false, true])
}

/// The issue #5 loop: moving the tools into the bar restores or removes the title,
/// flipping the top inset 116 ↔ 232 at a fixed offset. Inset-only changes must never
/// flip the decision back.
@Test func insetOnlyChangesNeverFlipTheDecision() {
    var gate = ScrollAwayGate()
    _ = decisions([(-228, 228), (-116, 116), (-60, 116)], gate: &gate)
    #expect(gate.isScrolled)
    for top: CGFloat in [232, 116, 232, 116, 232] {
        let r1 = gate.update(offsetY: -60, topInset: top, containerWidth: 402)
        #expect(!r1)
        #expect(gate.isScrolled)
    }
}

/// The recorded freeze: offset −95.67 with the inset alternating 232/116. Measured
/// from the collapsed inset this is 20.3pt (not scrolled) whatever the chrome does.
@Test func recordedFreezeGeometryIsStable() {
    var gate = ScrollAwayGate()
    _ = decisions([(-228, 228), (-116, 116), (-95.67, 116)], gate: &gate)
    #expect(!gate.isScrolled)
    _ = decisions([(-95.67, 232), (-95.67, 116), (-95.67, 232)], gate: &gate)
    #expect(!gate.isScrolled)
    // A transient expanded inset at a *moving* offset still measures from the collapsed bar.
    _ = decisions([(-90, 232), (-80, 232)], gate: &gate)
    #expect(gate.isScrolled)
    _ = decisions([(-109, 116), (-119, 232), (-125, 232)], gate: &gate)
    #expect(!gate.isScrolled)
}

/// Hysteresis: once scrolled, the list stays scrolled until it is within the exit
/// distance of the top, so a slow drag across 24pt cannot flicker the chrome.
@Test func hysteresisKeepsTheDecisionNearTheThreshold() {
    var gate = ScrollAwayGate()
    let result = decisions(
        [(-116, 116), (-80, 116), (-100, 116), (-106, 116), (-108, 116), (-109, 116),
         (-100, 116), (-92.5, 116), (-91, 116)],
        gate: &gate
    )
    #expect(result == [false, true, true, true, true, false, false, false, true])
}

/// Sub-tolerance jitter is ignored; returning true reports only real changes.
@Test func jitterIsIgnoredAndChangesAreReported() {
    var gate = ScrollAwayGate()
    let r2 = gate.update(offsetY: -116, topInset: 116, containerWidth: 402)
    #expect(!r2)
    let r3 = gate.update(offsetY: -50, topInset: 116, containerWidth: 402)
    #expect(r3)
    let r4 = gate.update(offsetY: -50.2, topInset: 116, containerWidth: 402)
    #expect(!r4)
    let r5 = gate.update(offsetY: -40, topInset: 116, containerWidth: 402)
    #expect(!r5)
    let r6 = gate.update(offsetY: -116, topInset: 116, containerWidth: 402)
    #expect(r6)
}

/// Before first layout (width 0) nothing is decided or remembered, and a width change
/// (rotation) re-measures the collapsed inset instead of keeping a smaller old one.
@Test func layoutAndWidthChangesResetTheCollapsedInset() {
    var gate = ScrollAwayGate()
    let r7 = gate.update(offsetY: 0, topInset: 0, containerWidth: 0)
    #expect(!r7)
    // Had the unlaid-out 0 inset been kept, −204 would read as scrolled-away −204pt.
    let r8 = gate.update(offsetY: -228, topInset: 228, containerWidth: 402)
    #expect(!r8)
    let r9 = gate.update(offsetY: -204, topInset: 204, containerWidth: 402)
    #expect(!r9)
    // Landscape: a shorter bar.
    let r10 = gate.update(offsetY: 0, topInset: 60, containerWidth: 874)
    #expect(r10)
    // Back to portrait at the top: the old 60pt minimum must not survive.
    let r11 = gate.update(offsetY: -228, topInset: 228, containerWidth: 402)
    #expect(r11)
    #expect(!gate.isScrolled)
    let r12 = gate.update(offsetY: -150, topInset: 150, containerWidth: 402)
    #expect(!r12)
}
