import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Load state

/// Explicit loading/loaded/failed state for one independently fetched Rivals section.
///
/// Each instrument/scope section owns its own instance (rather than the whole
/// page sharing one), mirroring the web's per-instrument `useQueries` — one
/// slow or failed instrument never blocks the others from rendering.
enum RivalsLoadState<Value> {
    case loading
    case loaded(Value)
    case failed(ServiceIssue)
}

// MARK: - Visible instruments

/// Reads the same nine per-instrument `@AppStorage` Settings switches as
/// `FestivalRootView`/`SettingsScreen` (`fst.settings.show*`), so Rivals/Compete
/// hide instruments the way Songs and the tab bar already do. Duplicated rather
/// than shared because those keys live in Lane A/Settings-owned files this lane
/// does not edit; the storage keys themselves are the shared contract.
struct VisibleInstrumentsReader: DynamicProperty {
    @AppStorage("fst.settings.showLead") private var showLead = true
    @AppStorage("fst.settings.showBass") private var showBass = true
    @AppStorage("fst.settings.showDrums") private var showDrums = true
    @AppStorage("fst.settings.showVocals") private var showVocals = true
    @AppStorage("fst.settings.showProLead") private var showProLead = true
    @AppStorage("fst.settings.showProBass") private var showProBass = true
    @AppStorage("fst.settings.showKaraoke") private var showKaraoke = true
    @AppStorage("fst.settings.showProCymbals") private var showProCymbals = true
    @AppStorage("fst.settings.showProDrums") private var showProDrums = true

    /// Saved-visible charts in the source's stable nine-instrument order.
    var instruments: [Instrument] {
        let flags: [(Instrument, Bool)] = [
            (.lead, showLead), (.bass, showBass), (.drums, showDrums), (.vocals, showVocals),
            (.proLead, showProLead), (.proBass, showProBass), (.karaoke, showKaraoke),
            (.proCymbals, showProCymbals), (.proDrums, showProDrums),
        ]
        return flags.filter(\.1).map(\.0)
    }
}

// MARK: - No player selected

/// Shared empty state for every player-only Rivals/Compete surface.
struct RivalsChooseProfileState: View {
    let action: () -> Void

    var body: some View {
        FestivalEmptyState(
            "No Player Selected", systemImage: "person.crop.circle.badge.questionmark",
            subtitle: "Choose a profile to see your rivals.",
            accessibilityIdentifier: "fst.rivals.chooseProfile"
        ) {
            Button("Choose Profile", action: action)
                .festivalProminentButton()
        }
    }
}

// MARK: - Rival row content

/// Flat row content for one rival, meant to sit inside a `FestivalGlassSection`
/// card (per `.agents/design/apple/liquid-glass.md`: Rivals groups get one material
/// card per group, with flat rows inside — never a card per row).
///
/// Field placement mirrors the web's `RivalRow.tsx`, including its slightly
/// surprising pairing: the "ahead" pill shows `behindCount` and the "behind"
/// pill shows `aheadCount` (both counts are from the rival's own perspective in
/// the wire payload). Unlike the web, it omits the trailing "N shared" count,
/// which is always ahead + behind (issue #40).
struct RivalRowContent<Rival: RivalRowDisplayable>: View {
    let rival: Rival
    let direction: RivalDirection

    private var name: String { rival.displayName ?? "Unknown Player" }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(direction == .below ? BrandTokens.statusGreen : BrandTokens.statusRed)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                MarqueeText(name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(BrandTokens.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    RivalStatusPill("\(rival.behindCount) ahead", tint: BrandTokens.statusGreen)
                    RivalStatusPill("\(rival.aheadCount) behind", tint: BrandTokens.statusRed)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(FestivalText.deemphasized)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(name), \(rival.behindCount) songs ahead, \(rival.aheadCount) songs behind"
        )
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Rival status pill

/// The red/green capsule every Rivals card draws its standing in (pattern `rival-rows` R2):
/// the hub rows' "N ahead" / "N behind" counts and the song rows' "#rank Name" sides.
///
/// The text always carries the meaning, so colour is never the only signal (HIG Color:
/// "Avoid relying solely on color"); red text uses ``RivalStatusText/readable(_:)``.
/// Line limits come from the caller's environment.
struct RivalStatusPill: View {
    /// Visible label.
    let text: String
    /// Status tint: `BrandTokens.statusGreen`, `BrandTokens.statusRed` or a neutral text colour.
    let tint: Color

    /// Create a pill.
    ///
    /// - Parameters:
    ///   - text: Visible label.
    ///   - tint: Status tint for the fill, stroke and (readable) text.
    init(_ text: String, tint: Color) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(RivalStatusText.readable(tint))
            .background(tint.opacity(0.16), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.4), lineWidth: 1))
    }
}

