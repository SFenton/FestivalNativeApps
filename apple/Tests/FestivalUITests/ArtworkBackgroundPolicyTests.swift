import Testing
@testable import FestivalUI

/// A reported offline path does not become usable just because it is known.
@Test func decorativeNetworkRequiresSatisfiedPath() {
    #expect(!ArtworkNetworkStatus.canFetch(known: false, satisfied: false))
    #expect(!ArtworkNetworkStatus.canFetch(known: false, satisfied: true))
    #expect(!ArtworkNetworkStatus.canFetch(known: true, satisfied: false))
    #expect(ArtworkNetworkStatus.canFetch(known: true, satisfied: true))
}

/// All artwork policy states must affect actual loading and timer decisions.
@Test func artworkPolicyHonorsSystemAndAppOverrides() {
    let active = ArtworkPlaybackPolicy(
        activeScene: true, visiblePage: true, reduceMotion: false,
        disableAnimation: false, reduceTransparency: false,
        saveData: false, lowPower: false, artCount: 2
    )
    #expect(active.mayLoad && active.mayAnimate)

    let cases: [(ArtworkPlaybackPolicy, Bool)] = [
        (.init(activeScene: false, visiblePage: true, reduceMotion: false,
               disableAnimation: false, reduceTransparency: false,
               saveData: false, lowPower: false, artCount: 2), false),
        (.init(activeScene: true, visiblePage: false, reduceMotion: false,
               disableAnimation: false, reduceTransparency: false,
               saveData: false, lowPower: false, artCount: 2), false),
        (.init(activeScene: true, visiblePage: true, reduceMotion: false,
               disableAnimation: false, reduceTransparency: true,
               saveData: false, lowPower: false, artCount: 2), false),
        (.init(activeScene: true, visiblePage: true, reduceMotion: false,
               disableAnimation: false, reduceTransparency: false,
               saveData: true, lowPower: false, artCount: 2), false),
        (.init(activeScene: true, visiblePage: true, reduceMotion: false,
               disableAnimation: false, reduceTransparency: false,
               saveData: false, lowPower: false, artCount: 0), false),
        (.init(activeScene: true, visiblePage: true, reduceMotion: true,
               disableAnimation: false, reduceTransparency: false,
               saveData: false, lowPower: false, artCount: 2), true),
        (.init(activeScene: true, visiblePage: true, reduceMotion: false,
               disableAnimation: true, reduceTransparency: false,
               saveData: false, lowPower: false, artCount: 2), true),
        (.init(activeScene: true, visiblePage: true, reduceMotion: false,
               disableAnimation: false, reduceTransparency: false,
               saveData: false, lowPower: true, artCount: 2), true),
        (.init(activeScene: true, visiblePage: true, reduceMotion: false,
               disableAnimation: false, reduceTransparency: false,
               saveData: false, lowPower: false, artCount: 1), true),
    ]
    for (policy, shouldLoad) in cases {
        #expect(policy.mayLoad == shouldLoad)
        #expect(!policy.mayAnimate)
    }
}
