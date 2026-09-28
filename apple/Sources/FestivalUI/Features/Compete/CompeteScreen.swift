import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - CompeteScreen

/// `/compete` — phone hub combining Leaderboards and Rivals; this is the phone
/// tab shown once a player is selected (see `FestivalRootView`).
///
/// The web's `CompetePage` shows live Top-10 leaderboard previews per ranking
/// scope alongside rival previews. The Leaderboards half here needs the
/// Leaderboards lane's rankings Core API (not yet landed and out of this lane's
/// ownership), so its section links straight to `AppRoute.leaderboards` /
/// `AppRoute.fullRankings` per instrument rather than fabricating preview rows;
/// the Rivals half is fully live. See `.agents/pages/compete/ios.md`.
struct CompeteScreen: View {
    let session: FestivalSession
    @Environment(\.openProfile) private var openProfile
    private var visible = VisibleInstrumentsReader()

    /// Create the screen.
    ///
    /// - Parameter session: Shared app session (API client, selected profile, caches).
    init(session: FestivalSession) {
        self.session = session
    }

    var body: some View {
        Group {
            if session.selectedPlayer == nil {
                RivalsChooseProfileState { openProfile() }
            } else {
                hub
            }
        }
        .navigationTitle("Compete")
        .festivalBackground(.carousel, session: session)
    }

    @ViewBuilder private var hub: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                leaderboardsSection
                rivalsSection
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: Leaderboards

    private var leaderboardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FestivalSectionHeader("Leaderboards")
                .padding(.horizontal, 16)
            FestivalGlassSection {
                NavigationLink(value: AppRoute.leaderboards) {
                    HStack {
                        Label("Leaderboards Overview", systemImage: "list.number")
                            .foregroundStyle(BrandTokens.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BrandTokens.textMuted)
                    }
                    .contentShape(Rectangle())
                }
                ForEach(visible.instruments) { instrument in
                    NavigationLink(
                        value: AppRoute.fullRankings(instrument: instrument, rankBy: "totalscore")
                    ) {
                        HStack(spacing: 12) {
                            InstrumentIcon(instrument, size: 20)
                            Text(instrument.label)
                                .foregroundStyle(BrandTokens.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BrandTokens.textMuted)
                        }
                        .contentShape(Rectangle())
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: Rivals

    private var rivalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FestivalSectionHeader("Rivals")
                .padding(.horizontal, 16)
            if visible.instruments.isEmpty {
                FestivalFootnote("Enable at least one instrument in Settings to see rivals.")
                    .padding(.horizontal, 16)
            } else {
                ForEach(visible.instruments) { instrument in
                    RivalInstrumentSongSection(session: session, instrument: instrument)
                }
            }
        }
    }
}
