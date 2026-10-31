import Foundation
import Testing
@testable import FestivalCore
@testable import FestivalUI

/// The Songs decisions shared by the SwiftUI page and the UIKit port (``SongsPipeline``,
/// ``SongProfileSummaryText``): saved-settings defaults and the profile summary's words.
@MainActor
@Suite
struct SongsPipelineTests {
    /// A private defaults store, emptied for each test.
    private func store() -> UserDefaults {
        let name = "fst.tests.songs-pipeline.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func settingsDefaultToTitleAscendingWithEverythingVisible() {
        let settings = SongsSettings.load(from: store())
        #expect(settings.sortMode == .title)
        #expect(settings.sortAscending)
        #expect(!settings.hideShop)
        #expect(settings.showInstrumentIcons)
        #expect(settings.metadata == SongMetadataVisibility())
        #expect(settings.leeway == 1.0)
    }

    @Test func settingsReadTheKeysSongsScreenDeclares() {
        let defaults = store()
        defaults.set("year", forKey: "fst.songs.sortMode")
        defaults.set(false, forKey: "fst.songs.sortAscending")
        defaults.set(true, forKey: "fst.settings.hideShop")
        defaults.set(false, forKey: "fst.settings.metadataScore")
        defaults.set(1.4, forKey: "fst.settings.leeway")
        let settings = SongsSettings.load(from: defaults)
        #expect(settings.sortMode == .year)
        #expect(!settings.sortAscending)
        #expect(settings.hideShop)
        #expect(!settings.metadata.score)
        #expect(settings.metadata.percentage)
        #expect(settings.leeway == 1.4)
    }

    @Test func unreadableSortModeFallsBackToTitle() {
        let defaults = store()
        defaults.set("not-a-mode", forKey: "fst.songs.sortMode")
        #expect(SongsSettings.load(from: defaults).sortMode == .title)
    }

    @Test func summaryNamesEachLoadState() {
        let json = Data(#"{"accountId":"fixture-player-1","displayName":"Fixture Player 1"}"#.utf8)
        let player = try! JSONDecoder().decode(SelectedPlayerIdentity.self, from: json)
        func line(_ state: SelectedPlayerLoadState, chart: Instrument? = .lead, available: Bool = true) -> SongProfileSummaryText.Line {
            SongProfileSummaryText.line(
                player: player, chart: chart, chartAvailable: available, score: nil, state: state,
                visibility: SongMetadataVisibility()
            )
        }
        #expect(line(.loading).text == "Loading Fixture Player 1's scores")
        #expect(line(.syncing).symbol == "arrow.triangle.2.circlepath")
        #expect(line(.failed).gold)
        #expect(line(.none).text == "Selected player scores are not loaded")
        #expect(line(.available, available: false).text == "\(Instrument.lead.label) is not charted for this song")
        #expect(line(.available).text == "No \(Instrument.lead.label) score for Fixture Player 1")
        #expect(line(.available, chart: nil).text == "No visible instrument in Settings")
        #expect(line(.available, chart: nil).gold)
    }

    @Test func noGroupsWithoutSectionsOfAKind() {
        #expect(SongsPipeline.listGroups(indexSections: nil, shopSections: nil, durationSections: nil, yearSections: nil) == nil)
    }

    @Test func indexSectionsBecomeScrubberGroups() throws {
        let sections = [SongSection(id: 0, label: "A", songs: []), SongSection(id: 1, label: "B", songs: [])]
        let groups = try #require(SongsPipeline.listGroups(indexSections: sections, shopSections: nil, durationSections: nil, yearSections: nil))
        #expect(groups.map(\.label) == ["A", "B"])
        #expect(groups.map(\.accessibilityID) == ["fst.songs.section.0", "fst.songs.section.1"])
        #expect(groups.allSatisfy { $0.quickLink == nil })
    }
}
