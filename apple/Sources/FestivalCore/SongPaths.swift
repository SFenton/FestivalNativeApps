import Foundation
import ImageIO

/// Supported CHOpt difficulties in the public path artifact route.
public enum PathDifficulty: String, CaseIterable, Codable, Identifiable, Sendable {
    case easy
    case medium
    case hard
    case expert

    public var id: String { rawValue }

    /// Display the selected difficulty without a web-specific icon.
    ///
    /// - Returns: Readable difficulty label.
    public var label: String { rawValue.capitalized }
}

/// Each mode has its own publication-aware path and loading state.
public enum PathDisplayMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case image
    case text

    public var id: String { rawValue }

    /// Name the native image or structured text display.
    ///
    /// - Returns: Readable display mode.
    public var label: String { rawValue.capitalized }
}

/// A service note used to identify the frets at an activation anchor.
public struct PathNote: Decodable, Sendable {
    public let beat: Double
    public let seconds: Double?
    public let isSpNote: Bool
    public let frets: [String: Double]
}

/// Optional scored note included in a path activation.
public struct PathStartNote: Decodable, Sendable {
    public let beat: Double
    public let seconds: Double?
    public let cumulativeScore: Int
    public let noteValue: Int
    public let odPercent: Double
    public let isSpGranting: Bool
}

/// One CHOpt activation, including optional schema-two instructions.
public struct PathActivation: Decodable, Sendable {
    public let startBeat: Double
    public let endBeat: Double
    public let startSeconds: Double?
    public let activationBeat: Double?
    public let activationSeconds: Double?
    public let anchorBeat: Double?
    public let odAtActivation: Double?
    public let scoreBeforeActivation: Int?
    public let instruction: String?
    public let startNotes: [PathStartNote]?
}

/// Native table values resolved from the path's activation and note lists.
public struct PathActivationRow: Sendable {
    public let number: Int
    public let instruction: String?
    public let beat: Double
    public let seconds: Double
    public let odPercent: Double?
    public let scoreBeforeActivation: Int?
    public let frets: [String]
}

/// Structured text artifact from `/api/paths/{song}/{chart}/{difficulty}/data`.
public struct SongPathData: Decodable, Sendable {
    public let schemaVersion: Int?
    public let songName: String
    public let artist: String
    public let charter: String
    public let difficulty: String
    public let totalScore: Int
    public let pathSummary: String
    public let activations: [PathActivation]
    public let notes: [PathNote]

    /// Reject malformed or oversized path data before it enters an offline snapshot.
    ///
    /// - Parameter requested: Difficulty whose endpoint produced this response.
    /// - Throws: `FestivalAPIError.invalidPathData` for inconsistent or unsafe values.
    public func validate(for requested: PathDifficulty) throws {
        let fretKeys: Set<String> = ["green", "red", "yellow", "blue", "orange", "open"]
        guard schemaVersion.map({ (1...2).contains($0) }) ?? true,
              difficulty.lowercased() == requested.rawValue,
              !songName.isEmpty, !artist.isEmpty, totalScore > 0,
              activations.count <= 128, notes.count <= 25_000,
              activations.allSatisfy({ activation in
                  Self.validBeat(activation.startBeat)
                  && Self.validBeat(activation.endBeat)
                  && activation.endBeat >= activation.startBeat
                  && [activation.activationBeat, activation.anchorBeat]
                      .compactMap { $0 }.allSatisfy(Self.validBeat)
                  && [activation.startSeconds, activation.activationSeconds]
                      .compactMap { $0 }.allSatisfy(Self.validSeconds)
                  && activation.odAtActivation.map {
                      $0.isFinite && (0...1).contains($0)
                  } != false
                  && activation.scoreBeforeActivation.map { $0 >= 0 } != false
                  && (activation.startNotes?.count ?? 0) <= 256
                  && (activation.startNotes ?? []).allSatisfy { note in
                      Self.validBeat(note.beat)
                      && note.seconds.map(Self.validSeconds) != false
                      && note.cumulativeScore >= 0 && note.noteValue >= 0
                      && note.odPercent.isFinite && (0...1).contains(note.odPercent)
                  }
              }),
              notes.allSatisfy({ note in
                  Self.validBeat(note.beat)
                  && note.seconds.map(Self.validSeconds) != false
                  && note.frets.keys.allSatisfy(fretKeys.contains)
                  && note.frets.values.allSatisfy(Self.validBeat)
              }) else {
            throw FestivalAPIError.invalidPathData
        }
    }

