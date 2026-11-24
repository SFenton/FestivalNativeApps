import Foundation
import FestivalCore

// MARK: - Path load

/// What one Paths pane shows, and how it is read: shared by the SwiftUI ``SongPathsSheet``
/// and the UIKit port's Paths page so both reload, fail and speak identically.
enum SongPathsLoadState {
    /// The CHOpt path image.
    case image(SongPathImagePayload)
    /// The activation table.
    case text(SongPathDataPayload)
    /// The read failed; the pane shows a status view with Retry.
    case failed(ServiceIssue)

    /// Read one pane's content.
    ///
    /// - Parameters:
    ///   - display: Image or text.
    ///   - instrument: The chart.
    ///   - difficulty: The difficulty.
    ///   - song: The song.
    ///   - session: Process-scoped, publication-aware public client.
    /// - Returns: The image, table or failure to show.
    /// - Throws: `CancellationError` when a newer selection cancels the request.
    @MainActor
    static func fetch(
        _ display: PathDisplayMode, instrument: Instrument, difficulty: PathDifficulty, song: Song, session: FestivalSession
    ) async throws -> SongPathsLoadState {
        do {
            switch display {
            case .image:
                return .image(try await session.pathImage(song: song, instrument: instrument, difficulty: difficulty))
            case .text:
                return .text(try await session.pathData(song: song, instrument: instrument, difficulty: difficulty))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return .failed(ServiceIssue(error))
        }
    }

    /// What VoiceOver hears once new content fades in; failures announce themselves.
    ///
    /// - Parameters:
    ///   - instrument: The chart.
    ///   - difficulty: The difficulty.
    /// - Returns: The announcement, or nil for a failure.
    func loadedAnnouncement(instrument: Instrument, difficulty: PathDifficulty) -> String? {
        switch self {
        case .image: SongPathsSheet.loadedAnnouncement(instrument: instrument, difficulty: difficulty, activations: nil)
        case let .text(payload): SongPathsSheet.loadedAnnouncement(instrument: instrument, difficulty: difficulty, activations: payload.rows.count)
        case .failed: nil
        }
    }
}

// MARK: - Activation card

/// The Paths text card's presentation rules.
enum SongPathsActivation {
    /// Frets in lane order.
    static let frets = ["green", "red", "yellow", "blue", "orange"]

    /// A fret's fill (sRGB, 0 to 1), or nil for an unknown name.
    ///
    /// - Parameter name: "green", "red", "yellow", "blue" or "orange".
    /// - Returns: The components.
    static func fretRGB(_ name: String) -> (red: Double, green: Double, blue: Double)? {
        switch name {
        case "green": (46.0 / 255, 204.0 / 255, 113.0 / 255)
        case "red": (231.0 / 255, 76.0 / 255, 60.0 / 255)
        case "yellow": (241.0 / 255, 196.0 / 255, 15.0 / 255)
        case "blue": (52.0 / 255, 152.0 / 255, 219.0 / 255)
        case "orange": (230.0 / 255, 126.0 / 255, 34.0 / 255)
        default: nil
        }
    }

    /// Format seconds as the source's minute/second/millisecond time.
    ///
    /// - Parameter seconds: Nonnegative, validated time from CHOpt data.
    /// - Returns: `mm:ss:SSS` with normalized millisecond rollover.
    static func time(_ seconds: Double) -> String {
        let millis = Int((seconds * 1000).rounded())
        return String(format: "%02d:%02d:%03d", millis / 60_000, millis / 1_000 % 60, millis % 1_000)
    }

    /// Everything the card shows, for VoiceOver.
    ///
    /// - Parameter row: The activation.
    /// - Returns: Frets, beat, time, score and overdrive.
    static func spokenValue(_ row: PathActivationRow) -> String {
        var parts = [row.frets.isEmpty ? "No anchor note" : "Frets \(row.frets.joined(separator: ", "))"]
        parts.append("beat \(row.beat.formatted(.number.precision(.fractionLength(2))))")
        parts.append("time \(time(row.seconds))")
        if let score = row.scoreBeforeActivation { parts.append("score \(score.formatted())") }
        if let od = row.odPercent { parts.append("overdrive \(Int(od.rounded())) percent") }
        return parts.joined(separator: ", ")
    }
}
