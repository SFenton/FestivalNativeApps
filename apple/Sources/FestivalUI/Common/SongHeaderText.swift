import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - In-page song header text

/// The text column of every in-page song header (Song Details hero, Song Leaderboard):
/// the song title and artist, each on one line that fills the width beside the album
/// art and scrolls with ``MarqueeText`` when it does not fit, like the web's shared
/// `SongInfoHeader` (pattern `song-header` R1–R3, issue #315).
///
/// The column takes all the width its row offers (`maxWidth: .infinity`), so a title
/// never wraps early beside empty space; the lines scroll in lockstep
/// (``SwiftUI/View/marqueeSync(gap:)``, web `useMarqueeSync`). ``MarqueeText`` keeps
/// its rules: short lines stay still, Reduce Motion tail-truncates without animation,
/// and accessibility text sizes wrap onto as many lines as needed (HIG Typography).
struct SongHeaderText<Details: View>: View {
    private let title: String
    private let artist: String
    private let titleFont: Font
    private let spacing: CGFloat
    private let onTitleScrolledAway: ((Bool) -> Void)?
    private let details: Details

    /// Create a song header's text column.
    ///
    /// - Parameters:
    ///   - title: Song title (VoiceOver reads it in full).
    ///   - artist: Artist line.
    ///   - titleFont: The page's title font (Song Details `.title.bold()`, Song
    ///     Leaderboard `.title3.bold()`).
    ///   - spacing: Space between lines.
    ///   - onTitleScrolledAway: Called with whether the title's bottom edge has passed
    ///     under the bar (``SongDetailPinnedTitlePolicy``), for a pinned bar title.
    ///   - details: Lines under the artist (year, instrument and entry total).
    init(
        title: String, artist: String, titleFont: Font, spacing: CGFloat,
        onTitleScrolledAway: ((Bool) -> Void)? = nil,
        @ViewBuilder details: () -> Details
    ) {
        self.title = title
        self.artist = artist
        self.titleFont = titleFont
        self.spacing = spacing
        self.onTitleScrolledAway = onTitleScrolledAway
        self.details = details()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            titleLine
            MarqueeText(artist, font: .body)
                .foregroundStyle(FestivalText.primary)
            details
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .marqueeSync()
    }

    /// The marquee title, reporting when it scrolls under the bar if asked to.
    @ViewBuilder private var titleLine: some View {
        let line = MarqueeText(title, font: titleFont)
        if let onTitleScrolledAway {
            line.onGeometryChange(for: Bool.self) { proxy in
                SongDetailPinnedTitlePolicy.isHeroHidden(titleMaxY: proxy.frame(in: .scrollView).maxY)
            } action: { hidden in
                onTitleScrolledAway(hidden)
            }
        } else {
            line
        }
    }
}

// MARK: - Pinned bar title

/// The compact song title a song page shows in its navigation bar once the in-page
/// header has scrolled away: 28 pt art, the title on one marqueeing line and an
/// optional caption (the Song Leaderboard's instrument), like the web's collapsed
/// `SongInfoHeader` (pattern `song-header` R4).
///
/// The title stays on one line at every text size (a bar caps its text), and a long
/// press shows it in the Large Content Viewer, as system bar titles do. Callers build
/// it only while the in-page header is hidden, so VoiceOver reads the title once.
struct SongBarTitle: View {
    /// Widest the bar title may grow; narrower bars offer less and it marquees there.
    static let maxWidth: CGFloat = 240

    let song: Song
    let session: FestivalSession
    var caption: String?

    /// An invisible, unspoken stand-in as wide as the bar title (art and gap plus the
    /// one-line title), so a bar that sizes its title slot by content keeps that width
    /// before the title appears and does not jump.
    ///
    /// - Parameter title: Song title.
    /// - Returns: A hidden one-line placeholder.
    static func layoutPlaceholder(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .lineLimit(1)
            .padding(.leading, 36)
            .hidden()
    }

    var body: some View {
        HStack(spacing: 8) {
            ArtworkTile(raw: song.albumArt, session: session, size: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                MarqueeText(song.title, font: .headline)
                    .foregroundStyle(FestivalText.primary)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(FestivalText.primary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: Self.maxWidth)
        .environment(\.marqueeWrapsAtAccessibilitySizes, false)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityShowsLargeContentViewer()
    }
}
