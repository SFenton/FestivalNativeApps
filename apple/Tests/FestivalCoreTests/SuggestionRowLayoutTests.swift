import Testing
@testable import FestivalCore

// MARK: - Web CategoryCard.getRowLayout parity

@Test func rowLayoutFollowsWebCategoryFamilies() {
    let cases: [(String, SuggestionRowLayout)] = [
        ("band_unplayed_Band_Duets", .hidden), ("band_near_fc_x", .unfcAccuracy),
        ("band_star_progress_x", .singleInstrument), ("band_pct_push_x", .percentile),
        ("band_rank_improve_x", .percentile), ("band_stale_x", .season),
        ("song_rival_gap_abc", .rival), ("lb_rival_x", .rival),
        ("variety_pack", .hidden), ("artist_sampler_Queen", .hidden),
        ("artist_unplayed_x", .hidden), ("unplayed_any", .hidden), ("samename_Intro", .hidden),
        ("samename_nearfc_Intro", .singleInstrument), ("unfc_Solo_Guitar", .unfcAccuracy),
        ("stale_global_old", .season), ("almost_elite", .percentile), ("pct_push_Solo_Bass", .percentile),
        ("pct_improve_5", .percentile), ("same_pct_improve", .percentile),
        ("improve_rankings_Solo_Drums", .percentile), ("near_fc_any", .singleInstrument),
        ("almost_six_star", .singleInstrument), ("more_stars", .singleInstrument),
        ("first_plays_mixed", .singleInstrument), ("star_gains", .singleInstrument),
        ("near_max_elite", .singleInstrument), ("something_new", .instrumentChips),
        ("NEAR_FC_RELAXED", .singleInstrument),
    ]
    for (key, layout) in cases {
        #expect(SuggestionRowLayout.forCategory(key) == layout, "\(key)")
    }
}

@Test func starsShowOnlyOnStarProgressCategories() {
    #expect(SuggestionRowLayout.showsStars(categoryKey: "star_gains"))
    #expect(SuggestionRowLayout.showsStars(categoryKey: "star_gains_decade_wrap"))
    #expect(SuggestionRowLayout.showsStars(categoryKey: "band_star_progress_Band_Duets"))
    #expect(!SuggestionRowLayout.showsStars(categoryKey: "near_fc_any"))
    #expect(!SuggestionRowLayout.showsStars(categoryKey: "pct_push"))
}

@Test func compactLayoutsStayOnTheSongLine() {
    #expect(SuggestionRowLayout.singleInstrument.isCompact(showsStars: false))
    #expect(!SuggestionRowLayout.singleInstrument.isCompact(showsStars: true))
    #expect(SuggestionRowLayout.season.isCompact(showsStars: false))
    #expect(SuggestionRowLayout.hidden.isCompact(showsStars: false))
    #expect(!SuggestionRowLayout.percentile.isCompact(showsStars: false))
    #expect(!SuggestionRowLayout.instrumentChips.isCompact(showsStars: false))
}

@Test func categoryInstrumentParsesNativeRawValueKeys() {
    #expect(SuggestionRowLayout.categoryInstrument("unfc_Solo_Guitar") == .lead)
    #expect(SuggestionRowLayout.categoryInstrument("unfc_Solo_Guitar_decade_wrap") == .lead)
    #expect(SuggestionRowLayout.categoryInstrument("pct_improve_Solo_PeripheralBass_5") == .proBass)
    #expect(SuggestionRowLayout.categoryInstrument("stale_Solo_PeripheralCymbals_old") == .proCymbals)
    #expect(SuggestionRowLayout.categoryInstrument("stale_global_old") == nil)
    #expect(SuggestionRowLayout.categoryInstrument("pct_improve_5") == nil)
    #expect(SuggestionRowLayout.categoryInstrument("near_fc_any") == nil)
}

@Test func unfcAccuracyFloorsAndCapsLikeTheWeb() {
    #expect(SuggestionRowLayout.unfcAccuracy(percent: 98.7) == 980_000)
    #expect(SuggestionRowLayout.unfcAccuracy(percent: 100) == 990_000)
    #expect(SuggestionRowLayout.unfcAccuracy(percent: 0) == nil)
    #expect(SuggestionRowLayout.unfcAccuracy(percent: nil) == nil)
}

// MARK: - Rival name badge (issue #29)

@Test func singleRivalCategoriesHideTheRepeatedRivalName() {
    for key in [
        "song_rival_spotlight_abc", "song_rival_gap_abc", "song_rival_protect_abc",
        "song_rival_slipping_abc", "song_rival_dominate_abc", "SONG_RIVAL_SPOTLIGHT_abc",
    ] {
        #expect(!SuggestionRowLayout.showsRivalName(categoryKey: key), "\(key)")
    }
}

@Test func mixedRivalCategoriesKeepTheRivalName() {
    for key in [
        "song_rival_battleground", "song_rival_near_fc", "song_rival_stale",
        "song_rival_star_gains", "song_rival_pct_push", "lb_rival_x", "near_fc_any",
    ] {
        #expect(SuggestionRowLayout.showsRivalName(categoryKey: key), "\(key)")
    }
}

@Test func rivalDeltaAccessibilityLabelNamesTheRivalWhenTheBadgeIsHidden() {
    typealias L = SuggestionRowLayout
    #expect(L.rivalDeltaAccessibilityLabel(delta: 3, rivalName: "TempoTide") == "3 ranks ahead of TempoTide")
    #expect(L.rivalDeltaAccessibilityLabel(delta: -1, rivalName: "TempoTide") == "1 rank behind TempoTide")
    #expect(L.rivalDeltaAccessibilityLabel(delta: 0, rivalName: "TempoTide") == "Tied with TempoTide")
    #expect(L.rivalDeltaAccessibilityLabel(delta: 2, rivalName: nil) == "2 ranks ahead")
    #expect(L.rivalDeltaAccessibilityLabel(delta: -4, rivalName: "") == "4 ranks behind")
    #expect(L.rivalDeltaAccessibilityLabel(delta: 0, rivalName: nil) == "Tied")
}

// MARK: - Stacking

/// Accessibility sizes stack every row with metadata, at any width; otherwise only the
/// wide layouts in compact width do.
@Test func rowsStackMetadataAtAccessibilitySizes() {
    #expect(SuggestionRowLayout.percentile.stacksMetadata(regularWidth: true, accessibilitySize: true, showsStars: false))
    #expect(!SuggestionRowLayout.percentile.stacksMetadata(regularWidth: true, accessibilitySize: false, showsStars: false))
    #expect(SuggestionRowLayout.percentile.stacksMetadata(regularWidth: false, accessibilitySize: false, showsStars: false))
    #expect(!SuggestionRowLayout.season.stacksMetadata(regularWidth: false, accessibilitySize: false, showsStars: false))
    #expect(SuggestionRowLayout.season.stacksMetadata(regularWidth: false, accessibilitySize: true, showsStars: false))
    #expect(!SuggestionRowLayout.hidden.stacksMetadata(regularWidth: false, accessibilitySize: true, showsStars: false))
}
