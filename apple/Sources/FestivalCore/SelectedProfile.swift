import Foundation

/// Explicitly selected public identity, never the merely viewed search result.
public struct SelectedPlayerIdentity: Codable, Equatable, Sendable, Identifiable {
    public static let storageKey = "fst.profile.selectedPlayer.v1"

    public let accountId: String
    public let displayName: String

    public var id: String { accountId }

    /// Promote only an already validated public search identity.
    ///
    /// - Parameter searchResult: Player viewed before explicit selection.
    /// - Throws: An invalid or untrusted account-search result.
    public init(searchResult: PlayerSearchResult) throws {
        try searchResult.validate()
        accountId = searchResult.accountId
        displayName = searchResult.displayName
    }

    /// Revalidate stored public identity bytes before using them for a native GET.
    ///
    /// - Throws: `FestivalAPIError.invalidSelectedProfile` for corrupt or unsafe data.
    public func validate() throws {
        guard ProfileSearchText.isValidAccountId(accountId),
              !displayName.isEmpty, displayName.count <= 200,
              displayName == displayName.trimmingCharacters(in: .whitespacesAndNewlines),
              !ProfileSearchText.containsUnsafeScalar(displayName) else {
            throw FestivalAPIError.invalidSelectedProfile
        }
    }
}
