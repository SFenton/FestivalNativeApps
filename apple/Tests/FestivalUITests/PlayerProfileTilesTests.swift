import FestivalCore
import Testing
@testable import FestivalUI

/// The shared profile rules the SwiftUI page and the UIKit port both call.
@MainActor
struct PlayerProfileTilesTests {
    @Test func formatsFullComboAndRank() {
        #expect(PlayerProfileTiles.fullComboText(count: 0, percent: 0) == "0")
        #expect(PlayerProfileTiles.fullComboText(count: 5, percent: 100) == "5")
        #expect(PlayerProfileTiles.fullComboText(count: 2, percent: 66.6) == "2 (66.6%)")
        #expect(PlayerProfileTiles.rankText(nil) == "\u{2014}")
        #expect(PlayerProfileTiles.rankText(12) == "#12")
    }

    @Test func identityRules() {
        #expect(PlayerProfileTiles.identity(isSelected: true, payloadPublicationId: nil, sessionPublicationId: 1, hasSelectedPlayer: true) == .deselect)
        #expect(PlayerProfileTiles.identity(isSelected: false, payloadPublicationId: 1, sessionPublicationId: 1, hasSelectedPlayer: false) == .select)
        #expect(PlayerProfileTiles.identity(isSelected: false, payloadPublicationId: 1, sessionPublicationId: 1, hasSelectedPlayer: true) == .switchTo)
        #expect(PlayerProfileTiles.identity(isSelected: false, payloadPublicationId: 2, sessionPublicationId: 1, hasSelectedPlayer: true) == nil)
    }

    @Test func linkDecisions() {
        let songs = PlayerStatLink.songs(.overall(.hasScores, visible: [.lead]))
        let rank = PlayerStatLink.fullRankings(.lead, rankBy: "totalscore")
        #expect(PlayerProfileTiles.decision(for: songs, isSelected: true, identity: nil) == .navigate)
        #expect(PlayerProfileTiles.decision(for: songs, isSelected: false, identity: .select) == .selectThenNavigate)
        #expect(PlayerProfileTiles.decision(for: songs, isSelected: false, identity: .switchTo) == .confirmSwitch)
        #expect(PlayerProfileTiles.decision(for: songs, isSelected: false, identity: nil) == .ignore)
        #expect(PlayerProfileTiles.decision(for: rank, isSelected: false, identity: nil) == .navigate)
    }

    @Test func tileLinkNeedsNavigatorAndSelection() {
        let songs = PlayerStatLink.songs(.overall(.hasScores, visible: [.lead]))
        #expect(PlayerProfileTiles.tileLink(songs, hasNavigator: false, isSelected: true, hasIdentity: true) == nil)
        #expect(PlayerProfileTiles.tileLink(songs, hasNavigator: true, isSelected: false, hasIdentity: false) == nil)
        #expect(PlayerProfileTiles.tileLink(songs, hasNavigator: true, isSelected: false, hasIdentity: true) == songs)
    }
}
