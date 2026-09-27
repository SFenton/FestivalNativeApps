import Foundation
import Testing
@testable import FestivalCore

private let sample = Data("""
{"count":2,"currentSeason":9,"songs":[
 {"songId":"fixture-pulse","title":"Fixture Pulse","artist":"Test Ensemble",
  "difficulty":{"guitar":0,"bass":2,"drums":99,"vocals":-1,
  "proGuitar":3,"proBass":4,"proVocals":5,"proCymbals":6,"proDrums":1}},
 {"songId":"fixture-orbit","title":"Fixture Orbit","artist":"Test Ensemble"}
]}
""".utf8)

/// Every service instrument ID selects the corresponding song difficulty key.
@Test(arguments: Instrument.allCases)
func chartedInstrumentsMatchWireFields(_ instrument: Instrument) throws {
    let catalog = try JSONDecoder().decode(SongsResponse.self, from: sample)
    try catalog.validate()
    let first = try #require(catalog.songs.first)
    #expect(first.id == "fixture-pulse")
    #expect(instrument.label != "")
    #expect(first.supports(instrument) == ![.drums, .vocals].contains(instrument))
    #expect(catalog.songs[1].supports(instrument) == false)
}

/// Malformed counts and unnamed rows cannot be mistaken for loaded content.
@Test func catalogRejectsInvalidEnvelope() throws {
    let wrongCount = try JSONDecoder().decode(
        SongsResponse.self,
        from: Data(#"{"count":1,"songs":[]}"#.utf8)
    )
    #expect(throws: FestivalAPIError.invalidCatalogue) {
        try wrongCount.validate()
    }
    let missingID = try JSONDecoder().decode(
        SongsResponse.self,
        from: Data(#"{"count":1,"songs":[{"songId":"","title":"Untitled","artist":"Fixture"}]}"#.utf8)
    )
    #expect(throws: FestivalAPIError.invalidCatalogue) {
        try missingID.validate()
    }
}

/// Mirror the PWA's positive-duration labels without inventing missing metadata.
@Test func songDurationMatchesSourceFormatting() throws {
    let cases: [(Int?, String?)] = [
        (nil, nil), (0, nil), (-1, nil),
        (5, "0:05"), (59, "0:59"), (60, "1:00"),
        (366, "6:06"), (3_600, "1:00:00"), (3_661, "1:01:01"),
        (86_400, "24:00:00"),
    ]
    for (seconds, expected) in cases {
        var record: [String: Any] = [
            "songId": "fixture-duration", "title": "Fixture", "artist": "Test",
        ]
        if let seconds {
            record["durationSeconds"] = seconds
        }
        let song = try JSONDecoder().decode(
            Song.self, from: JSONSerialization.data(withJSONObject: record)
        )
        #expect(song.formattedDuration == expected)
    }
}