// MARK: - Rival song standing

/// Who leads one shared song, from ``RivalSongComparison/rankDelta`` (positive: the player
/// has the better rank).
enum RivalSongStanding: Equatable {
    case playerAhead
    case rivalAhead
    case tied

    /// Classify a rank delta.
    ///
    /// - Parameter rankDelta: The comparison's `rankDelta`.
    init(rankDelta: Int) {
        self = rankDelta > 0 ? .playerAhead : (rankDelta < 0 ? .rivalAhead : .tied)
    }

    /// Pill tint for the player's side: green when ahead, red when behind, neutral when tied.
    var playerTint: Color {
        switch self {
        case .playerAhead: BrandTokens.statusGreen
        case .rivalAhead: BrandTokens.statusRed
        case .tied: FestivalText.primary
        }
    }

    /// Pill tint for the rival's side, the mirror of ``playerTint``.
    var rivalTint: Color {
        switch self {
        case .playerAhead: BrandTokens.statusRed
        case .rivalAhead: BrandTokens.statusGreen
        case .tied: FestivalText.primary
        }
    }

    /// Spoken leader phrase for the row's VoiceOver label.
    ///
    /// - Parameter rivalName: Rival display name.
    /// - Returns: "you lead", "<rival> leads" or "tied".
    func spokenLeader(rivalName: String) -> String {
        switch self {
        case .playerAhead: "you lead"
        case .rivalAhead: "\(rivalName) leads"
        case .tied: "tied"
        }
    }
}

/// "View All Rivals" link that ends a rivals preview card (#41): the shared
/// ``PurpleActionLink`` that Rival Detail's category cards and "View Full Leaderboard"
/// also draw, passed as the card's `action` so it sits inside the card after the last
/// row (#382), where the web's shared `viewAllButton` follows its rows.
struct RivalsViewAllButton: View {
    /// Full rivals list to push.
    let route: AppRoute
    /// Per-section `…view-all` accessibility identifier.
    let identifier: String
    /// Card title spoken after the label ("View All Rivals, Lead Rivals"; view-all-cta R4).
    var card: String? = nil

    var body: some View {
        PurpleActionLink(title: "View All Rivals", route: route, identifier: identifier, card: card)
    }
}

// MARK: - Rival song row content

/// Flat row content comparing one shared song between the player and a rival
/// (pattern `rival-rows`): Rival Detail category cards, Rivalry and the Duo category cards.
///
/// The leading column shows the song's album art (the shared ``ArtworkTile``), above the
/// instrument icon when there is one; the column is vertically centred, so art alone sits
/// in the middle of the row (owner, #558). The bottom line is the player's and the rival's
/// "#rank Name" as ``RivalStatusPill``s, green for the side that leads and red for the
/// side behind (agent decision #558, rival-rows R3).
struct RivalSongRowContent: View {
    /// Album art edge, the native song rows' 44 pt (Songs, Suggestions, Search).
    static let artSize: CGFloat = 44

    let song: RivalSongComparison
    /// Catalogue artwork path for the song, or nil for the placeholder.
    let albumArt: String?
    /// Shared session whose bounded artwork caches draw the art.
    let session: FestivalSession
    let playerName: String
    let rivalName: String
    /// Decoded art for hosted visual tests; nil loads `albumArt`.
    var previewArtwork: CGImage? = nil

