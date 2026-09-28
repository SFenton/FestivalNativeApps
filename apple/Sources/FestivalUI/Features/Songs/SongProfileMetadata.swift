import Foundation
import FestivalCore
import FestivalDesign

/// Source-order field identity, independent of chart name and native view geometry.
enum SongMetadataKind: String, CaseIterable, Sendable {
    case score
    case accuracy
    case percentile
    case stars
    case season
    case intensity
    case difficulty
    case lastPlayed
}

/// Source percentile bands, not raw cross-profile rank metadata.
enum SongPercentileTier: Sendable, Equatable {
    case topOne
    case topFive
    case ordinary
}

/// Only validated, independently switchable Songs card content reaches SwiftUI.
enum SongMetadataField: Sendable, Equatable, Identifiable {
    case score(Int)
    case accuracy(Double?, fullCombo: Bool, percentageVisible: Bool, tint: ScoreAccuracyTint?)
    case percentile(String, tier: SongPercentileTier)
    case stars(count: Int, gold: Bool)
    case season(Int, current: Bool)
    case intensity(Double)
    case difficulty(Int)
    case lastPlayed(String)

    var id: SongMetadataKind {
        switch self {
        case .score: .score
        case .accuracy: .accuracy
        case .percentile: .percentile
        case .stars: .stars
        case .season: .season
        case .intensity: .intensity
        case .difficulty: .difficulty
        case .lastPlayed: .lastPlayed
        }
    }

    /// Preserve full spoken meaning while visual pills remain compact.
    ///
    /// - Returns: A chart field's value without depending on fill color or badge shape.
    var announcement: String {
        switch self {
        case let .score(value):
            "Score \(value.formatted())"
        case let .accuracy(value, fullCombo, percentageVisible, tint):
            if !fullCombo && value != nil && tint == nil {
                "Accuracy display unavailable"
            } else if fullCombo {
                if percentageVisible, let value {
                    "Full combo, accuracy \(ScoreFormatting.accuracy(value)) percent"
                } else if percentageVisible {
                    "Full combo, accuracy unavailable"
                } else {
                    "Full combo"
                }
            } else if let value {
                "Accuracy \(ScoreFormatting.accuracy(value)) percent"
            } else {
                "Accuracy unavailable"
            }
        case let .percentile(bucket, _):
            bucket
        case let .stars(count, gold):
            gold ? "\(count) gold stars" : "\(count) stars"
        case let .season(number, current):
            current ? "Current season \(number)" : "Season \(number)"
        case let .intensity(raw):
            "Song intensity \(Int(DifficultyMeter.displayLevel(level: raw, raw: true))) of 7"
        case let .difficulty(number):
            if SongProfileCardPolicy.difficultyNames.indices.contains(number) {
                "\(SongProfileCardPolicy.difficultyNames[number]) difficulty"
            } else {
                "Invalid game difficulty \(number)"
            }
        case let .lastPlayed(value):
            value
        }
    }

    /// Retain a plain-text fallback for previously hosted score-state views.
    ///
    /// - Returns: One readable label derived from the same typed field projection.
    var plainLabel: String {
        switch self {
        case let .score(value):
            "Score \(value.formatted())"
        case let .accuracy(value, fullCombo, percentageVisible, _):
            if percentageVisible, let value {
                "Accuracy \(ScoreFormatting.accuracy(value))%"
            } else if fullCombo {
                "Full combo"
            } else {
                "Accuracy unavailable"
            }
        case let .percentile(bucket, _):
            bucket
        case let .stars(count, gold):
            gold ? "\(count) gold stars" : "\(count) stars"
        case let .season(number, _):
            "Season \(number)"
        case .intensity:
            announcement
        case let .difficulty(number):
            if SongProfileCardPolicy.difficultyNames.indices.contains(number) {
                SongProfileCardPolicy.difficultyNames[number]
            } else {
                "Invalid game difficulty \(number)"
            }
        case let .lastPlayed(value):
            value
        }
    }
}

