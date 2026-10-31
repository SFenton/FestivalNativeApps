import Testing
@testable import FestivalUI

// MARK: - Logic shared by the SwiftUI and UIKit background hosts

/// Dimming follows either the in-app or the system contrast setting.
@Test func backdropDimmingRaisesWithIncreasedContrast() {
    #expect(BackdropPresentation.dimming(appMoreContrast: false, systemIncreased: false) == 0.7)
    #expect(BackdropPresentation.dimming(appMoreContrast: true, systemIncreased: false) == 0.82)
    #expect(BackdropPresentation.dimming(appMoreContrast: false, systemIncreased: true) == 0.82)
}

/// Art is drawn only when nothing asks for an opaque or data-saving presentation.
@Test func backdropShowsArtOnlyWithoutOpaqueOrDataSaving() {
    #expect(BackdropPresentation.showsArt(
        appLessTransparency: false, systemReduceTransparency: false, constrained: false))
    #expect(!BackdropPresentation.showsArt(
        appLessTransparency: true, systemReduceTransparency: false, constrained: false))
    #expect(!BackdropPresentation.showsArt(
        appLessTransparency: false, systemReduceTransparency: true, constrained: false))
    #expect(!BackdropPresentation.showsArt(
        appLessTransparency: false, systemReduceTransparency: false, constrained: true))
}

/// The shared policy factory maps each input onto the same decision the hosts rely on.
@Test func resolvedPolicyHonorsEveryPreference() {
    func policy(
        scene: Bool = true, visible: Bool = true, known: Bool = true, satisfied: Bool = true,
        reduceMotion: Bool = false, disable: Bool = false, reduceTransparency: Bool = false,
        saveData: Bool = false, lowPower: Bool = false, count: Int = 2
    ) -> ArtworkPlaybackPolicy {
        .resolve(
            sceneActive: scene, visible: visible, pathKnown: known, pathSatisfied: satisfied,
            reduceMotion: reduceMotion, disableAnimation: disable,
            reduceTransparency: reduceTransparency, saveData: saveData, lowPower: lowPower,
            artCount: count
        )
    }
    let base = policy()
    #expect(base.mayLoad)
    // The debug still background is part of "disableAnimation", so only assert the
    // preference-driven direction that holds in every build.
    #expect(!policy(scene: false).mayLoad)
    #expect(!policy(visible: false).mayLoad)
    #expect(!policy(known: false).mayLoad)
    #expect(!policy(satisfied: false).mayLoad)
    #expect(!policy(reduceTransparency: true).mayLoad)
    #expect(!policy(saveData: true).mayLoad)
    #expect(!policy(count: 0).mayLoad)
    #expect(policy(reduceMotion: true).mayLoad && !policy(reduceMotion: true).mayAnimate)
    #expect(policy(disable: true).mayLoad && !policy(disable: true).mayAnimate)
    #expect(policy(lowPower: true).mayLoad && !policy(lowPower: true).mayAnimate)
    #expect(!policy(count: 1).mayAnimate)
}

/// A shown cover is kept only for the same song and only when it can no longer improve.
@Test func presentingASongKeepsAnEquivalentCover() {
    typealias Coordinator = FestivalBackgroundCoordinator
    #expect(!Coordinator.keepsCover(current: nil, raw: "a", opaque: false))
    #expect(!Coordinator.keepsCover(current: ("b", true), raw: "a", opaque: false))
    #expect(Coordinator.keepsCover(current: ("a", true), raw: "a", opaque: false))
    // The cover failed to decode: retry unless art cannot be shown anyway.
    #expect(!Coordinator.keepsCover(current: ("a", false), raw: "a", opaque: false))
    #expect(Coordinator.keepsCover(current: ("a", false), raw: "a", opaque: true))
    // A song without art is its brand-surface cover.
    #expect(Coordinator.keepsCover(current: ("", false), raw: "", opaque: false))
}
