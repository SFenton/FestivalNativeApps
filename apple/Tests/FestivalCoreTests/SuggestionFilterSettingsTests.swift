import Foundation
import Testing
@testable import FestivalCore

// MARK: - Defaults and persistence

@Test func defaultFilterSettingsAreInactiveAndEnableEverything() {
    let defaults = SuggestionFilterSettings.defaults()
    #expect(!defaults.isActive())
    for instrument in Instrument.allCases {
        #expect(defaults.isInstrumentEnabled(instrument))
    }
    for type in SuggestionCategoryType.allCases {
        #expect(defaults.isGlobalEnabled(type))
        for instrument in Instrument.allCases {
            #expect(defaults.isTypeEnabled(type, instrument: instrument))
        }
        #expect(defaults.isTypeEnabled(type, instrument: nil))
    }
}

@Test func encodedDefaultsProduceEmptyDataAndRoundTrip() throws {
    let defaults = SuggestionFilterSettings.defaults()
    #expect(try defaults.encoded().isEmpty)

    var edited = defaults
    edited.setInstrumentEnabled(.karaoke, enabled: false)
    let data = try edited.encoded()
    #expect(!data.isEmpty)
    #expect(SuggestionFilterSettings.decodeSaved(data) == edited)
}

@Test func decodeSavedFallsBackToDefaultsForCorruptOrOversizeData() {
    #expect(SuggestionFilterSettings.decodeSaved(Data()) == .defaults())
    #expect(SuggestionFilterSettings.decodeSaved(Data("not json".utf8)) == .defaults())
    let oversize = Data(repeating: 0x41, count: 20_000)
    #expect(SuggestionFilterSettings.decodeSaved(oversize) == .defaults())
}

// MARK: - Instrument toggle

@Test func instrumentToggleGatesEffectiveInstrumentsIndependentlyOfAppSettings() {
    var filter = SuggestionFilterSettings.defaults()
    filter.setInstrumentEnabled(.karaoke, enabled: false)
    #expect(!filter.isInstrumentEnabled(.karaoke))
    #expect(filter.isActive())

    let appVisible = Set(Instrument.allCases)
    let effective = filter.effectiveInstruments(appVisible: appVisible)
    #expect(!effective.contains(.karaoke))
    #expect(effective.count == appVisible.count - 1)

    // Settings hiding a chart the filter never touched still removes it.
    let bothHidden = filter.effectiveInstruments(appVisible: appVisible.subtracting([.proDrums]))
    #expect(!bothHidden.contains(.karaoke))
    #expect(!bothHidden.contains(.proDrums))
}

// MARK: - Type toggles

@Test func globalToggleCascadesToEveryInstrumentRow() {
    var filter = SuggestionFilterSettings.defaults()
    filter.setGlobalType(.nearFC, enabled: false)
    #expect(!filter.isGlobalEnabled(.nearFC))
    for instrument in Instrument.allCases {
        #expect(!filter.isTypeEnabled(.nearFC, instrument: instrument))
    }
    #expect(!filter.isTypeEnabled(.nearFC, instrument: nil))
    #expect(filter.isActive())

    filter.setGlobalType(.nearFC, enabled: true)
    #expect(filter.isGlobalEnabled(.nearFC))
    for instrument in Instrument.allCases {
        #expect(filter.isTypeEnabled(.nearFC, instrument: instrument))
    }
    #expect(!filter.isActive())
}

@Test func perInstrumentToggleReenablesGlobalWhenTurnedOn() {
    var filter = SuggestionFilterSettings.defaults()
    filter.setGlobalType(.stale, enabled: false, instruments: [.lead, .bass])
    #expect(!filter.isGlobalEnabled(.stale))

    filter.setPerInstrumentType(.stale, instrument: .lead, enabled: true, allInstruments: [.lead, .bass])
    #expect(filter.isGlobalEnabled(.stale))
    #expect(filter.isTypeEnabled(.stale, instrument: .lead))
    #expect(!filter.isTypeEnabled(.stale, instrument: .bass))
}

@Test func perInstrumentToggleTurnsGlobalOffOnlyWhenEveryRowIsOff() {
    var filter = SuggestionFilterSettings.defaults()
    filter.setPerInstrumentType(.almostElite, instrument: .lead, enabled: false, allInstruments: [.lead, .bass])
    #expect(filter.isGlobalEnabled(.almostElite), "one row off should not clear the global switch")

    filter.setPerInstrumentType(.almostElite, instrument: .bass, enabled: false, allInstruments: [.lead, .bass])
    #expect(!filter.isGlobalEnabled(.almostElite), "every visible row off should clear the global switch")
}

@Test func resetClearsEveryOverride() {
    var filter = SuggestionFilterSettings.defaults()
    filter.setInstrumentEnabled(.karaoke, enabled: false)
    filter.setGlobalType(.unplayed, enabled: false)
    #expect(filter.isActive())
    filter.reset()
    #expect(!filter.isActive())
    #expect(filter == .defaults())
}

