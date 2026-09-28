import Foundation

// MARK: - All-combo rivals (`GET /api/player/:accountId/rivals/all`)

/// One compact song sample shared between the player and a rival.
///
/// The wire uses single-letter keys (`s`, `i`, `ur`, `rr`, `us`, `rs`) to keep the
/// precomputed payload small (`FSTService/Scraping/ScrapeTimePrecomputer.cs`,
/// web `RivalsAllSample` in `packages/core/src/api/serverTypes.ts`).
public struct RivalsAllSample: Decodable, Sendable, Equatable {
    /// Index into `RivalsAllResponse.songs`.
    public let songIndex: Int
    /// Instrument key, for example `Solo_Guitar`.
    public let instrument: String
    /// The player's rank on this song and instrument.
    public let userRank: Int
    /// The rival's rank on this song and instrument.
    public let rivalRank: Int
    /// The player's score, when known.
    public let userScore: Int?
    /// The rival's score, when known.
    public let rivalScore: Int?

    private enum CodingKeys: String, CodingKey {
        case songIndex = "s"
        case instrument = "i"
        case userRank = "ur"
        case rivalRank = "rr"
        case userScore = "us"
        case rivalScore = "rs"
    }
}

/// A rival in one combo of the all-combo response.
///
/// The precomputed payload carries `direction` and `samples`; the service's
/// live fallback (used when no precomputed copy exists) omits both and adds
/// `avgSignedDelta`, so those fields are optional or default to empty.
public struct RivalsAllEntry: Decodable, Sendable, Equatable, Identifiable {
    public let accountId: String
    public let displayName: String?
    /// `above` or `below`, when the precomputed payload supplies it.
    public let direction: String?
    public let sharedSongCount: Int
    public let aheadCount: Int
    public let behindCount: Int
    public let rivalScore: Double
    /// Present only on the live fallback payload.
    public let avgSignedDelta: Double?
    /// Indexed song samples; empty on the live fallback payload.
    public let samples: [RivalsAllSample]

    public var id: String { accountId }

    private enum CodingKeys: String, CodingKey {
        case accountId, displayName, direction, sharedSongCount, aheadCount, behindCount
        case rivalScore, avgSignedDelta, samples
    }

    /// Decode either payload variant.
    ///
    /// - Parameter decoder: JSON decoder positioned at one rival object.
    /// - Throws: Missing required counts, identifiers or scores.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountId = try container.decode(String.self, forKey: .accountId)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        direction = try container.decodeIfPresent(String.self, forKey: .direction)
        sharedSongCount = try container.decode(Int.self, forKey: .sharedSongCount)
        aheadCount = try container.decode(Int.self, forKey: .aheadCount)
        behindCount = try container.decode(Int.self, forKey: .behindCount)
        rivalScore = try container.decode(Double.self, forKey: .rivalScore)
        avgSignedDelta = try container.decodeIfPresent(Double.self, forKey: .avgSignedDelta)
        samples = try container.decodeIfPresent([RivalsAllSample].self, forKey: .samples) ?? []
    }
}

/// One combo's rivals ahead of and behind the player.
public struct RivalsAllCombo: Decodable, Sendable, Equatable, Identifiable {
    /// Hex instrument-combo identifier, for example `01`.
    public let combo: String
    public let above: [RivalsAllEntry]
    public let below: [RivalsAllEntry]

    public var id: String { combo }
}

/// Response from `GET /api/player/{accountId}/rivals/all`: every combo's rivals
/// in one read, with song samples indexed into a shared `songs` table.
///
/// This is the source the web's `buildRivalDataIndexFromRivalsAll` uses for the
/// `song_rival_*`/`lb_rival_*` suggestion families.
public struct RivalsAllResponse: Decodable, Sendable, Equatable {
    public let accountId: String
    /// Deduplicated song IDs referenced by `RivalsAllSample.songIndex`.
    public let songs: [String]
    public let combos: [RivalsAllCombo]

    private enum CodingKeys: String, CodingKey {
        case accountId, songs, combos
    }

    /// Create a response directly (tests and empty normalization).
    ///
    /// - Parameters:
    ///   - accountId: Player whose rivals these are.
    ///   - songs: Song index table.
    ///   - combos: Per-combo rivals.
    public init(accountId: String, songs: [String], combos: [RivalsAllCombo]) {
        self.accountId = accountId
        self.songs = songs
        self.combos = combos
    }

    /// Decode either the precomputed or the live fallback payload.
    ///
    /// - Parameter decoder: JSON decoder positioned at the envelope.
    /// - Throws: A missing account ID or combos array.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountId = try container.decode(String.self, forKey: .accountId)
        songs = try container.decodeIfPresent([String].self, forKey: .songs) ?? []
        combos = try container.decode([RivalsAllCombo].self, forKey: .combos)
    }

    /// An empty result, used to normalize the endpoint's HTTP 404 "No rivals found."
    ///
    /// - Parameter accountId: Requested player.
    /// - Returns: A valid response with no combos.
    public static func empty(accountId: String) -> RivalsAllResponse {
        RivalsAllResponse(accountId: accountId, songs: [], combos: [])
    }

    /// Whether no combo has any rival.
    public var isEmpty: Bool {
        combos.allSatisfy { $0.above.isEmpty && $0.below.isEmpty }
    }

    /// Resolve a sample's song ID without trapping on a malformed index.
    ///
    /// - Parameter sample: Sample from any entry in this response.
    /// - Returns: The song ID, or nil when the index is out of range.
    public func songId(for sample: RivalsAllSample) -> String? {
        songs.indices.contains(sample.songIndex) ? songs[sample.songIndex] : nil
    }
}