    /// Bound note locations and sustain lengths before native row formatting.
    ///
    /// - Parameter beat: Raw beat from the path artifact.
    /// - Returns: True only for a finite, displayable beat.
    private static func validBeat(_ beat: Double) -> Bool {
        beat.isFinite && (0...1_000_000).contains(beat)
    }

    /// Bound timestamps before converting seconds to integer milliseconds.
    ///
    /// - Parameter seconds: Raw timestamp from the path artifact.
    /// - Returns: True only for a finite timestamp within one day.
    private static func validSeconds(_ seconds: Double) -> Bool {
        seconds.isFinite && (0...86_400).contains(seconds)
    }

    /// Resolve native activation cells using the source's note-anchor tolerance.
    ///
    /// - Returns: Ordered text rows with note frets, time, OD and score.
    public func activationRows() -> [PathActivationRow] {
        let ordered = notes.sorted { $0.beat < $1.beat }
        return activations.enumerated().map { index, activation in
            let first = activation.startNotes?.first
            let beat = activation.activationBeat ?? first?.beat ?? activation.startBeat
            let anchor = activation.anchorBeat ?? first?.beat
                ?? Self.nearbyAnchor(beat, in: ordered)
            let frets = anchor.map { Self.chordFrets(at: $0, in: ordered) } ?? []
            return PathActivationRow(
                number: index + 1, instruction: activation.instruction,
                beat: beat,
                seconds: activation.activationSeconds
                    ?? first?.seconds ?? activation.startSeconds ?? 0,
                odPercent: activation.odAtActivation.map { $0 * 100 }
                    ?? first.map { $0.odPercent * 100 },
                scoreBeforeActivation: activation.scoreBeforeActivation
                    ?? first?.cumulativeScore,
                frets: frets
            )
        }
    }

    /// Locate all simultaneous fret keys without scanning the entire chart per cell.
    ///
    /// - Parameters:
    ///   - anchor: Activation's resolved note beat.
    ///   - ordered: Beat-sorted notes for this path.
    /// - Returns: Fret names in the source's visible order.
    private static func chordFrets(at anchor: Double, in ordered: [PathNote]) -> [String] {
        var low = 0
        var high = ordered.count
        while low < high {
            let middle = (low + high) / 2
            if ordered[middle].beat < anchor - 0.02 {
                low = middle + 1
            } else {
                high = middle
            }
        }
        var found = Set<String>()
        while low < ordered.count && ordered[low].beat < anchor + 0.02 {
            if abs(ordered[low].beat - anchor) < 0.02 {
                found.formUnion(ordered[low].frets.keys)
            }
            low += 1
        }
        return ["green", "red", "yellow", "blue", "orange", "open"]
            .filter(found.contains)
    }

    /// Prefer a sustained note at the activation, then a coincident prior note.
    ///
    /// - Parameters:
    ///   - beat: Activation point from the CHOpt response.
    ///   - ordered: Note list sorted once for all rendered rows.
    /// - Returns: Note beat whose fret chord annotates the activation.
    private static func nearbyAnchor(_ beat: Double, in ordered: [PathNote]) -> Double? {
        var prior: Double?
        var sustained: Double?
        for note in ordered {
            if note.beat > beat + 0.02 { break }
            prior = note.beat
            let sustain = note.frets.values.max() ?? 0
            if note.beat + sustain >= beat - 0.02 {
                sustained = note.beat
            }
        }
        if let sustained { return sustained }
        if let prior, abs(prior - beat) < 0.02 { return prior }
        return nil
    }
}

