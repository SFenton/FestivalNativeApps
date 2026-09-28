import Foundation
import Testing
@testable import FestivalCore

/// Build one minimal, decoded-shape song without a live network dependency.
///
/// - Parameters:
///   - title: Catalogue title used as the sort/section key under test.
///   - artist: Catalogue artist used as an alternate section key.
///   - year: Optional catalogue year.
/// - Returns: A validated `Song` for section-index fixtures.
private func fixtureSong(title: String, artist: String = "Artist", year: Int? = nil) throws -> Song {
    let yearField = year.map { ",\"year\":\($0)" } ?? ""
    return try JSONDecoder().decode(Song.self, from: Data("""
    {"songId":"\(title)-\(artist)","title":"\(title)","artist":"\(artist)"\(yearField),
     "difficulty":{"guitar":1}}
    """.utf8))
}

@Test func sectionsGroupConsecutiveTitlesByFirstLetter() throws {
    let songs = try [
        fixtureSong(title: "Alpha"), fixtureSong(title: "Ammonite"),
        fixtureSong(title: "Beta"), fixtureSong(title: "1999"),
    ]
    let sections = SongSectionIndex.sections(songs, mode: .title)
    #expect(sections.map(\.label) == ["A", "B", "#"])
    #expect(sections[0].songs.count == 2)
    #expect(sections[1].songs.map(\.title) == ["Beta"])
}

@Test func sectionsGroupByArtistIndependentlyOfTitle() throws {
    let songs = try [
        fixtureSong(title: "Song One", artist: "Zed"),
        fixtureSong(title: "Song Two", artist: "Zed"),
        fixtureSong(title: "Song Three", artist: "Ada"),
    ]
    let sections = SongSectionIndex.sections(songs, mode: .artist)
    #expect(sections.map(\.label) == ["Z", "A"])
}

@Test func sectionsGroupByExactYearIncludingMissing() throws {
    let songs = try [
        fixtureSong(title: "A", year: 2023), fixtureSong(title: "B", year: 2023),
        fixtureSong(title: "C", year: 2024), fixtureSong(title: "D", year: nil),
    ]
    let sections = SongSectionIndex.sections(songs, mode: .year)
    #expect(sections.map(\.label) == ["2023", "2024", "—"])
}

/// Native Contacts convention: only A–Z leads its own section; punctuation,
/// digits and symbols all share one leading "#" bucket, matching where a raw
/// string sort already puts them (before any letter-led title).
@Test func nonLetterLeadingTitlesShareOneContiguousHashSection() throws {
    let songs = try [
        fixtureSong(title: "(Don't Fear) The Reaper"),
        fixtureSong(title: "2055"),
        fixtureSong(title: "24K Magic"),
        fixtureSong(title: "4 Raws"),
        fixtureSong(title: "500lbs"),
        fixtureSong(title: "Alpha"),
        fixtureSong(title: "Beta"),
    ]
    let sections = SongSectionIndex.sections(songs, mode: .title)
    #expect(sections.map(\.label) == ["#", "A", "B"])
    #expect(sections[0].songs.count == 5)
    // Labels must be unique across the whole index: no repeated or
    // out-of-order letters from titles that used to skip ahead past
    // punctuation/digits to an unrelated "real" letter.
    #expect(Set(sections.map(\.label)).count == sections.count)
}

/// A diacritic folds to its plain Latin letter rather than falling to "#".
@Test func diacriticLeadingTitlesFoldToTheirPlainLetter() throws {
    let songs = try [fixtureSong(title: "Öyster Cult"), fixtureSong(title: "Zed")]
    let sections = SongSectionIndex.sections(songs, mode: .title)
    #expect(sections.map(\.label) == ["O", "Z"])
}

/// Chunking (not the label rule alone) still guards against merging two
/// non-adjacent runs that happen to share a label, e.g. two separate "#"
/// stretches if a locale tie ever splits them apart from each other.
@Test func sectionsNeverMergeNonAdjacentRunsOfTheSameLabel() throws {
    let songs = try [
        fixtureSong(title: "2055"), // "#"
        fixtureSong(title: "Alpha"), // "A"
        fixtureSong(title: "500lbs"), // "#" again, non-adjacent to the first
    ]
    let sections = SongSectionIndex.sections(songs, mode: .title)
    #expect(sections.map(\.label) == ["#", "A", "#"])
    #expect(sections[0].songs.map(\.title) == ["2055"])
    #expect(sections[2].songs.map(\.title) == ["500lbs"])
    // Distinct chunks must have distinct ids even when their labels repeat.
    #expect(Set(sections.map(\.id)).count == sections.count)
}

@Test func sectionsAreEmptyForModesWithoutAMeaningfulKey() throws {
    let songs = try [fixtureSong(title: "A"), fixtureSong(title: "B")]
    #expect(SongSectionIndex.sections(songs, mode: .duration).isEmpty)
    #expect(SongSectionIndex.sections(songs, mode: .shop).isEmpty)
}

@Test func sectionsAreEmptyForZeroOrOneSong() throws {
    #expect(SongSectionIndex.sections([], mode: .title).isEmpty)
    let single = try [fixtureSong(title: "Solo")]
    #expect(SongSectionIndex.sections(single, mode: .title).isEmpty)
}
