import CoreGraphics
import Testing
@testable import FestivalUI

// MARK: - Drawer open/close choreography (issue #362)

/// Opening dims the whole window before the panel moves; the panel then slides in.
@Test func drawerScrimFadesBeforeThePanelMoves() {
    let distance: CGFloat = 348
    let closed = DrawerMotion(presence: 0, slides: true)
    #expect(closed.scrim == 0)
    #expect(closed.panelOffset(hiddenDistance: distance) == -distance)

    let midFade = DrawerMotion(presence: DrawerMotion.scrimShare / 2, slides: true)
    #expect(midFade.scrim > 0 && midFade.scrim < 1)
    #expect(midFade.panel == 0)
    #expect(midFade.panelOffset(hiddenDistance: distance) == -distance)

    let dimmed = DrawerMotion(presence: DrawerMotion.scrimShare, slides: true)
    #expect(dimmed.scrim == 1)
    #expect(dimmed.panelOffset(hiddenDistance: distance) == -distance)

    let sliding = DrawerMotion(presence: (1 + DrawerMotion.scrimShare) / 2, slides: true)
    #expect(sliding.scrim == 1)
    #expect(sliding.panelOffset(hiddenDistance: distance) < 0)
    #expect(sliding.panelOffset(hiddenDistance: distance) > -distance)

    let open = DrawerMotion(presence: 1, slides: true)
    #expect(open.scrim == 1)
    #expect(open.panelOffset(hiddenDistance: distance) == 0)
    #expect(open.panelOpacity == 1)
}

/// Closing runs the same presence back: the scrim stays fully dark until the panel has
/// left, then fades.
@Test func drawerPanelLeavesBeforeTheScrimFades() {
    let distance: CGFloat = 348
    var presence = 1.0
    var lastOffset: CGFloat = 0
    var panelGoneAt: Double?
    while presence >= 0 {
        let motion = DrawerMotion(presence: presence, slides: true)
        let offset = motion.panelOffset(hiddenDistance: distance)
        #expect(offset <= lastOffset)
        lastOffset = offset
        if offset > -distance {
            #expect(motion.scrim == 1)
        } else if panelGoneAt == nil {
            panelGoneAt = presence
        }
        presence -= 0.01
    }
    #expect(panelGoneAt != nil)
    #expect(DrawerMotion(presence: 0, slides: true).scrim == 0)
}

/// Reduce Motion: the panel never moves; it fades in place after the scrim.
@Test func drawerReduceMotionFadesWithoutSliding() {
    for step in 0...20 {
        let motion = DrawerMotion(presence: Double(step) / 20, slides: false)
        #expect(motion.panelOffset(hiddenDistance: 348) == 0)
        if motion.panelOpacity > 0 { #expect(motion.scrim == 1) }
    }
    #expect(DrawerMotion(presence: 0, slides: false).panelOpacity == 0)
    #expect(DrawerMotion(presence: 1, slides: false).panelOpacity == 1)
}

/// The sequence keeps the web panel duration and stays brief (HIG Motion).
@Test func drawerMotionTimings() {
    #expect(DrawerMotion.panelDuration == 0.25)
    #expect(DrawerMotion.totalDuration <= 0.5)
    #expect(DrawerMotion().presence == 1)
    #expect(DrawerMotion().scrim == 1 && DrawerMotion().panel == 1)
}