/// A typed path response with separate observed and response-proven generations.
public struct SongPathDataPayload: Sendable {
    public let path: SongPathData
    public let rows: [PathActivationRow]
    public let publicationId: Int?
    public let observedPublicationId: Int
    public let isStale: Bool
}

/// ImageIO produces an immutable CGImage off the UI actor before caching bytes.
public struct SongPathImagePayload: @unchecked Sendable {
    public let image: CGImage
    public let publicationId: Int?
    public let observedPublicationId: Int
    public let isStale: Bool
}

/// Decode only a bounded, single-frame PNG rather than a full-size UI-thread image.
enum SongPathImageDecoding {
    /// Validate and downsample one public path image on a utility executor.
    ///
    /// - Parameter data: Raw PNG bytes from a public, publication-aware GET.
    /// - Returns: Immutable image limited to a 4,096-pixel longest edge.
    /// - Throws: `FestivalAPIError.invalidPathImage` for an invalid or oversized PNG.
    static func prepare(_ data: Data) async throws -> CGImage {
        guard data.count <= 8_000_000,
              data.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        else {
            throw FestivalAPIError.invalidPathImage
        }
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetCount(source) == 1,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                    as? [String: Any],
                  let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
                  (1...8192).contains(width), (1...30_000).contains(height),
                  width * height <= 24_000_000 else {
                throw FestivalAPIError.invalidPathImage
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                source, 0, options as CFDictionary
            ) else {
                throw FestivalAPIError.invalidPathImage
            }
            try Task.checkCancellation()
            return thumbnail
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}

extension FestivalAPI {
    /// Fetch and validate structured CHOpt text before retaining headerless bytes.
    ///
    /// - Parameters:
    ///   - songId: Catalog song identifier.
    ///   - instrument: Path-capable, currently selected chart.
    ///   - difficulty: Requested path difficulty.
    ///   - generationId: Optional artifact revision from the catalog.
    /// - Returns: Typed path and explicit response provenance.
    /// - Throws: Network, publication or malformed-data failures.
    public func pathData(
        songId: String, instrument: Instrument, difficulty: PathDifficulty,
        generationId: String? = nil
    ) async throws -> SongPathDataPayload {
        let endpoint = PublicEndpoint.path(
            songId: songId, instrument: instrument, difficulty: difficulty,
            display: .text, generationId: generationId
        )
        let payload = try await read(endpoint)
        guard payload.data.count <= 8_000_000 else {
            throw FestivalAPIError.invalidPathData
        }
        let path: SongPathData
        do {
            path = try JSONDecoder().decode(SongPathData.self, from: payload.data)
        } catch is DecodingError {
            throw FestivalAPIError.invalidPathData
        }
        try path.validate(for: difficulty)
        try await rememberUnverified(payload, for: endpoint)
        return SongPathDataPayload(
            path: path, rows: path.activationRows(), publicationId: payload.publicationId,
            observedPublicationId: payload.observedPublicationId, isStale: payload.isStale
        )
    }

    /// Fetch and decode a bounded CHOpt image without a URLSession disk cache.
    ///
    /// - Parameters:
    ///   - songId: Catalog song identifier.
    ///   - instrument: Path-capable chart.
    ///   - difficulty: Requested path difficulty.
    ///   - generationId: Optional artifact revision from the catalog.
    /// - Returns: Decoded image and explicit response provenance.
    /// - Throws: Network, publication or malformed-image failures.
    public func pathImage(
        songId: String, instrument: Instrument, difficulty: PathDifficulty,
        generationId: String? = nil
    ) async throws -> SongPathImagePayload {
        let endpoint = PublicEndpoint.path(
            songId: songId, instrument: instrument, difficulty: difficulty,
            display: .image, generationId: generationId
        )
        let payload = try await read(endpoint)
        let image = try await SongPathImageDecoding.prepare(payload.data)
        try Task.checkCancellation()
        try await rememberUnverified(payload, for: endpoint)
        return SongPathImagePayload(
            image: image, publicationId: payload.publicationId,
            observedPublicationId: payload.observedPublicationId, isStale: payload.isStale
        )
    }
}
