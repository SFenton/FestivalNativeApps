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

/// Only a scrolled floating dock (iOS 17–26.0 iPhone) hands its tools to the bar; every
/// viewer gets it (the old profile-only gate left anonymous Sort and Quick Links
/// floating). The iOS 26.1+ tab-bar accessory keeps them at the bottom (issue #42).
@Test(arguments: [
    (false, nil, false),
    (true, nil, false),
    (false, PageToolsPresentation.floating, false),
    (true, .floating, true),
    (false, .accessory, false),
    (true, .accessory, false),
] as [(Bool, PageToolsPresentation?, Bool)])
func toolsMoveIntoTheBarOnlyWhenAFloatingDockScrolls(
    scrolled: Bool, presentation: PageToolsPresentation?, expected: Bool
) {
    #expect(PageToolsHandOff.toolsInBar(scrolled: scrolled, presentation: presentation) == expected)
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
