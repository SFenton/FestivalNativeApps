import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - BandsScreen

/// `/bands` — band lookup landing page.
///
/// Band search by member name lives in global search's Bands scope (issue #320, web
/// `SearchModal`). This screen offers the selected player's own bands and links into
/// the public Band Rankings boards.
struct BandsScreen: View {
    let session: FestivalSession
    @Environment(\.deviceLayout) private var layout

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
                                Image(systemName: "chevron.forward")
                                    .foregroundStyle(FestivalText.deemphasized)
                            }
                            .contentShape(Rectangle())
                        }
                        #if os(macOS)
                        // A row, not the Mac's default bordered push button.
                        .buttonStyle(FestivalRowPrimitiveButtonStyle(cornerRadius: 8))
                        #endif
                        .accessibilityIdentifier("fst.bands.your-bands")
                    }
                    .festivalFadeIn(isLoaded: true, index: 0)
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
                                Image(systemName: "chevron.forward")
                                    .foregroundStyle(FestivalText.deemphasized)
                            }
                            .contentShape(Rectangle())
                        }
                        #if os(macOS)
                        .buttonStyle(FestivalRowPrimitiveButtonStyle(cornerRadius: 8))
                        #endif
                        .accessibilityIdentifier("fst.bands.rankings.\(bandType.rawValue)")
                    }
                }
                .festivalFadeIn(isLoaded: true, index: 1)
                FestivalFootnote("To find a band by a member's name, use Search.")
                .padding(.horizontal, 4)
                .festivalFadeIn(isLoaded: true, index: 2)
            }
            // Label-and-chevron rows and a footnote: cap the line length at regular width
            // like Settings and Licenses (iPhone Duo inner display: ~850 pt rows before).
            .modifier(ReadableWidthContainer(isRegularWidth: layout.widthClass == .regular))
            .padding(16)
            // A scroll while the cards stagger in fades the rest in together (#323).
            .festivalFadeInScope()
        }
        .festivalBackground(.carousel, session: session)
        .festivalNavigationTitle("Bands")
        .accessibilityIdentifier("fst.bands.screen")
    }
}
