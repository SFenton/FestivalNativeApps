import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Song leaderboard header

/// The board line under a song leaderboard header's artist: the board's name (an
/// instrument or a band size), with the entry total when the service asks for totals.
enum SongLeaderboardBoardLine {
    /// Compose the board line.
    ///
    /// Web `SongInfoHeader` `subtitle2`: the band page reads
    /// `songBandLeaderboard.subtitle` ("{type} • {count} entries") only when
    /// `showLeaderboardEntryTotals` is true; natives use the solo board's " · ".
    ///
    /// - Parameters:
    ///   - name: Board name, e.g. "Lead" or "Duos".
    ///   - totalEntries: Ranked entries on the board.
    ///   - showsTotals: The response's `showLeaderboardEntryTotals`.
    /// - Returns: "Duos · 1,234 entries" with totals, otherwise "Duos".
    static func text(name: String, totalEntries: Int, showsTotals: Bool?) -> String {
        guard showsTotals == true else { return name }
        return "\(name) · \(totalEntries.formatted()) entries"
    }
}

/// The song header at the top of a song leaderboard (solo instrument or band size):
/// art, title, artist and the board line, scrolling with the rows on the song's dimmed
/// backdrop with no card behind it (operator batch 7.2, issues #293 and #317). It
/// reports when it has scrolled under the bar so ``SongLeaderboardPinnedTitle`` can
/// take over (``SongDetailPinnedTitlePolicy``).
///
/// One header for every song leaderboard, like the web `SongInfoHeader` that the solo
/// `LeaderboardPage` and `SongBandLeaderboardPage` share.
struct SongLeaderboardHeader<Icon: View>: View {
    let song: Song
    let session: FestivalSession
    /// The board line (``SongLeaderboardBoardLine``).
    let boardLine: String
    /// Identifier prefix of the page, e.g. `fst.song-leaderboard`.
    let idPrefix: String
    /// Set while the header is under the bar.
    @Binding var hidden: Bool
    /// Board icon before the board line (the instrument); empty for band sizes, which the
    /// web header shows without an icon.
    @ViewBuilder let icon: () -> Icon

    /// Create the header.
    ///
    /// - Parameters:
    ///   - song: Song of the board.
    ///   - session: Shared session, for the artwork cache.
    ///   - boardLine: The line under the artist.
    ///   - idPrefix: Identifier prefix of the page.
    ///   - hidden: Set while the header is under the bar.
    ///   - icon: Board icon before the board line.
    init(
        song: Song, session: FestivalSession, boardLine: String, idPrefix: String,
        hidden: Binding<Bool>, @ViewBuilder icon: @escaping () -> Icon
    ) {
        self.song = song
        self.session = session
        self.boardLine = boardLine
        self.idPrefix = idPrefix
        _hidden = hidden
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 12) {
            ArtworkTile(raw: song.albumArt, session: session, size: 80)
                .id(song.albumArt)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.title3.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text(song.artist)
                    .foregroundStyle(FestivalText.primary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    icon()
                        .accessibilityHidden(true)
                    Text(boardLine)
                        .foregroundStyle(FestivalText.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
        .foregroundStyle(FestivalText.primary)
        // No card or band behind the header, like Song Detail's (operator batch 7.2,
        // issue #293): the shared dimmed song backdrop keeps the text legible.
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("\(idPrefix).header")
        .onGeometryChange(for: Bool.self) { proxy in
            SongDetailPinnedTitlePolicy.isHeroHidden(titleMaxY: proxy.frame(in: .scrollView).maxY)
        } action: { isHidden in
            hidden = isHidden
        }
    }
}

extension SongLeaderboardHeader where Icon == EmptyView {
    /// Create a header without a board icon (band sizes).
    ///
    /// - Parameters:
    ///   - song: Song of the board.
    ///   - session: Shared session, for the artwork cache.
    ///   - boardLine: The line under the artist.
    ///   - idPrefix: Identifier prefix of the page.
    ///   - hidden: Set while the header is under the bar.
    init(song: Song, session: FestivalSession, boardLine: String, idPrefix: String, hidden: Binding<Bool>) {
        self.init(
            song: song, session: session, boardLine: boardLine, idPrefix: idPrefix, hidden: hidden
        ) { EmptyView() }
    }
}

// MARK: - Pinned bar title

/// The song leaderboard's bar title: empty until ``SongLeaderboardHeader`` scrolls away,
/// then 28 pt art, the song title and the board name, like Song Detail (operator batch
/// 7.2, issue #317).
struct SongLeaderboardPinnedTitle: ToolbarContent {
    let song: Song
    let session: FestivalSession
    /// Board name under the title, e.g. "Lead" or "Duos".
    let boardName: String
    /// Identifier prefix of the page, e.g. `fst.song-leaderboard`.
    let idPrefix: String
    /// Whether the in-page header is under the bar.
    let headerHidden: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            // Built only once the header has scrolled away: a hidden (opacity 0) copy
            // was still audited, and its fixed-size icon failed Dynamic Type. Until then
            // an empty, unspoken placeholder holds the slot: an empty principal item let
            // the bar fall back to `navigationTitle`, so the title showed above the
            // in-page header before any scroll (issue #93).
            if headerHidden {
                HStack(spacing: 8) {
                    ArtworkTile(raw: song.albumArt, session: session, size: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        MarqueeText(song.title)
                            .font(.headline)
                            .foregroundStyle(FestivalText.primary)
                            .lineLimit(1)
                        Text(boardName)
                            .font(.caption)
                            .foregroundStyle(FestivalText.primary)
                    }
                }
                .frame(maxWidth: 240)
                // A bar title stays on one line at every text size.
                .environment(\.marqueeWrapsAtAccessibilitySizes, false)
                .transition(.opacity)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("\(idPrefix).pinned-title")
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityHidden(true)
            }
        }
    }
}
