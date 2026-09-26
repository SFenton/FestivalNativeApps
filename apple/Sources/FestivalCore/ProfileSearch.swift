import Foundation

/// Preserve legitimate name-joining format characters while blocking controls and bidi spoofing.
enum ProfileSearchText {
    /// Check raw search and display text before it becomes visible or navigable.
    ///
    /// - Parameter text: Untrusted user-entered query or service display name.
    /// - Returns: True for actual control, line-separator or bidi-override characters.
    static func containsUnsafeScalar(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            let value = scalar.value
            return value < 0x20 || (0x7F...0x9F).contains(value)
                || (0x2028...0x202E).contains(value)
                || (0x2066...0x2069).contains(value)
        }
    }
}

/// An identity returned by the public account-name search, not a selected profile.
public struct PlayerSearchResult: Decodable, Sendable, Equatable, Identifiable {
    public let accountId: String
    public let displayName: String

    public var id: String { accountId }

    private enum CodingKeys: String, CodingKey {
        case accountId, displayName
    }

    /// Trim benign outer whitespace as the website does, without masking unsafe controls.
    ///
    /// - Parameter decoder: Raw account-search row from the public service.
    /// - Throws: Decoding or invalid-profile-search errors.
    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        accountId = try fields.decode(String.self, forKey: .accountId)
        let rawName = try fields.decode(String.self, forKey: .displayName)
        guard !ProfileSearchText.containsUnsafeScalar(rawName) else {
            throw FestivalAPIError.invalidProfileSearch
        }
        displayName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reject malformed or ambiguous identities before they enter native selection.
    ///
    /// - Throws: `FestivalAPIError.invalidProfileSearch` for an unusable result.
    public func validate() throws {
        let validId = accountId.range(
            of: #"\A[A-Za-z0-9_-]{1,128}\z"#, options: .regularExpression
        ) != nil
        guard validId, !displayName.isEmpty, displayName.count <= 200 else {
            throw FestivalAPIError.invalidProfileSearch
        }
    }
}

/// Native direct-read account search has no client publication pin or offline cache.
public struct PlayerSearchResponse: Decodable, Sendable, Equatable {
    public let results: [PlayerSearchResult]

    /// Require a bounded, unique result set rather than silently dropping bad rows.
    ///
    /// - Parameter limit: Maximum result count requested from the service.
    /// - Throws: `FestivalAPIError.invalidProfileSearch` for malformed identities.
    public func validate(limit: Int) throws {
        guard (1...10).contains(limit), results.count <= limit else {
            throw FestivalAPIError.invalidProfileSearch
        }
        var accountIds = Set<String>()
        for result in results {
            try result.validate()
            guard accountIds.insert(result.accountId.lowercased()).inserted else {
                throw FestivalAPIError.invalidProfileSearch
            }
        }
    }
}

extension FestivalAPI {
    /// Search public account names without selected-profile headers or a tracking POST.
    ///
    /// - Parameters:
    ///   - query: Trimmed user text of 2-200 characters.
    ///   - limit: Maximum of ten public identities to return.
    /// - Returns: Validated results, including an empty response envelope.
    /// - Throws: Invalid input, HTTP 403, transport, cancellation or malformed wire errors.
    public func searchPlayers(query: String, limit: Int = 10) async throws
        -> PlayerSearchResponse {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        try Task.checkCancellation()
        let data: Data
        do {
            data = try await readOperational(.accountSearch(query: normalized, limit: limit))
        } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
            throw CancellationError()
        }
        try Task.checkCancellation()
        guard data.count <= 64_000 else {
            throw FestivalAPIError.invalidProfileSearch
        }
        do {
            let response = try JSONDecoder().decode(PlayerSearchResponse.self, from: data)
            try response.validate(limit: limit)
            try Task.checkCancellation()
            return response
        } catch is DecodingError {
            throw FestivalAPIError.invalidProfileSearch
        }
    }
}
