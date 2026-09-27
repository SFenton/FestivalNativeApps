import Foundation
import Testing
@testable import FestivalCore

/// Reconstruct a locally authored player result without a real account lookup.
///
/// - Parameters:
///   - accountId: Synthetic account key.
///   - displayName: Synthetic visible player name.
/// - Returns: Public search result that has not been selected.
/// - Throws: Invalid synthetic JSON.
private func searchedPlayer(_ accountId: String, _ displayName: String) throws
    -> PlayerSearchResult {
    try JSONDecoder().decode(PlayerSearchResult.self, from: Data("""
    {"accountId":"\(accountId)","displayName":"\(displayName)"}
    """.utf8))
}

@Test func selectionRequiresAViewedSearchResultAndPersistsIdentityOnly() throws {
    let viewed = try searchedPlayer("fixture-player-1", "Fixture Player 1")
    let selected = try SelectedPlayerIdentity(searchResult: viewed)
    try selected.validate()
    #expect(selected.accountId == "fixture-player-1")
    #expect(selected.id == selected.accountId)
    #expect(selected.displayName == "Fixture Player 1")

    let data = try JSONEncoder().encode(selected)
    let restored = try JSONDecoder().decode(SelectedPlayerIdentity.self, from: data)
    try restored.validate()
    #expect(restored == selected)
    let raw = try #require(String(data: data, encoding: .utf8))
    #expect(!raw.contains("score"))
    #expect(!raw.contains("isFullCombo"))
}

@Test func invalidRestoredProfilesFailInsteadOfBecomingSelected() throws {
    for json in [
        #"{"accountId":"../other","displayName":"Unsafe"}"#,
        #"{"accountId":"fixture-player-1","displayName":" "}"#,
        #"{"accountId":"fixture-player-1","displayName":"Bi\u202Edi"}"#,
        #"{"accountId":"fixture-player-1","displayName":" padded "}"#,
    ] {
        let identity = try JSONDecoder().decode(
            SelectedPlayerIdentity.self, from: Data(json.utf8)
        )
        #expect(throws: FestivalAPIError.invalidSelectedProfile) {
            try identity.validate()
        }
    }
    let broken = try searchedPlayer("fixture/bad", "Bad player")
    #expect(throws: FestivalAPIError.invalidProfileSearch) {
        try SelectedPlayerIdentity(searchResult: broken)
    }
}