/// Form a source-ordered row without fabricating score, accuracy or profile provenance.
enum SongProfileCardPolicy {
    static let difficultyNames = ["Easy", "Medium", "Hard", "Expert"]

    /// Project one positive, publication-validated score and current catalogue chart.
    ///
    /// - Parameters:
    ///   - score: Current validated compact score, never another selected account's row.
    ///   - chart: First enabled or explicitly filtered solo chart.
    ///   - song: Typed catalogue song for chart Intensity; nil only in legacy hosted fallbacks.
    ///   - currentSeason: Optional, independently validated catalogue season.
    ///   - visibility: Saved switches; an independent FC cue survives hiding Percentage.
    /// - Returns: Source-default field order, with unsupported values omitted explicitly.
    /// - Throws: Invalid reported accuracy tint, never replaced with a plausible pill.
    static func fields(
        for score: PlayerScore, chart: Instrument,
        song: Song?, currentSeason: Int?,
        visibility: SongMetadataVisibility
    ) throws -> [SongMetadataField] {
        guard score.score > 0 else { return [] }
        var fields: [SongMetadataField] = []
        if visibility.score {
            fields.append(.score(score.score))
        }
        let combo = score.isFullCombo == true
        if visibility.percentage || combo {
            let accuracy = visibility.percentage ? score.accuracy : nil
            if let accuracy {
                let tint = combo ? nil : try ScoreFormatting.accuracyTint(accuracy)
                fields.append(
                    .accuracy(accuracy, fullCombo: combo,
                              percentageVisible: visibility.percentage, tint: tint)
                )
            } else if combo {
                fields.append(
                    .accuracy(nil, fullCombo: true,
                              percentageVisible: visibility.percentage, tint: nil)
                )
            }
        }
        if visibility.percentile, let rank = score.rank, let total = score.totalEntries,
           let bucket = ScoreFormatting.percentileBucket(rank: rank, totalEntries: total) {
            let percentile = min(Double(rank) / Double(total) * 100, 100)
            let tier: SongPercentileTier = percentile <= 1
                ? .topOne : percentile <= 5 ? .topFive : .ordinary
            fields.append(.percentile(bucket, tier: tier))
        }
        if visibility.stars, let stars = score.stars, stars > 0 {
            fields.append(.stars(count: stars >= 6 ? 5 : stars, gold: stars >= 6))
        }
        if visibility.season, let season = score.season, season > 0 {
            fields.append(.season(season, current: currentSeason == season))
        }
        if visibility.intensity, let raw = song?.difficulty?.chartedValue(for: chart) {
            fields.append(.intensity(raw))
        }
        if visibility.difficulty, let difficulty = score.difficulty,
           difficulty.rounded() == difficulty, (0...3).contains(difficulty) {
            fields.append(.difficulty(Int(difficulty)))
        }
        if visibility.lastPlayed,
           let rawDate = score.validLastPlayedAt ?? score.lastPlayedAt {
            do {
                let date = try Date.ISO8601FormatStyle().parse(rawDate)
                fields.append(.lastPlayed(
                    "Last played \(date.formatted(date: .abbreviated, time: .omitted))"
                ))
            } catch {
                fields.append(.lastPlayed("Last played date unavailable"))
            }
        }
        return fields
    }

    /// Derive the existing fallback label from the same typed source-ordered fields.
    ///
    /// - Parameters:
    ///   - score: Validated player score in the current chart.
    ///   - chart: Visible chart used for the fallback's context label.
    ///   - visibility: Saved independent score switches.
    /// - Returns: Chart context followed by enabled readable values.
    /// - Throws: The typed projection's explicit invalid-accuracy error.
    static func labels(
        for score: PlayerScore, chart: Instrument, visibility: SongMetadataVisibility
    ) throws -> [String] {
        [chart.label] + (try fields(
            for: score, chart: chart, song: nil,
            currentSeason: nil, visibility: visibility
        )).map(\.plainLabel)
    }
}
