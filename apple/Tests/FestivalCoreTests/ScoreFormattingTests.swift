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

/// Song rows use source buckets rather than displaying impossible "Top 0.0%".
@Test func scorePercentileUsesSourceSongBuckets() {
    #expect(ScoreFormatting.percentileBucket(rank: 1, totalEntries: 1_000_000)
            == "Top 1%")
    #expect(ScoreFormatting.percentileBucket(rank: 1, totalEntries: 26)
            == "Top 4%")
    #expect(ScoreFormatting.percentileBucket(rank: 2, totalEntries: 26)
            == "Top 10%")
    #expect(ScoreFormatting.percentileBucket(rank: 26, totalEntries: 26)
            == "Top 100%")
    #expect(ScoreFormatting.percentileBucket(rank: 27, totalEntries: 26)
            == "Top 100%")
    #expect(ScoreFormatting.percentileBucket(rank: 0, totalEntries: 26) == nil)
    #expect(ScoreFormatting.percentileBucket(rank: 1, totalEntries: 0) == nil)
}

/// Non-FC accuracy follows the source's bounded, translucent red-to-green ramp.
@Test func scoreAccuracyTintMatchesSourceGradientWithoutInferringFullCombo() throws {
    #expect(try ScoreFormatting.accuracyTint(0)
            == ScoreAccuracyTint(red: 220, green: 40, blue: 40))
    #expect(try ScoreFormatting.accuracyTint(500_000)
            == ScoreAccuracyTint(red: 133, green: 122, blue: 77))
    #expect(try ScoreFormatting.accuracyTint(980_000)
            == ScoreAccuracyTint(red: 49, green: 201, blue: 112))
    #expect(try ScoreFormatting.accuracyTint(1_000_000)
            == ScoreAccuracyTint(red: 46, green: 204, blue: 113))
    #expect(try ScoreFormatting.accuracyTint(-10)
            == ScoreAccuracyTint(red: 220, green: 40, blue: 40))
    #expect(try ScoreFormatting.accuracyTint(1_500_000)
            == ScoreAccuracyTint(red: 46, green: 204, blue: 113))
    #expect(throws: FestivalAPIError.invalidLeaderboard) {
        try ScoreFormatting.accuracyTint(.infinity)
    }
    #expect(throws: FestivalAPIError.invalidLeaderboard) {
        try ScoreFormatting.accuracyTint(.nan)
    }
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
        (.invalidShop, "The Item Shop data could not be read. Try again."),
        (.invalidPathData, "The path data could not be read. Try another chart or difficulty."),
        (.invalidPathImage, "The path image could not be displayed. Try another chart or difficulty."),
        (.invalidProfileSearchQuery, "Enter 2 to 200 characters to search players."),
        (.invalidProfileSearchLimit, "Player search can request up to ten results."),
        (.invalidProfileSearch, "Player search returned unreadable data. Try again."),
        (.invalidPlayerProfile, "The selected player's scores could not be read. Try again."),
        (.invalidSelectedProfile, "The saved profile could not be read. Choose a profile again."),
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
