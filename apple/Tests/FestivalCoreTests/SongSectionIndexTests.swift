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
    #expect(sections.map(\.id) == ["A", "B", "#"])
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
    #expect(sections.map(\.id) == ["Z", "A"])
}

@Test func sectionsGroupByExactYearIncludingMissing() throws {
    let songs = try [
        fixtureSong(title: "A", year: 2023), fixtureSong(title: "B", year: 2023),
        fixtureSong(title: "C", year: 2024), fixtureSong(title: "D", year: nil),
    ]
    let sections = SongSectionIndex.sections(songs, mode: .year)
    #expect(sections.map(\.id) == ["2023", "2024", "—"])
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
