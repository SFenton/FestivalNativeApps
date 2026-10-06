import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - In-page song header text

/// The text column of every in-page song header (Song Details hero, and through
/// ``SongHeaderRow`` the Song Leaderboard and Band Song Leaderboard):
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
    private let onTitleBottomChange: ((CGFloat) -> Void)?
    private let details: Details

    /// Create a song header's text column.
    ///
    /// - Parameters:
    ///   - title: Song title (VoiceOver reads it in full).
    ///   - artist: Artist line.
    ///   - titleFont: The page's title font (Song Details `.title.bold()`, Song
    ///     Leaderboard `.title3.bold()`).
    ///   - spacing: Space between lines.
    ///   - onTitleBottomChange: Called with the title's bottom edge in the scroll
    ///     content (``SwiftUI/View/songHeaderContentSpace()``), the threshold of
    ///     ``SwiftUI/View/songHeaderScrollAway(headerBottom:legacy:action:)`` for a
    ///     pinned bar title.
    ///   - details: Lines under the artist (year, instrument and entry total).
    init(
        title: String, artist: String, titleFont: Font, spacing: CGFloat,
        onTitleBottomChange: ((CGFloat) -> Void)? = nil,
        @ViewBuilder details: () -> Details
    ) {
        self.title = title
        self.artist = artist
        self.titleFont = titleFont
        self.spacing = spacing
        self.onTitleBottomChange = onTitleBottomChange
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

    /// The marquee title, reporting its bottom edge in the scroll content if asked to.
    ///
    /// Content coordinates, not the scroll view's: those move whenever the bar lays out
    /// again, and the bar re-laid out around the pinned title it had just shown, which
    /// hid it again in a loop that hung Song Details (#315).
    @ViewBuilder private var titleLine: some View {
        let line = MarqueeText(title, font: titleFont)
        if let onTitleBottomChange {
            line.onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .named(SongHeaderScrollAway.contentSpace)).maxY
            } action: { bottom in
                onTitleBottomChange(bottom)
            }
        } else {
            line
        }
    }
}

// MARK: - Leaderboard song header row

/// The in-page song header of a song leaderboard (Song Leaderboard, Band Song
/// Leaderboard): 80 pt album art beside ``SongHeaderText`` (title, artist and the
/// board's detail line), like the web's `SongInfoHeader` that both web boards share
/// (pattern `song-header` R1–R5, issue #315).
///
/// It sits at the top of the board's scrolling content with no card behind it (the
/// dimmed song backdrop keeps it legible) and reports its height, so the board's
/// scroll view can tell when it has passed under the bar
/// (``SwiftUI/View/songHeaderScrollAway(headerBottom:legacy:action:)``) and show
/// ``SongBarTitleToolbarItem`` instead. VoiceOver reads it as one heading: title,
/// artist, then the details.
struct SongHeaderRow<Details: View>: View {
    private let song: Song
    private let session: FestivalSession
    private let onHeightChange: ((CGFloat) -> Void)?
    private let details: Details

    /// Create a leaderboard's song header.
    ///
    /// - Parameters:
    ///   - song: The board's song.
    ///   - session: Shared session (artwork cache).
    ///   - onHeightChange: Called with the header's laid-out height, for the board's
    ///     ``SongHeaderScrollAway`` threshold; nil when the board measures its padded
    ///     header itself.
    ///   - details: Lines under the artist (instrument or band size, entry total).
    init(
        song: Song, session: FestivalSession,
        onHeightChange: ((CGFloat) -> Void)? = nil,
        @ViewBuilder details: () -> Details
    ) {
        self.song = song
        self.session = session
        self.onHeightChange = onHeightChange
        self.details = details()
    }

    var body: some View {
        HStack(spacing: 12) {
            ArtworkTile(raw: song.albumArt, session: session, size: 80)
                .id(song.albumArt)
                .accessibilityHidden(true)
            SongHeaderText(title: song.title, artist: song.artist, titleFont: .title3.bold(), spacing: 4) {
                details
            }
        }
        .foregroundStyle(FestivalText.primary)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            onHeightChange?(height)
        }
    }
}

// MARK: - Scrolled-away policy

/// When a board's ``SongHeaderRow`` has scrolled under the navigation bar, read from
/// the board's scroll offset rather than from the header itself: a `List` (the Song
/// Leaderboard) recycles the header's row as it leaves the screen, so a geometry
/// observer on the header stopped reporting before the header passed the bar, and the
/// pinned bar title never appeared (issue #315).
enum SongHeaderScrollAway {
    /// The coordinate space of a song page's scroll content
    /// (``SwiftUI/View/songHeaderContentSpace()``).
    static let contentSpace = "fst.song-header.content"

    /// Whether the header has scrolled away: the content has scrolled at least as far
    /// as the header's bottom edge, so that edge sits at or above the bar's lower edge
    /// (Song Details passes its hero title's bottom edge instead).
    ///
    /// - Parameters:
    ///   - offset: Distance scrolled from the resting top
    ///     (``PlatformScrollObserver/Reading/offset``).
    ///   - headerBottom: The header's bottom edge in the scroll content (space above it
    ///     plus its height); 0 or less before it has been measured.
    /// - Returns: True when the bar should show the song title.
    static func isHidden(offset: CGFloat, headerBottom: CGFloat) -> Bool {
        headerBottom > 0 && offset.isFinite && offset >= headerBottom
    }
}

