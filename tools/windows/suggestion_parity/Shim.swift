import Foundation

// Minimal stand-ins for the FestivalCore types the copied Apple suggestion sources reference
// but this harness does not compile (PlayerProfile.swift / FestivalAPI pull in the network stack).

/// Error type referenced by the copied `ScoreFormatting.accuracyTint`.
public enum FestivalAPIError: Error { case invalidLeaderboard }

/// The fields `SuggestionGenerator` reads from the Apple `PlayerScore` (expanded accuracy).
public struct PlayerScore: Decodable, Equatable, Sendable {
    public let songId: String
    public let instrument: Instrument
    public let score: Int
    public let accuracy: Double?
    public let isFullCombo: Bool?
    public let stars: Int?
    public let season: Int?
    public let rank: Int?
    public let totalEntries: Int?

    private enum CodingKeys: String, CodingKey {
        case songId, instrument, score, accuracy, isFullCombo = "fullCombo", stars, season, rank, totalEntries
    }
}
