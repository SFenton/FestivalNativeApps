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
