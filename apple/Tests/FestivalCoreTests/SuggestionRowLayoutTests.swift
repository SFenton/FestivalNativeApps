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
