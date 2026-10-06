import Foundation

// MARK: - Band search response

/// The `results` of `GET /api/bands/search` (`BandSearchResponseDto`,
/// `FSTService/Persistence/DataTransferObjects.cs:423-483`; web `BandSearchResponse`).
///
/// Each `BandSearchResultDto` carries the `PlayerBandEntry` fields (band ID, team key,
/// band type, appearance count, members) plus ranking and parse provenance that global
/// search does not show, so results decode straight into ``PlayerBandEntry`` and render
/// with the same band card as the player Bands pages (web `PlayerBandCard`).
public struct BandSearchResponse: Decodable, Sendable, Equatable {
    /// Largest page the service serves (`Math.Clamp(pageSize, 1, 100)`).
    public static let maximumPageSize = 100

    public let results: [PlayerBandEntry]

    /// Require a bounded, unique, displayable result set rather than silently dropping
    /// bad rows.
    ///
    /// - Parameter pageSize: Rows requested from the service.
    /// - Throws: `FestivalAPIError.invalidBandSearch` for an unusable result.
    public func validate(pageSize: Int) throws {
        guard (1...Self.maximumPageSize).contains(pageSize), results.count <= pageSize else {
            throw FestivalAPIError.invalidBandSearch
        }
        // Unique by the identity the result list keys its rows on.
        var ids = Set<String>()
        for band in results {
            guard BandType(rawValue: band.bandType) != nil,
                  !band.teamKey.isEmpty, band.teamKey.count <= 600,
                  band.bandId.count <= 200, !band.bandId.contains("/"),
                  band.appearanceCount >= 0,
                  !band.members.isEmpty,
                  ids.insert(band.id).inserted
            else {
                throw FestivalAPIError.invalidBandSearch
            }
            for member in band.members {
                guard ProfileSearchText.isValidAccountId(member.accountId),
                      !ProfileSearchText.containsUnsafeScalar(member.displayName ?? "")
                else {
                    throw FestivalAPIError.invalidBandSearch
                }
            }
        }
    }
}

// MARK: - Band search read

extension FestivalAPI {
    /// Largest band-search body accepted (ten bands of up to four members each are a few
    /// kilobytes; the cap only bounds a misbehaving response).
    static let bandSearchByteLimit = 512_000

    /// Search bands by member names, the web global search's Bands query.
    ///
    /// `GET /api/bands/search?q=&page=1&pageSize=` with no selected-profile headers and no
    /// key. Read-only once the service serves only its band-search projection and never
    /// rebuilds membership rows (issue #320, `.agents/platforms/service-safety.md`).
    ///
    /// - Parameters:
    ///   - query: Trimmed user text of 2-200 characters.
    ///   - pageSize: Bands to return (web global search: 10).
    /// - Returns: Validated results, including an empty envelope.
    /// - Throws: Invalid input, HTTP, freeze, transport, cancellation or malformed wire
    ///   errors.
    public func searchBands(query: String, pageSize: Int = 10) async throws -> BandSearchResponse {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        try Task.checkCancellation()
        let data: Data
        do {
            data = try await readOperational(.bandSearch(query: normalized, pageSize: pageSize))
        } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
            throw CancellationError()
        }
        try Task.checkCancellation()
        guard data.count <= Self.bandSearchByteLimit else {
            throw FestivalAPIError.invalidBandSearch
        }
        do {
            let response = try JSONDecoder().decode(BandSearchResponse.self, from: data)
            try response.validate(pageSize: pageSize)
            try Task.checkCancellation()
            return response
        } catch is DecodingError {
            throw FestivalAPIError.invalidBandSearch
        }
    }
}
