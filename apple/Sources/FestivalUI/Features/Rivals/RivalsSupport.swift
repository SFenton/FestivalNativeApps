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
                    pill(count: rival.behindCount, label: "ahead", tint: BrandTokens.statusGreen)
                    pill(count: rival.aheadCount, label: "behind", tint: BrandTokens.statusRed)
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

    @ViewBuilder
    private func pill(count: Int, label: String, tint: Color) -> some View {
        Text("\(count) \(label)")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(RivalStatusText.readable(tint))
            .background(tint.opacity(0.16), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.4), lineWidth: 1))
    }
}

/// "View All Rivals" link below a rivals preview card (#41): the shared
/// ``PurpleActionLink`` that Rival Detail's category cards and "View Full Leaderboard"
/// also draw, sitting under the card rather than inside it, like the web's shared
/// `viewAllButton`.
struct RivalsViewAllButton: View {
    /// Full rivals list to push.
    let route: AppRoute
    /// Per-section `…view-all` accessibility identifier.
    let identifier: String

    var body: some View {
        PurpleActionLink(title: "View All Rivals", route: route, identifier: identifier)
    }
}

// MARK: - Rival song row content

/// Flat row content comparing one shared song between the player and a rival.
struct RivalSongRowContent: View {
    let song: RivalSongComparison
    let playerName: String
    let rivalName: String

    private var instrument: Instrument? { Instrument(rawValue: song.instrument) }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Rank comparison layout: a row, or a column at accessibility sizes.
    private var comparisonLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(spacing: 4))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let instrument {
                InstrumentIcon(instrument, size: 22)
            }
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
                // One line normally; at accessibility sizes each part gets its own
                // wrapping line (the AX5 audit read "#12 Fixt… vs #13 u…").
                comparisonLayout {
                    Text("#\(song.userRank) \(playerName)")
                    Text("vs")
                        .foregroundStyle(FestivalText.primary)
                    Text("#\(song.rivalRank) \(rivalName)")
                }
                .font(.caption2)
                .foregroundStyle(FestivalText.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }
            Spacer(minLength: 8)
            deltaBadge
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(song.title ?? song.songId), you rank \(song.userRank), "
            + "\(rivalName) ranks \(song.rivalRank)"
        )
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
