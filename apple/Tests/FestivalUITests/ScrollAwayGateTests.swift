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
/// "scrolled" until it moves past the collapsed bar: where the first section title
/// leaves its pin line (issue #631), within the title-pass tolerance.
@Test func gateWaitsForTheCollapsedTitleThenFlipsAtThePinLine() {
    var gate = ScrollAwayGate()
    let result = decisions(
        [(-228, 228), (-200, 200), (-140, 140), (-116, 116), (-115.5, 116), (-115, 116),
         (-114.5, 116)],
        gate: &gate
    )
    #expect(result == [false, false, false, false, false, false, true])
}

/// Issue #631: the pinned section title took over 24 pt past the collapsed top, after
/// the in-list title had slid that far under the navigation bar, and handed back 8 pt
/// above the line. Both hand-offs now sit within a point of the pin line, so a slow drag
/// shows the title stop at the line instead of rising and jumping back.
@Test func handOffsSitWithinAPointOfThePinLine() {
    #expect(ScrollAwayGate.enterDistance <= SongsScrollChrome.headerTolerance)
    #expect(ScrollAwayGate.exitDistance > 0)
    #expect(ScrollAwayGate.exitDistance < ScrollAwayGate.enterDistance)
    var gate = ScrollAwayGate()
    // Slow drag down from the top in 2 pt steps: scrolled from the first step past 1 pt.
    let down = decisions(
        [(-228, 228), (-172, 172), (-116, 116), (-114, 116), (-112, 116)], gate: &gate
    )
    #expect(down == [false, false, false, true, true])
    // And back: still scrolled at 0.5 pt, back at the top below it and while the title
    // expands again.
    let up = decisions([(-115, 116), (-115.5, 116), (-116, 116), (-150, 150)], gate: &gate)
    #expect(up == [true, true, false, false])
}

/// A list with no collapsing title (macOS, a landscape bar) rests at distance 0, which
/// always counts as the top, so returning there forgets passed titles (#297).
@Test func aListAtItsOwnTopIsNeverScrolled() {
    var gate = ScrollAwayGate()
    let result = decisions([(-60, 60), (-50, 60), (-59.4, 60), (-60, 60)], gate: &gate)
    #expect(result == [false, true, true, false])
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

/// The recorded freeze: the inset alternating 232/116 at a fixed offset. Measured
/// from the collapsed inset the decision holds whatever the chrome does: −116.5 is
/// −0.5 pt (not scrolled), −95.67 is 20.3 pt (scrolled).
@Test func recordedFreezeGeometryIsStable() {
    var gate = ScrollAwayGate()
    _ = decisions([(-228, 228), (-116, 116), (-116.5, 116)], gate: &gate)
    #expect(!gate.isScrolled)
    _ = decisions([(-116.5, 232), (-116.5, 116), (-116.5, 232)], gate: &gate)
    #expect(!gate.isScrolled)
    _ = decisions([(-95.67, 116)], gate: &gate)
    #expect(gate.isScrolled)
    _ = decisions([(-95.67, 232), (-95.67, 116), (-95.67, 232)], gate: &gate)
    #expect(gate.isScrolled)
    // A transient expanded inset at a *moving* offset still measures from the collapsed bar.
    _ = decisions([(-90, 232), (-80, 232)], gate: &gate)
    #expect(gate.isScrolled)
    _ = decisions([(-116, 116), (-119, 232), (-125, 232)], gate: &gate)
    #expect(!gate.isScrolled)
}

/// Hysteresis: once scrolled, the list stays scrolled until it is within the exit
/// distance of the top, so jitter around the enter distance cannot flicker the chrome.
@Test func hysteresisKeepsTheDecisionNearTheThreshold() {
    var gate = ScrollAwayGate()
    let result = decisions(
        [(-116, 116), (-80, 116), (-114, 116), (-115, 116), (-115.4, 116), (-116, 116),
         (-115.4, 116), (-115, 116), (-114.9, 116)],
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
