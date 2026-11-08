#if os(iOS)
@testable import FestivalCore
import Testing
import UIKit
@testable import FestivalUI

extension UKFoundationTests {
    @MainActor
    struct UKRouteArchitectureTests {
        private struct OfflineTransport: HTTPTransport {
            func send(_ request: URLRequest) async throws -> HTTPResult {
                throw URLError(.notConnectedToInternet)
            }
        }

        private func context() throws -> UKContext {
            let api = try FestivalAPI(transport: OfflineTransport())
            return UKContext(session: FestivalSession(factory: { api }))
        }

        @Test
        func everySectionUsesAnExplicitScreenAndRealPageBody() throws {
            let context = try context()
            for section in FestivalSection.allCases {
                let controller = UKRouteDestination.root(for: section, context: context)
                #expect(!(controller is UKPlaceholderViewController), "Unimplemented root \(section)")
                #expect(controller is UKScreenViewController, "Missing lifecycle owner for \(section)")
                controller.loadViewIfNeeded()
                if let page = controller as? UKPageViewController {
                    #expect(!page.pageContainment.contentView.subviews.isEmpty, "Unowned body for \(section)")
                }
            }
        }

        @Test
        func everyActiveRouteAndSettingsTopicUsesTheSharedScreenArchitecture() throws {
            let context = try context()
            let song = Song(
                songId: "fixture-pulse", title: "Fixture Pulse", artist: "Synthetic Quartet", album: nil,
                year: 2026, durationSeconds: 180, albumArt: nil, difficulty: nil,
                pathArtifactGenerationId: nil, sig: nil, maxScores: nil, doubleBassSupported: nil
            )
            let combo = try #require(RankingCombo(instruments: [.lead, .bass]))
            let scope = RivalScope.song(instruments: [Instrument.lead.rawValue])
            let routes: [AppRoute] = [
                .songDetail(song), .songLeaderboard(song, .lead, 1),
                .songBandLeaderboard(song, bandType: BandType.duets.rawValue),
                .playerHistory(song, .lead),
                .player(accountId: "fixture-player-1", displayName: "Fixture Player 1"),
                .playerBands(accountId: "fixture-player-1", displayName: "Fixture Player 1"),
                .bands, .band(bandId: "fixture-band", name: "Fixture Band"),
                .leaderboards, .fullRankings(instrument: .lead, rankBy: "totalscore"),
                .fullComboRankings(combo: combo, rankBy: "totalscore"),
                .bandRankings(bandType: BandType.duets.rawValue),
                .rivals, .allRivals(scope: scope),
                .rivalDetail(rivalId: "fixture-player-2", name: "Fixture Player 2", scope: scope),
                .rivalry(rivalId: "fixture-player-2", mode: "ahead", name: "Fixture Player 2", scope: scope),
                .statistics, .suggestions, .compete, .shop, .licenses,
            ] + SettingsTopic.allCases.map(AppRoute.settingsTopic)

            for route in routes {
                let controller = UKRouteDestination.make(route, context: context)
                #expect(!(controller is UKPlaceholderViewController), "Unimplemented route \(route)")
                #expect(controller is UKScreenViewController, "Missing lifecycle owner for \(route)")
                #expect(controller.ukRoute == route)
                controller.loadViewIfNeeded()
                if let page = controller as? UKPageViewController {
                    #expect(!page.pageContainment.contentView.subviews.isEmpty, "Unowned body for \(route)")
                }
            }
        }
    }
}
#endif