    private var instrument: Instrument? { Instrument(rawValue: song.instrument) }
    private var standing: RivalSongStanding { RivalSongStanding(rankDelta: song.rankDelta) }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The row's single VoiceOver label: song, both ranks and who leads.
    ///
    /// - Parameters:
    ///   - song: The comparison.
    ///   - rivalName: Rival display name.
    /// - Returns: For example "Song, you rank 12, Rival ranks 13, you lead".
    static func accessibilityLabel(for song: RivalSongComparison, rivalName: String) -> String {
        "\(song.title ?? song.songId), you rank \(song.userRank), "
            + "\(rivalName) ranks \(song.rivalRank), "
            + RivalSongStanding(rankDelta: song.rankDelta).spokenLeader(rivalName: rivalName)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            leadingColumn
            VStack(alignment: .leading, spacing: 4) {
                MarqueeText(song.title ?? song.songId)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(BrandTokens.textPrimary)
                    .lineLimit(1)
                if let artist = song.artist {
                    MarqueeText(artist)
                        .font(.caption)
                        .foregroundStyle(FestivalText.primary)
                        .lineLimit(1)
                }
                standingPills
            }
            Spacer(minLength: 8)
            deltaBadge
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.accessibilityLabel(for: song, rivalName: rivalName))
    }

    /// Album art, with the instrument icon under it when the chart is known.
    private var leadingColumn: some View {
        VStack(spacing: 6) {
            ArtworkTile(raw: albumArt, session: session, size: Self.artSize, previewImage: previewArtwork)
                .id(albumArt)
                .accessibilityHidden(true)
            if let instrument {
                InstrumentIcon(instrument, size: 22)
            }
        }
    }

    /// "#rank Name" pills for both sides. One line when they fit, else one pill per line;
    /// at accessibility sizes each pill wraps instead of truncating (HIG Typography: "Keep
    /// text truncation to a minimum as font size increases").
    @ViewBuilder private var standingPills: some View {
        let player = RivalStatusPill("#\(song.userRank) \(playerName)", tint: standing.playerTint)
        let rival = RivalStatusPill("#\(song.rivalRank) \(rivalName)", tint: standing.rivalTint)
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                player.fixedSize(horizontal: false, vertical: true)
                rival.fixedSize(horizontal: false, vertical: true)
            }
            .lineLimit(nil)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { player; rival }
                VStack(alignment: .leading, spacing: 4) { player; rival }
            }
            .lineLimit(1)
        }
    }

    @ViewBuilder private var deltaBadge: some View {
        let magnitude = abs(song.rankDelta)
        let color: Color = song.rankDelta == 0
            ? FestivalText.primary
            : (song.rankDelta > 0 ? BrandTokens.statusGreen : BrandTokens.statusRed)
        VStack(spacing: 0) {
            Image(systemName: song.rankDelta == 0 ? "equal" : (song.rankDelta > 0 ? "arrow.up" : "arrow.down"))
                .font(.caption.weight(.bold))
            Text("\(magnitude)")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(RivalStatusText.readable(color))
        .frame(minWidth: 28)
    }
}

/// Text colours for the rivals status tints.
///
/// `BrandTokens.statusRed` (198, 40, 40) as caption text on the dark cards measured
/// 2.6–3.0:1 rendered on iPad (the audit's "behind" pills and rank-drop deltas), below
/// WCAG AA 4.5:1 for small text (HIG Accessibility). The red pill keeps its tinted fill
/// and stroke; only its text uses a lighter red (≈ 6.5:1). Green already passes.
enum RivalStatusText {
    /// Lighter red for text on dark surfaces.
    static let red = Color(.sRGB, red: 1.0, green: 0.45, blue: 0.45, opacity: 1)

    /// The readable text colour for a status tint.
    ///
    /// - Parameter tint: A status tint (or any other colour, returned unchanged).
    /// - Returns: ``red`` for `BrandTokens.statusRed`, else `tint`.
    static func readable(_ tint: Color) -> Color {
        tint == BrandTokens.statusRed ? red : tint
    }
}
