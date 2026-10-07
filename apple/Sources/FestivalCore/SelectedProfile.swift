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

/// A band selected as the Songs profile: its size, roster key and display name.
///
/// Band selection has no persisted store or user-facing entry yet (PROGRESS.md:
/// "select as band profile" is unported); it is set in memory for debug launches
/// (`FST_DEBUG_BAND`) and hosted tests. Reads use only the keyless band song-rows
/// index, never band search, band detail or sync-status.
public struct SelectedBandIdentity: Equatable, Sendable, Identifiable {
    public let bandType: BandType
    public let teamKey: String
    public let displayName: String

    public var id: String { "\(bandType.rawValue)/\(teamKey)" }

    /// Create an identity without validating it; call ``validate()`` before a read.
    ///
    /// - Parameters:
    ///   - bandType: Band size.
    ///   - teamKey: Colon-separated member account IDs.
    ///   - displayName: Name shown for the band.
    public init(bandType: BandType, teamKey: String, displayName: String) {
        self.bandType = bandType
        self.teamKey = teamKey
        self.displayName = displayName
    }

    /// Members a band of this size has.
    public var memberCount: Int {
        switch bandType {
        case .duets: 2
        case .trios: 3
        case .quad: 4
        }
    }

    /// Check the roster key and name before using them in a native GET path.
    ///
    /// - Throws: `FestivalAPIError.invalidSelectedProfile` for a key whose members are
    ///   not distinct valid account IDs matching the band size, or an unsafe name.
    public func validate() throws {
        let members = teamKey.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard members.count == memberCount, Set(members).count == members.count,
              members.allSatisfy(ProfileSearchText.isValidAccountId),
              !displayName.isEmpty, displayName.count <= 200,
              displayName == displayName.trimmingCharacters(in: .whitespacesAndNewlines),
              !ProfileSearchText.containsUnsafeScalar(displayName) else {
            throw FestivalAPIError.invalidSelectedProfile
        }
    }
}