extension View {
    /// Names this scroll content's coordinate space for ``SongHeaderText``'s
    /// `onTitleBottomChange`. Apply it to the content's outermost view, so 0 is the
    /// content's top.
    ///
    /// - Returns: The content, with its coordinate space named.
    func songHeaderContentSpace() -> some View {
        coordinateSpace(.named(SongHeaderScrollAway.contentSpace))
    }

    /// Reports whether the ``SongHeaderRow`` at the top of this scroll view's content
    /// has scrolled under the bar (``SongHeaderScrollAway``), on every supported system
    /// (``SwiftUI/View/onScrollEdgeReading(legacy:_:action:)``). Apply it to the board's
    /// `List` or `ScrollView`.
    ///
    /// - Parameters:
    ///   - headerBottom: The header's bottom edge in the scroll content.
    ///   - legacy: Read the platform scroll view (iOS 17 / macOS 14 path); tests set it.
    ///   - action: Receives each change, on the main actor.
    /// - Returns: The scroll view, observed.
    func songHeaderScrollAway(
        headerBottom: CGFloat, legacy: Bool = ScrollEdgeTracking.usesLegacyPath,
        action: @escaping (Bool) -> Void
    ) -> some View {
        modifier(SongHeaderScrollAwayReader(headerBottom: headerBottom, legacy: legacy, action: action))
    }
}

/// The modifier behind ``SwiftUI/View/songHeaderScrollAway(headerBottom:legacy:action:)``.
///
/// The threshold lives in a reference the reading's transform reads, because the
/// platform-scroll-view path keeps the transform it was first given: a captured
/// `headerBottom` would stay at its unmeasured 0 there.
private struct SongHeaderScrollAwayReader: ViewModifier {
    let headerBottom: CGFloat
    let legacy: Bool
    let action: (Bool) -> Void
    @State private var threshold = Threshold()

    /// The latest header bottom; never observed by SwiftUI.
    private final class Threshold {
        var headerBottom: CGFloat = 0
    }

    func body(content: Content) -> some View {
        let threshold = threshold
        content
            .onScrollEdgeReading(legacy: legacy) { reading in
                SongHeaderScrollAway.isHidden(offset: reading.offset, headerBottom: threshold.headerBottom)
            } action: { hidden in
                action(hidden)
            }
            .onChange(of: headerBottom, initial: true) { _, bottom in
                threshold.headerBottom = bottom
            }
    }
}

// MARK: - Pinned bar title

/// The bar's principal item on a song page (Song Details and both song leaderboards):
/// ``SongBarTitle`` while the page's song header is scrolled away, otherwise an empty,
/// unspoken placeholder (pattern `song-header` R4).
///
/// The title is built only once the header has scrolled away: a hidden (opacity 0) copy
/// was still audited, and its fixed-size icon failed Dynamic Type. The placeholder holds
/// the slot meanwhile: an empty principal item let the bar fall back to the page's
/// `navigationTitle`, which then showed above the in-page header (issue #93). It is a
/// point, not a hidden copy of the title: a hidden full-length title beside the
/// marquee kept the bar re-sizing its title slot and hung Song Details (#315).
///
/// iOS and iPadOS only: a Mac toolbar gives a centred item its ideal width and moves
/// trailing actions into overflow to make room (HIG Toolbars: trailing items "remain
/// visible at every window size"), so the Mac keeps its leading window title, as Song
/// Details and Full Rankings do.
struct SongBarTitleToolbarItem: ToolbarContent {
    let song: Song
    let session: FestivalSession
    /// The caption under the title (the board's instrument or band size); none on
    /// Song Details.
    let caption: String?
    /// Whether the in-page header has scrolled under the bar.
    let isShown: Bool
    /// Accessibility identifier of the shown title.
    let identifier: String

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if isShown {
                SongBarTitle(song: song, session: session, caption: caption)
                    .transition(.opacity)
                    .accessibilityIdentifier(identifier)
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// The compact song title a song page shows in its navigation bar once the in-page
/// header has scrolled away: 28 pt art, the title on one marqueeing line and an
/// optional caption (the Song Leaderboard's instrument), like the web's collapsed
/// `SongInfoHeader` (pattern `song-header` R4).
///
/// It takes all the width the bar offers its title slot, between the back button and
/// the bar's actions (no fixed cap), so a long title scrolls only when that space runs
/// out; a short title stays centred. Actions that no longer fit still move to the
/// bar's system overflow menu. The title stays on one line at every text size (a bar
/// caps its text), and a long press shows it in the Large Content Viewer, as system
/// bar titles do. Callers build it only while the in-page header is hidden, so
/// VoiceOver reads the title once.
struct SongBarTitle: View {
    let song: Song
    let session: FestivalSession
    var caption: String?

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
        .environment(\.marqueeWrapsAtAccessibilitySizes, false)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityShowsLargeContentViewer()
    }
}
