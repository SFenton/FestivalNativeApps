import Foundation
import Testing
@testable import FestivalCore

/// Display-service rules use the same expanded accuracy units as the wire.
@Test func scoreFormattingKeepsNecessaryAccuracyPrecision() {
    #expect(ScoreFormatting.accuracy(980_000) == "98")
    #expect(ScoreFormatting.accuracy(985_000) == "98.5")
    #expect(ScoreFormatting.accuracy(1_000_000) == "100")
    #expect(ScoreFormatting.leeway(1) == "+1.0%")
    #expect(ScoreFormatting.leeway(0) == "0.0%")
    #expect(ScoreFormatting.leeway(-0.5) == "-0.5%")
}

/// Each API failure reaches a retry screen without exposing an enum identifier.
@Test func serviceFailuresHaveReadableExplanations() {
    let cases: [(FestivalAPIError, String)] = [
        (.insecureBaseURL, "A secure service connection is required."),
        (.invalidPublication, "The current scores could not be verified. Try again."),
        (.invalidResponse, "The service returned data we could not read. Try again."),
        (.invalidResource, "That song or chart is unavailable."),
        (.invalidCatalogue, "The service returned data we could not read. Try again."),
        (.invalidLeaderboard, "The service returned data we could not read. Try again."),
        (.invalidArtwork, "Album artwork could not be displayed."),
        (.httpStatus(404), "That song or chart is no longer available."),
        (.httpStatus(429), "Too many requests. Try again shortly."),
        (.httpStatus(503), "The service is temporarily unavailable. Try again."),
        (.httpStatus(418), "The service could not load this content (HTTP 418)."),
        (.unexpectedNotModified, "The service returned an incomplete update. Try again."),
        (.unavailable(retryAfter: "30"),
         "The service is temporarily unavailable. Try again in 30 seconds."),
        (.unavailable(retryAfter: "invalid"),
         "The service is temporarily unavailable. Try again."),
    ]
    for (error, expected) in cases {
        #expect(error.localizedDescription == expected)
    }
}
