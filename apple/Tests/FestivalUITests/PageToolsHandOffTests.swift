import Testing
@testable import FestivalUI

// MARK: - PageToolsHandOff (issue #13)

/// Either Reduce Motion source turns the hand-off into a cross-fade.
@Test(arguments: [
    (false, false, PageToolsHandOff.Style.motion),
    (true, false, .crossFade),
    (false, true, .crossFade),
    (true, true, .crossFade),
])
func handOffStyleFollowsEitherReduceMotionSetting(
    system: Bool, app: Bool, expected: PageToolsHandOff.Style
) {
    #expect(PageToolsHandOff.style(systemReduceMotion: system, appReduceMotion: app) == expected)
}

/// Only a scrolled iPhone dock hands its tools to the bar; every viewer gets it (the
/// old profile-only gate left anonymous Sort and Quick Links floating).
@Test(arguments: [
    (false, false, false),
    (true, false, false),
    (false, true, false),
    (true, true, true),
])
func toolsMoveIntoTheBarOnlyWhenADockedPageScrolls(
    scrolled: Bool, actionsInDock: Bool, expected: Bool
) {
    #expect(PageToolsHandOff.toolsInBar(scrolled: scrolled, actionsInDock: actionsInDock) == expected)
}

/// Both styles produce an animation and a dock transition (smoke: the values are opaque).
@Test(arguments: [PageToolsHandOff.Style.motion, .crossFade])
func everyStyleHasAnAnimationAndADockTransition(style: PageToolsHandOff.Style) {
    _ = PageToolsHandOff.animation(style)
    _ = PageToolsHandOff.dockTransition(style)
}

/// The cross-fade is shorter than the motion hand-off and never springs.
@Test func crossFadeUsesItsOwnTiming() {
    #expect(PageToolsHandOff.animation(.crossFade) != PageToolsHandOff.animation(.motion))
}