// MARK: - Category filtering

private func song(_ id: String) throws -> Song {
    let record: [String: Any] = ["songId": id, "title": id, "artist": id]
    return try JSONDecoder().decode(Song.self, from: JSONSerialization.data(withJSONObject: record))
}

@Test func categoryFilterDropsASingleInstrumentCategoryWhenItsChartIsHidden() throws {
    let category = SuggestionCategory(
        key: "unfc_Solo_Guitar", title: "Finish the Lead FCs", description: "", type: .nearFC,
        instrument: .lead, songs: [SuggestionSongItem(song: try song("a"))]
    )
    let visible = SuggestionCategoryFilter.visible(
        category, effectiveInstruments: [.bass, .drums], filter: .defaults()
    )
    #expect(visible == nil)

    let kept = SuggestionCategoryFilter.visible(
        category, effectiveInstruments: [.lead, .bass], filter: .defaults()
    )
    #expect(kept == category)
}

@Test func categoryFilterDropsASingleInstrumentCategoryWhenItsTypeIsDisabled() throws {
    let category = SuggestionCategory(
        key: "unfc_Solo_Guitar", title: "Finish the Lead FCs", description: "", type: .nearFC,
        instrument: .lead, songs: [SuggestionSongItem(song: try song("a"))]
    )
    var filter = SuggestionFilterSettings.defaults()
    filter.setGlobalType(.nearFC, enabled: false)
    #expect(SuggestionCategoryFilter.visible(category, effectiveInstruments: [.lead], filter: filter) == nil)
}

@Test func categoryFilterTrimsAMultiInstrumentCategoryToVisibleCharts() throws {
    let leadItem = SuggestionSongItem(song: try song("a"), instrument: .lead)
    let bassItem = SuggestionSongItem(song: try song("b"), instrument: .bass)
    let category = SuggestionCategory(
        key: "near_fc_any", title: "FC These Next!", description: "", type: .nearFC,
        instrument: nil, songs: [leadItem, bassItem]
    )
    let trimmed = try #require(SuggestionCategoryFilter.visible(
        category, effectiveInstruments: [.lead], filter: .defaults()
    ))
    #expect(trimmed.songs == [leadItem])
    #expect(trimmed.key == category.key)

    #expect(SuggestionCategoryFilter.visible(
        category, effectiveInstruments: [.drums], filter: .defaults()
    ) == nil)

    let untouched = try #require(SuggestionCategoryFilter.visible(
        category, effectiveInstruments: [.lead, .bass], filter: .defaults()
    ))
    #expect(untouched == category)
}

@Test func categoryFilterTrimsAMultiInstrumentCategoryByPerInstrumentType() throws {
    let leadItem = SuggestionSongItem(song: try song("a"), instrument: .lead)
    let bassItem = SuggestionSongItem(song: try song("b"), instrument: .bass)
    let category = SuggestionCategory(
        key: "near_fc_any", title: "FC These Next!", description: "", type: .nearFC,
        instrument: nil, songs: [leadItem, bassItem]
    )
    var filter = SuggestionFilterSettings.defaults()
    filter.setPerInstrumentType(.nearFC, instrument: .bass, enabled: false)
    let trimmed = try #require(SuggestionCategoryFilter.visible(
        category, effectiveInstruments: [.lead, .bass], filter: filter
    ))
    #expect(trimmed.songs == [leadItem])
}

@Test func categoryFilterKeepsAnInstrumentAgnosticSongItem() throws {
    let item = SuggestionSongItem(song: try song("a"))
    let category = SuggestionCategory(
        key: "variety_pack", title: "Variety Pack", description: "", type: .varietyPack,
        instrument: nil, songs: [item]
    )
    let kept = try #require(SuggestionCategoryFilter.visible(
        category, effectiveInstruments: [], filter: .defaults()
    ))
    #expect(kept == category)
}

// MARK: - Category type metadata

@Test func songItemIdentityCombinesSongAndInstrumentWhenPresent() throws {
    let base = try song("a")
    #expect(SuggestionSongItem(song: base).id == "a")
    #expect(SuggestionSongItem(song: base, instrument: .bass).id == "a|Solo_Bass")
}

@Test func categoryIdentityIsItsKey() throws {
    let category = SuggestionCategory(
        key: "near_fc_any", title: "FC These Next!", description: "", type: .nearFC,
        instrument: nil, songs: [SuggestionSongItem(song: try song("a"))]
    )
    #expect(category.id == "near_fc_any")
}

@Test func everyCategoryTypeHasNonEmptyLabelsAndDescriptions() {
    for type in SuggestionCategoryType.allCases {
        #expect(!type.label.isEmpty)
        #expect(!type.filterDescription.isEmpty)
        #expect(type.id == type.rawValue)
    }
}
