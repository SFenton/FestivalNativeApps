import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - BandsScreen

/// `/bands` — band lookup landing page.
///
/// The web client's `BandLookupPage` searches for a band by member name via
/// `GET /api/bands/search`. That endpoint's missing-projection fallback deletes
/// and rebuilds membership rows (`GlobalLeaderboardPersistence.cs:3954-3971`,
/// `BandLeaderboardPersistence.cs:905-947`) — a write side effect from a GET — so
/// it is on this app's blocked list (`.agents/platforms/service-safety.md`) and is
/// never called here. This screen instead offers what remains safely reachable:
/// the selected player's own bands and links into the public Band Rankings boards.
struct BandsScreen: View {
    let session: FestivalSession

    /// Create the screen.
    ///
    /// - Parameter session: Shared app session (API client, selected profile, caches).
    init(session: FestivalSession) {
        self.session = session
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let player = session.selectedPlayer {
                    FestivalGlassSection("Your Bands") {
                        NavigationLink(
                            value: AppRoute.playerBands(
                                accountId: player.accountId, displayName: player.displayName
                            )
                        ) {
                            HStack {
                                Text("View \(player.displayName)'s Bands")
                                    .foregroundStyle(BrandTokens.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(FestivalText.deemphasized)
                            }
                        }
                        .accessibilityIdentifier("fst.bands.your-bands")
                    }
                }
                FestivalGlassSection(
                    "Band Rankings",
                    subtitle: "Public rankings by band size."
                ) {
                    ForEach(BandType.allCases) { bandType in
                        NavigationLink(value: AppRoute.bandRankings(bandType: bandType.rawValue)) {
                            HStack {
                                Text(bandType.label)
                                    .foregroundStyle(BrandTokens.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(FestivalText.deemphasized)
                            }
                        }
                        .accessibilityIdentifier("fst.bands.rankings.\(bandType.rawValue)")
                    }
                }
                FestivalFootnote(
                    "Band lookup by name isn't available yet: the service's search "
                        + "endpoint can register band data as a side effect of a search "
                        + "read, so this app doesn't call it. Browse Band Rankings or a "
                        + "selected player's own bands instead."
                )
                .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .festivalBackground(.carousel, session: session)
        .navigationTitle("Bands")
        .accessibilityIdentifier("fst.bands.screen")
    }
}
