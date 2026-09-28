import Foundation

/// Exact service identifiers and labels for the nine solo instrument charts.
public enum Instrument: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case lead = "Solo_Guitar"
    case bass = "Solo_Bass"
    case drums = "Solo_Drums"
    case vocals = "Solo_Vocals"
    case proLead = "Solo_PeripheralGuitar"
    case proBass = "Solo_PeripheralBass"
    case karaoke = "Solo_PeripheralVocals"
    case proCymbals = "Solo_PeripheralCymbals"
    case proDrums = "Solo_PeripheralDrums"

    public var id: String { rawValue }

    /// Present the same instrument names as the web client.
    ///
    /// - Returns: User-facing instrument label.
    public var label: String {
        switch self {
        case .lead: "Lead"
        case .bass: "Bass"
        case .drums: "Drums"
        case .vocals: "Tap Vocals"
        case .proLead: "Pro Lead"
        case .proBass: "Pro Bass"
        case .karaoke: "Karaoke"
        case .proCymbals: "Pro Drums + Cymbals"
        case .proDrums: "Pro Drums"
        }
    }
}

/// Chart difficulties use ordinary keys even though API instrument IDs differ.
public struct SongDifficulty: Decodable, Sendable, Equatable, Hashable {
    public let guitar: Double?
    public let bass: Double?
    public let drums: Double?
    public let vocals: Double?
    public let proGuitar: Double?
    public let proBass: Double?
    public let proDrums: Double?
    public let proCymbals: Double?
    public let proVocals: Double?

    /// Return nil for an uncharted instrument (including the service's 99 sentinel).
    ///
    /// - Parameter instrument: Chart to inspect.
    /// - Returns: Its finite raw difficulty, or nil when not charted.
    public func chartedValue(for instrument: Instrument) -> Double? {
        let value: Double?
        switch instrument {
        case .lead: value = guitar
        case .bass: value = bass
        case .drums: value = drums
        case .vocals: value = vocals
        case .proLead: value = proGuitar
        case .proBass: value = proBass
        case .karaoke: value = proVocals
        case .proCymbals: value = proCymbals
        case .proDrums: value = proDrums
        }
        guard let value, value.isFinite, value >= 0, value != 99 else {
            return nil
        }
        return value
    }
}

/// Fields directly present in the service's `/api/songs` wire objects.
public struct Song: Decodable, Sendable, Identifiable, Equatable, Hashable {
    public let songId: String
    public let title: String
    public let artist: String
    public let album: String?
    public let year: Int?
    public let durationSeconds: Int?
    public let albumArt: String?
    public let difficulty: SongDifficulty?
    public let pathArtifactGenerationId: String?
    /// Lead/Pro Lead controller signature from the service (`"Guitar"` or
    /// `"Keyboard"`); selects the matching `InstrumentIcon` variant.
    public let sig: String?

    public var id: String { songId }

    /// Whether Lead/Pro Lead should use the keys icon variant instead of guitar.
    public var usesKeyboardIcon: Bool { sig == "Keyboard" }

    /// Format a positive catalogue duration like the source Song info block.
    ///
    /// - Returns: `m:ss` or `h:mm:ss`, or nil for missing or nonpositive seconds.
    public var formattedDuration: String? {
        guard let durationSeconds, durationSeconds > 0 else { return nil }
        let hours = durationSeconds / 3_600
        let minutes = (durationSeconds % 3_600) / 60
        let seconds = durationSeconds % 60
        let secondText = seconds < 10 ? "0\(seconds)" : "\(seconds)"
        if hours > 0 {
            let minuteText = minutes < 10 ? "0\(minutes)" : "\(minutes)"
            return "\(hours):\(minuteText):\(secondText)"
        }
        return "\(minutes):\(secondText)"
    }

    /// Whether an instrument has a playable chart, independent of visibility.
    ///
    /// - Parameter instrument: Solo chart selected by the user.
    /// - Returns: True if its raw difficulty is neither absent nor uncharted.
    public func supports(_ instrument: Instrument) -> Bool {
        difficulty?.chartedValue(for: instrument) != nil
    }
}

/// Catalog wire envelope; compact population-tier fields need separate expansion.
public struct SongsResponse: Decodable, Sendable, Equatable {
    public let count: Int
    public let currentSeason: Int?
    public let songs: [Song]

    /// Reject contradictory catalogue cardinality instead of showing false data.
    ///
    /// - Throws: `FestivalAPIError.invalidCatalogue` when count is inconsistent.
    public func validate() throws {
        guard count >= 0, count == songs.count,
              songs.allSatisfy({ !$0.songId.isEmpty && !$0.title.isEmpty }) else {
            throw FestivalAPIError.invalidCatalogue
        }
    }
}

/// Decoded catalogue accompanied by the source's offline freshness.
public struct CatalogPayload: Sendable {
    public let catalog: SongsResponse
    public let publicationId: Int?
    public let observedPublicationId: Int
    public let isStale: Bool
}

extension FestivalAPI {
    /// Fetch, validate and label songs without persisting them across cold launches.
    ///
    /// - Returns: Decoded wire catalogue and explicit freshness information.
    /// - Throws: Service, decoding or catalogue consistency errors.
    public func catalog() async throws -> CatalogPayload {
        let payload = try await read(.songs)
        let catalog = try JSONDecoder().decode(SongsResponse.self, from: payload.data)
        try catalog.validate()
        try await rememberUnverified(payload, for: .songs)
        return CatalogPayload(
            catalog: catalog,
            publicationId: payload.publicationId,
            observedPublicationId: payload.observedPublicationId,
            isStale: payload.isStale
        )
    }
}
