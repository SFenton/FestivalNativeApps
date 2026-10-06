import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Load state

/// Shared loading/loaded/failed state for every rankings surface in this feature.
enum RankLoadState<Value> {
    case loading
    case loaded(Value)
    case failed(ServiceIssue)

    /// Whether the value is still loading (drives ``FestivalReloadGate``).
    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

// MARK: - Account ranking row

/// One account-rankings row, shared by the overview cards and the full board.
///
/// A compact single-line card row (rank, name, `728 / 729`, accent-coloured value),
/// matching the web client's `RankingEntry` inside `RankingCard.tsx`: every row is
/// its own frosted card there, so each row here carries its own material card and
/// the surrounding page adds none (no card in a card).
///
/// Navigates to the viewed player's profile, matching the web client's row link
/// to `/player/:accountId` (or Statistics for the signed-in player, which native
/// resolves the same way once a selected-profile route exists). Anonymous
/// production rows (empty `accountId`) render the same content without a link.
struct AccountRankingRow: View {
    let entry: AccountRankingEntry
    let metric: RankingMetric
    /// True for the selected player's own row, whether it is highlighted in place
    /// among the top rows or shown as a separate spotlight below them — matching
    /// the web client's `isPlayer` accent treatment
    /// (`RankingCard.tsx`'s `playerEntryRow` style: a tinted fill plus border).
    var isSelected: Bool = false
    /// Draw the row as its own material card (Leaderboards, Full Rankings). Off where
    /// the row already sits inside a card (Compete previews): no card in a card.
    var cardSurface: Bool = false
    /// Wrap the row in its profile link. Off for a board's pinned footer, whose caller
    /// wraps the row in the selected-row action instead (``SelectedRowAction``, #318).
    var opensProfile: Bool = true

    private var displayName: String { Self.displayName(entry) }

    /// The name a row shows for `entry` ("Unknown User" without one).
    ///
    /// - Parameter entry: A rankings row.
    /// - Returns: The display name as drawn.
    static func displayName(_ entry: AccountRankingEntry) -> String {
        entry.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown User"
    }

    /// The profile a row opens.
    ///
    /// - Parameter entry: A rankings row with an account.
    /// - Returns: The player route.
    static func route(_ entry: AccountRankingEntry) -> AppRoute {
        .player(accountId: entry.accountId, displayName: entry.displayName)
    }

    /// Mac arrow-key rows for a board's linked rows (anonymous rows open nothing).
    ///
    /// - Parameters:
    ///   - entries: Rows in display order.
    ///   - prefix: Keeps ids unique when one page shows several boards.
    ///   - container: The lazily built card holding them, if any.
    /// - Returns: Rows with ids `prefix + entry.id`.
    static func keyRows(
        _ entries: [AccountRankingEntry], prefix: String = "", container: String? = nil
    ) -> [MacKeyRow] {
        entries.filter(\.hasAccount).map {
            MacKeyRow(id: prefix + $0.id, action: .route(route($0)), container: container)
        }
    }

    var body: some View {
        Group {
            if !opensProfile {
                // The caller's button or link is the row's action.
                rowContent
            } else if entry.hasAccount {
                ListDetailLink(
                    value: AppRoute.player(accountId: entry.accountId, displayName: entry.displayName)
                ) {
                    rowContent
                }
                .buttonStyle(.plain)
                #if os(macOS)
                .contextMenu {
                    MacPlayerRowMenu(accountId: entry.accountId, displayName: entry.displayName)
                }
                #else
                .openInNewWindowMenu(.player(accountId: entry.accountId, displayName: entry.displayName))
                #endif
            } else {
                // Anonymous production rows have no profile to open.
                rowContent
                    .accessibilityHint("Profile unavailable")
            }
        }
        .accessibilityIdentifier(opensProfile ? "fst.rankings.row.\(entry.id)" : "fst.rankings.footer-row.\(entry.id)")
        .modifier(SelectedRankAccessibilityLabel(
            isSelected: isSelected, rank: entry.rank(for: metric), name: displayName
        ))
    }

    /// The rank, name, songs and rating columns shared by linked and anonymous rows.
    private var rowContent: some View {
        let songs = entry.songsLabel(for: metric)
        return RankingRowLayout(
            rank: entry.rank(for: metric),
            name: displayName,
            songs: songs,
            spokenSongs: RankingsCountText.spokenSongs(songs, fullCombos: metric == .fcrate),
            rating: RankingFormatting.rating(entry.ratingValue(for: metric), metric: metric),
            bayesian: entry.bayesianValue(for: metric).map(RankingFormatting.bayesian),
            emphasized: isSelected,
            showsChevron: entry.hasAccount
        )
        .modifier(RankingRowSurface(isSelected: isSelected, card: cardSurface))
    }
}

// MARK: - Shared row layout

/// Compact rankings row content: `#rank`, the name, the songs column and the
/// accent-coloured value (web `RankingEntry.tsx`: `colRank`, `colName`, `colSongs`,
/// `colRating` = `Colors.accentBlue*`), on one line. Text is primary white throughout
/// (operator rule: no gray de-emphasis on these pages).
///
/// The name is a ``LeaderboardNameText``: it stays inside the name column and scrolls
/// (marquee) when it does not fit, tail-truncating under Reduce Motion (issue #292,
/// reversing batch 7.7's truncate-only rule).
///
/// Adjusted/Weighted add their Bayesian value as a second, smaller line under the
/// value (the web's compact two-row percentile layout). At accessibility Dynamic Type
/// sizes the row stacks (rank + name, then songs + value) and the name wraps instead
/// of truncating or scrolling.
///
/// Inside a fitted section the songs column shares the section's widest songs label,
/// and the section may hide it on every row to give names their room (#38,
/// `leaderboardSectionColumns(_:hidingCrowdedSongsFor:)`); VoiceOver still reads it.
struct RankingRowLayout: View {
    let rank: Int
    let name: String
    let songs: String
    let spokenSongs: String
    let rating: String
    let bayesian: String?
    /// Bold name and value for the selected player's own row (web `isPlayer`).
    var emphasized: Bool = false
    /// A trailing in-card chevron on rows that open something (operator batch 7.12).
    var showsChevron: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The section's shared rank/rating widths (web `computeRankWidth`, issue #37).
    @Environment(\.leaderboardRowColumns) private var columns
    /// Minimum rank column outside a fitted section (first-run demos), so `#1`…`#10`
    /// names still line up.
    @ScaledMetric(relativeTo: .body) private var rankWidth: CGFloat = 40

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        rankText
                        nameText
                    }
                    // Songs and value share a line when it fits; otherwise they stack and the
                    // value scales down rather than run past the row (folded Duo at AX5: a
                    // 596 pt row in a 350 pt column, under the vertical bar).
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            songsText
                            Spacer(minLength: 8)
                            ratingColumn
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            songsText
                            stackedRatingColumn
                        }
                    }
                }
            } else {
                HStack(spacing: Self.columnSpacing) {
                    LeaderboardColumnSlot(template: columns?.rankLabel) { rankText }
                        .frame(minWidth: columns == nil ? rankWidth : nil, alignment: .leading)
                    nameText
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !hidesSongs {
                        LeaderboardColumnSlot(
                            template: columns?.songsLabel, alignment: .trailing, font: Self.songsFont
                        ) {
                            songsText
                        }
                    }
                    LeaderboardColumnSlot(template: columns?.ratingLabel, alignment: .trailing) {
                        ratingColumn
                    }
                    if showsChevron {
                        Self.chevron
                    } else if columns != nil {
                        // Keep the rating column aligned with linked rows in the section.
                        Self.chevron.hidden()
                    }
                }
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, 8)
        // The web's 48 pt `entryRow`, like every other leaderboard row (issue #90).
        .frame(minHeight: LeaderboardRowMetrics.minHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .modifier(HiddenSongsAccessibility(spokenSongs: hidesSongs ? spokenSongs : nil))
    }

    /// The section hid the songs column (#38); stacked accessibility-size rows keep it.
    private var hidesSongs: Bool {
        columns?.showsSongs == false && !dynamicTypeSize.isAccessibilitySize
    }

    // MARK: Shared metrics

    /// Spacing between the row's columns.
    static let columnSpacing: CGFloat = 10
    /// Horizontal padding inside the row card.
    static let horizontalPadding: CGFloat = 14
    /// The songs played/total column's font.
    static let songsFont: Font = .subheadline

    /// The trailing disclosure chevron (operator batch 7.12).
    static var chevron: some View {
        Image(systemName: "chevron.forward")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(FestivalText.deemphasized)
            .accessibilityHidden(true)
    }

    /// A row name at its natural one-line size, in the row's font, for width probes
    /// (``RankingRowWidthProbe``); the row itself draws a ``LeaderboardNameText``.
    ///
    /// - Parameters:
    ///   - name: Display name.
    ///   - emphasized: The selected player's own row.
    /// - Returns: A one-line name.
    static func nameText(_ name: String, emphasized: Bool) -> some View {
        Text(name)
            .lineLimit(1)
            .font(LeaderboardNameText.font(emphasized: emphasized))
            .foregroundStyle(FestivalText.primary)
    }

    private var rankText: some View {
        Text("#\(rank.formatted())")
            .font(.body)
            .monospacedDigit()
            .foregroundStyle(FestivalText.primary)
            .fixedSize()
    }

    /// Scrolls when it does not fit, tail-truncating under Reduce Motion (issue #292
    /// reverses batch 7.7's truncate-only rule); wraps at accessibility sizes.
    private var nameText: some View {
        LeaderboardNameText(name: name, emphasized: emphasized)
    }

    private var songsText: some View {
        Text(songs)
            .font(Self.songsFont)
            .fontWeight(emphasized ? .bold : .regular)
            .monospacedDigit()
            .foregroundStyle(FestivalText.primary)
            .fixedSize()
            .accessibilityLabel(spokenSongs)
    }

    /// The value on its own line at accessibility sizes: one line that scales down to
    /// fit the row instead of overflowing it (digits never wrap).
    private var stackedRatingColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(rating)
                .font(.body)
                .fontWeight(emphasized ? .bold : .semibold)
                .monospacedDigit()
                .foregroundStyle(AccentText.blue)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let bayesian {
                Text(bayesian)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(FestivalText.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
    }

    private var ratingColumn: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(rating)
                .font(.body)
                .fontWeight(emphasized ? .bold : .semibold)
                .monospacedDigit()
                .foregroundStyle(AccentText.blue)
            if let bayesian {
                Text(bayesian)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(FestivalText.primary)
            }
        }
        .fixedSize()
    }
}

// MARK: - Leaderboard name

/// A leaderboard row's player or band name (issue #292): one line that stays inside
/// its column and scrolls with the shared ``MarqueeText`` when it does not fit; short
/// names stay still. ``MarqueeText`` tail-truncates instead of scrolling under Reduce
/// Motion (system or in-app), in inactive or hidden scenes and under the debug
/// still-background flag, and VoiceOver always reads the full name.
///
/// At accessibility Dynamic Type sizes, where the rows already stack, the name wraps
/// onto as many lines as it needs instead: the HIG's "Keep text truncation to a
/// minimum as font size increases" (`typography`), and layout lets rows "grow to
/// avoid clipping/overlap and allow multiple lines" (`layout`).
///
/// Shared by every leaderboard row (``RankingRowLayout``, `SongLeaderboardEntryRow`,
/// `SongBandPreviewRow`). It stays a static-text element for VoiceOver and XCUITest.
struct LeaderboardNameText: View {
    /// How a name is laid out at a text size.
    enum Presentation: Equatable {
        /// One line; scrolls when it overflows, else tail-truncates (``MarqueeText``).
        case marquee
        /// As many lines as the name needs.
        case wrapping
    }

    /// Display name, read in full by VoiceOver.
    let name: String
    /// Bold, for the selected player's own row (web `isPlayer`).
    var emphasized: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            switch Self.presentation(for: dynamicTypeSize) {
            case .marquee:
                MarqueeText(name, font: Self.font(emphasized: emphasized))
            case .wrapping:
                Text(name)
                    .font(Self.font(emphasized: emphasized))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(FestivalText.primary)
        .accessibilityAddTraits(.isStaticText)
    }

    /// The name's layout at a text size.
    ///
    /// - Parameter size: Current Dynamic Type size.
    /// - Returns: ``Presentation/wrapping`` at accessibility sizes, else
    ///   ``Presentation/marquee``.
    static func presentation(for size: DynamicTypeSize) -> Presentation {
        size.isAccessibilitySize ? .wrapping : .marquee
    }

    /// The name's font: body, bold for the selected player's row.
    ///
    /// - Parameter emphasized: The selected player's own row.
    /// - Returns: The row name font.
    static func font(emphasized: Bool) -> Font {
        emphasized ? .body.bold() : .body
    }
}

// MARK: - Songs column fitting (#38)

/// Keeps a hidden songs played/total value in the row's combined VoiceOver element.
private struct HiddenSongsAccessibility: ViewModifier {
    /// The spoken songs value when the column is hidden, else nil.
    let spokenSongs: String?

    func body(content: Content) -> some View {
        if let spokenSongs {
            content.accessibilityValue(spokenSongs)
        } else {
            content
        }
    }
}

/// One rankings row's name as its section draws it, for the songs-column fit.
struct RankingRowName: Hashable {
    /// Display name as the row shows it.
    let name: String
    /// Drawn bold (the selected player's row).
    var emphasized: Bool = false
}

extension View {
    /// Share `columns` with the section's rows like `leaderboardSectionColumns(_:)`,
    /// and hide the songs played/total column on **every** row when showing it would
    /// truncate any of `names` at the section's measured width (issue #38).
    ///
    /// The decision re-runs whenever the section width (orientation, split view,
    /// window size) or the text size changes, because both measurements are live.
    ///
    /// - Parameters:
    ///   - columns: The section's fitted rankings columns (`LeaderboardRowColumns.rankings`).
    ///   - names: Every row's name in the section, including a pinned/spotlight row.
    ///   - rowInset: Total horizontal padding between this view's edges and its rows
    ///     (for example 32 for a page that pads its rows by 16 on each side).
    /// - Returns: This view with the decided columns in its environment.
    func leaderboardSectionColumns(
        _ columns: LeaderboardRowColumns, hidingCrowdedSongsFor names: [RankingRowName],
        rowInset: CGFloat = 0
    ) -> some View {
        modifier(RankingSongsFit(columns: columns, names: names, rowInset: rowInset))
    }
}

/// Measures a rankings section and its widest possible row, then hides the songs
/// column when that row would not fit (`LeaderboardRowColumns.fittingSongs`).
private struct RankingSongsFit: ViewModifier {
    let columns: LeaderboardRowColumns
    let names: [RankingRowName]
    var rowInset: CGFloat = 0
    @State private var availableWidth: CGFloat = 0
    @State private var requiredWidth: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .leaderboardSectionColumns(columns.fittingSongs(
                availableWidth: Double(availableWidth > 0 ? max(1, availableWidth - rowInset) : 0),
                requiredWidth: Double(requiredWidth)
            ))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
            .background(alignment: .topLeading) {
                RankingRowWidthProbe(columns: columns, names: names)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { requiredWidth = $0 }
                    .hidden()
                    .accessibilityHidden(true)
            }
    }
}

/// A hidden template of the section's widest row with songs shown: the same columns,
/// fonts, spacing and padding as `RankingRowLayout`, with every name stacked so the
/// longest one sets the name column's ideal width.
struct RankingRowWidthProbe: View {
    let columns: LeaderboardRowColumns
    let names: [RankingRowName]

    var body: some View {
        HStack(spacing: RankingRowLayout.columnSpacing) {
            LeaderboardColumnSlot(template: columns.rankLabel) { EmptyView() }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(names.enumerated()), id: \.offset) { _, row in
                    RankingRowLayout.nameText(row.name, emphasized: row.emphasized)
                }
            }
            LeaderboardColumnSlot(
                template: columns.songsLabel, alignment: .trailing, font: RankingRowLayout.songsFont
            ) { EmptyView() }
            LeaderboardColumnSlot(template: columns.ratingLabel, alignment: .trailing) { EmptyView() }
            RankingRowLayout.chevron
        }
        .padding(.horizontal, RankingRowLayout.horizontalPadding)
    }
}

// MARK: - Row surface

/// Per-row material card, with the selected player's accent fill and border on top
/// (web `entryRow` / `playerEntryRow`: `purpleHighlight` rgba(75,15,99,0.75) and a
/// `purpleHighlightBorder` rgba(124,58,237,0.5) hairline). The one leaderboard row design
/// for Song Detail cards, song leaderboards, Leaderboards, Full Rankings and Compete
/// (operator batch 7.4).
///
/// Other rows sit on the shared material card (`festivalRowCard(cornerRadius:)`),
/// fitted to the tinted Liquid Glass card these rows used to draw (issue #291). Under a live
/// `glassEffect` a row skipped its staggered load-in fade (it showed with the page's
/// reveal), so the selected player's row, which never had glass, faded in last
/// (issue #295). HIG Materials: "Don't use Liquid Glass in the content layer. Use
/// standard materials for content-layer elements".
struct RankingRowSurface: ViewModifier {
    /// Web `Colors.purpleHighlight`.
    static let playerFill = Color(.sRGB, red: 75 / 255, green: 15 / 255, blue: 99 / 255, opacity: 0.75)
    /// Web `Colors.purpleHighlightBorder`.
    static let playerBorder = Color(.sRGB, red: 124 / 255, green: 58 / 255, blue: 237 / 255, opacity: 0.5)

    let isSelected: Bool
    /// False keeps only the selected-row accent, for rows already inside a card.
    var card: Bool = true

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        content
            .background {
                if isSelected {
                    shape.fill(Self.playerFill)
                }
            }
            .modifier(OptionalRowCard(enabled: card && !isSelected))
            .overlay {
                if isSelected {
                    shape.stroke(Self.playerBorder, lineWidth: 1)
                }
            }
    }
}

// MARK: - Selected-row accessibility

/// Overrides a rankings row's spoken label only for the selected player's own
/// row (e.g. "Your rank, 1,234th. PlayerName."); every other row keeps SwiftUI's
/// default combined label so unrelated VoiceOver behavior is unchanged.
struct SelectedRankAccessibilityLabel: ViewModifier {
    let isSelected: Bool
    let rank: Int
    let name: String

    func body(content: Content) -> some View {
        if isSelected {
            content.accessibilityLabel("Your rank, \(RankingFormatting.ordinal(rank)). \(name).")
        } else {
            content
        }
    }
}

// MARK: - Spotlight placeholders

/// Compact "your rank" loading placeholder shown while the selected player's own
/// per-account ranking read (`GET /api/rankings/{instrument}/{accountId}`) is in flight.
struct RankingSpotlightLoadingRow: View {
    var body: some View {
        HStack(spacing: 6) {
            // Operator standard: white spinner, no visible loading subtitle.
            FestivalLoadingView(accessibilityLabel: "Loading your rank")
                .controlSize(.small)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading your rank")
    }
}

/// "Not yet ranked" text shown when the selected player has no row on this board.
struct RankingSpotlightUnrankedRow: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(FestivalText.primary)
    }
}

/// Applies the material row card only when enabled.
private struct OptionalRowCard: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.festivalRowCard(cornerRadius: 12)
        } else {
            content
        }
    }
}

// MARK: - Band ranking row

/// One band-rankings row, shared by the overview cards and the full board, in the
/// same compact card layout as ``AccountRankingRow``.
///
/// Navigates to the band's detail page, matching the web client's row link
/// to `/bands/:bandId`.
struct BandRankingRow: View {
    let entry: BandRankingEntry
    let metric: BandRankingMetric
    /// Carried so Band Detail can call its safe `teamKey`-filtered rankings read
    /// instead of the side-effecting `/api/bands/{bandId}` lookup — see
    /// `Bands.swift`'s `BandDetail` documentation (Lane Bands, 2026-09-27).
    let bandType: BandType
    /// Draw the row as its own material card; see ``AccountRankingRow/cardSurface``.
    var cardSurface: Bool = false

    /// The band a row opens.
    ///
    /// - Parameters:
    ///   - entry: A band rankings row.
    ///   - bandType: The board's band size.
    /// - Returns: The band route.
    static func route(_ entry: BandRankingEntry, bandType: BandType) -> AppRoute {
        .band(bandId: entry.bandId, name: nil, bandType: bandType.rawValue, teamKey: entry.teamKey)
    }

    /// Mac arrow-key rows for a band board.
    ///
    /// - Parameters:
    ///   - entries: Rows in display order.
    ///   - bandType: The board's band size.
    ///   - prefix: Keeps ids unique when one page shows several boards.
    ///   - container: The lazily built card holding them, if any.
    /// - Returns: Rows with ids `prefix + teamKey`.
    static func keyRows(
        _ entries: [BandRankingEntry], bandType: BandType, prefix: String = "", container: String? = nil
    ) -> [MacKeyRow] {
        entries.map {
            MacKeyRow(id: prefix + $0.teamKey, action: .route(route($0, bandType: bandType)), container: container)
        }
    }

    var body: some View {
        let songs = entry.songsLabel(for: metric)
        // Opens Band Detail in the trailing pane where the board can split (Band
        // Rankings, the Leaderboards band cards), else pushes.
        ListDetailLink(
            value: Self.route(entry, bandType: bandType)
        ) {
            RankingRowLayout(
                rank: entry.rank(for: metric),
                name: entry.membersLabel,
                songs: songs,
                spokenSongs: RankingsCountText.spokenSongs(songs, fullCombos: metric == .fcrate),
                rating: RankingFormatting.rating(
                    entry.ratingValue(for: metric), metric: metric.asRankingMetric
                ),
                bayesian: entry.bayesianValue(for: metric).map(RankingFormatting.bayesian),
                showsChevron: true
            )
            .modifier(RankingRowSurface(isSelected: false, card: cardSurface))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("fst.band-rankings.row.\(entry.teamKey)")
    }
}

// MARK: - Skeleton

/// Redacted placeholder rows shown while a rankings request is in flight; card
/// rows where the loaded rows are cards, at the loaded rows' height so nothing jumps
/// when the data arrives (issue #90).
struct RankingsSkeletonRows: View {
    let count: Int
    /// Match card rows (Leaderboards) instead of plain rows inside a card.
    var cardRows: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: 10) {
                    Capsule().frame(width: 28, height: 14)
                    Capsule().frame(width: 120, height: 14)
                    Spacer()
                    Capsule().frame(width: 56, height: 14)
                }
                .foregroundStyle(BrandTokens.surfaceMuted)
                .padding(.horizontal, cardRows ? 14 : 0)
                .frame(minHeight: cardRows ? LeaderboardRowMetrics.minHeight : nil)
                .modifier(RankingRowSurface(isSelected: false, card: cardRows))
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

// MARK: - Rail clearance (B6)

extension View {
    /// Keeps a rankings `List`'s rows clear of hardware cutouts beside the iPhone Duo
    /// vertical bar (B6).
    ///
    /// Pads by `cutoutInsets.trailing` (camera occlusion only), not
    /// `overlayInsets.trailing`: the page's safe area already ends at the rail, so the
    /// full overlay inset counted the bar twice and left a rail-wide gap beside it
    /// (the same double inset the Duo lane fixed for the Songs scrubber, `186b430`).
    /// Zero on iPhone and wherever there is no cutout inside the safe area. Full and
    /// Band Rankings no longer use it (their `ScrollView` stops at the rail); song
    /// leaderboards and Player Bands still do.
    ///
    /// - Parameter layout: Current `\.deviceLayout`.
    /// - Returns: The list, inset clear of in-safe-area cutouts.
    func rankingsListRailClearance(_ layout: DeviceLayout) -> some View {
        padding(.trailing, layout.cutoutInsets.trailing)
    }
}

// MARK: - Pager (text footer)

/// Discoverable first/previous/next/last paging footer shared by the song
/// leaderboards, Full Rankings (issue #294: one pager for every instrument and song
/// board) and Player Bands. Band Rankings still uses ``RankingsFloatingBar``.
///
/// The `page / total` badge is one adjustable VoiceOver element ("Page, 2 of 48"):
/// swipe up/down to page, as the floating pager allows.
///
/// The arrows and badge sit on the rows' own card surface (``View/festivalCardCapsule()``,
/// ``View/festivalCard(cornerRadius:)``), like the web `Paginator`'s `frostedCard`
/// arrows (surface-materials R1, issue #319): same fill, translucency, rim and opaque
/// Reduce Transparency / Increase Contrast fallback. Rows never draw beneath the pager
/// (``View/bottomChromeFade(chromeTop:distance:in:legacyScrollTracking:)``), so no
/// row text sits under its glyphs.
///
/// On the iPhone Duo vertical bar this footer alone ran ≈150 of 678 pt (B2,
/// `.agents/design/apple/duo.md`), so it renders nothing there: the caller also adds
/// ``RankingsPagerToolbarContent`` to its own `.toolbar { … }`, which shows the same
/// four actions as compact `.bottomBar` symbol items instead. iPhone (horizontal bar)
/// keeps this footer — a bottom toolbar there would collide with the floating tab bar
/// (`.agents/design/apple/iphone.md`).
struct RankingsPagerView: View {
    let page: Int
    let totalPages: Int
    let idPrefix: String
    /// Space above the controls; a list with pinned chrome passes less so its last
    /// row rests one row gap above the pager (issue #293).
    var topPadding: CGFloat = 8
    let onChange: (Int) -> Void
    @Environment(\.deviceLayout) private var layout

    var body: some View {
        if layout.sectionChrome.isVerticalBar {
            EmptyView()
        } else {
            // Web `FixedLeaderboardPagination` / `Paginator`: one centred row of
            // frosted circle arrows around a "page / total" badge (operator batch 7.5).
            HStack(spacing: 10) {
                arrow("chevron.backward.2", "First page", id: "page-first", enabled: page > 1) { onChange(1) }
                arrow("chevron.backward", "Previous page", id: "page-previous", enabled: page > 1) { onChange(page - 1) }
                Text("\(page) / \(totalPages)")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(FestivalText.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    // The row card itself (12 pt corners like the rows), not a capsule:
                    // the badge's whole accessibility frame stays on the card (issue #319).
                    .festivalCard(cornerRadius: 12)
                    .accessibilityElement()
                    .accessibilityLabel("Page")
                    .accessibilityValue(pagerState.accessibilityValue)
                    .accessibilityAdjustableAction { direction in
                        let action: RankingsPagerAction? = switch direction {
                        case .increment: .next
                        case .decrement: .previous
                        @unknown default: nil
                        }
                        if let action, let destination = pagerState.destination(for: action) {
                            onChange(destination)
                        }
                    }
                    .accessibilityIdentifier("\(idPrefix).page-info")
                arrow("chevron.forward", "Next page", id: "page-next", enabled: page < totalPages) { onChange(page + 1) }
                arrow("chevron.forward.2", "Last page", id: "page-last", enabled: page < totalPages) { onChange(totalPages) }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, topPadding)
            .padding(.bottom, 8)
            .padding(.horizontal, 16)
        }
    }

    /// Clamped page facts for the spoken value and the adjustable action.
    private var pagerState: RankingsPagerState {
        RankingsPagerState(page: page, totalPages: totalPages)
    }

    /// A 44 pt frosted circle arrow (web `arrowBtnBase`), faded when disabled.
    ///
    /// - Parameters:
    ///   - symbol: Chevron symbol.
    ///   - label: Spoken action.
    ///   - id: Identifier suffix.
    ///   - enabled: Whether the move is possible.
    ///   - action: Page change.
    /// - Returns: The arrow button.
    private func arrow(
        _ symbol: String, _ label: String, id: String, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(enabled ? FestivalText.primary : FestivalText.disabled)
                .frame(width: 44, height: 44)
                .festivalCardCapsule()
                .contentShape(Circle())
        }
        .buttonStyle(HighContrastPagerStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier("\(idPrefix).\(id)")
    }
}

// MARK: - Floating pager

/// Floating bottom bar for Band Rankings: a material pager
/// capsule (`« ‹ 1 / 34,757 › »`) beside the board's switcher menu, mirroring the
/// web's floating pagination pill and instrument pill (`FullRankingsPage.tsx`).
///
/// Place it with `.safeAreaInset(edge: .bottom)` on the page: inside a `TabView` the
/// page's bottom safe area already ends above the floating tab bar, so the bar sits
/// above it and the scroll content insets under it. On the iPhone Duo vertical bar it
/// renders nothing: ``RankingsPagerToolbarContent`` puts the pager in the rail (B2)
/// and the caller keeps its switcher menu in the toolbar.
///
/// Layout falls back in order: one row with the menu's title, one row with an
/// icon-only menu, then pager above menu (large Dynamic Type).
struct RankingsFloatingBar<SwitcherMenu: View>: View {
    /// Nil while the first page of a new selection loads: only the menu shows.
    let pager: RankingsPagerState?
    let idPrefix: String
    let onChange: (Int) -> Void
    /// Board switcher (instrument or band size); `true` asks for its visible title.
    @ViewBuilder let menu: (_ showsTitle: Bool) -> SwitcherMenu
    @Environment(\.deviceLayout) private var layout

    var body: some View {
        if layout.sectionChrome.isVerticalBar {
            EmptyView()
        } else {
            Group {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        pagerView
                        menu(true)
                    }
                    HStack(spacing: 8) {
                        pagerView
                        menu(false)
                    }
                    VStack(spacing: 8) {
                        pagerView
                        menu(true)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var pagerView: some View {
        if let pager {
            RankingsGlassPager(state: pager, idPrefix: idPrefix, onChange: onChange)
        }
    }
}

/// The material pager capsule (``View/festivalCardCapsule()``): First, Previous, the `page / total` label, Next, Last.
///
/// Buttons are SF Symbols with spoken titles ("First Page" …) and keep their
/// existing `<idPrefix>.page-*` identifiers. The label is one adjustable element
/// ("Page, 1 of 34,757"): VoiceOver swipes up/down to page.
struct RankingsGlassPager: View {
    let state: RankingsPagerState
    let idPrefix: String
    let onChange: (Int) -> Void
    @ScaledMetric(relativeTo: .body) private var buttonSize: CGFloat = 44

    var body: some View {
        HStack(spacing: 0) {
            button(.first)
            button(.previous)
            Text(state.label)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(FestivalText.primary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6)
                .frame(minWidth: buttonSize, minHeight: buttonSize)
                // The shape makes the 44 pt frame the element's frame; without it the
                // audit measured the bare text (31 × 18 pt, "Hit area is too small").
                .contentShape(Rectangle())
                .accessibilityElement()
                .accessibilityLabel("Page")
                .accessibilityValue(state.accessibilityValue)
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: go(.next)
                    case .decrement: go(.previous)
                    @unknown default: break
                    }
                }
                .accessibilityIdentifier("\(idPrefix).page-info")
            button(.next)
            button(.last)
        }
        .padding(.horizontal, 4)
        .festivalCardCapsule()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(idPrefix).pager")
    }

    /// Move to an action's destination when it is enabled.
    ///
    /// - Parameter action: Pager step.
    private func go(_ action: RankingsPagerAction) {
        if let destination = state.destination(for: action) { onChange(destination) }
    }

    /// One symbol button; disabled at the matching edge.
    ///
    /// - Parameter action: Pager step.
    /// - Returns: A 44 pt (scaled) plain button with a spoken title and stable id.
    private func button(_ action: RankingsPagerAction) -> some View {
        let enabled = state.destination(for: action) != nil
        return Button { go(action) } label: {
            Image(systemName: Self.symbol(action))
                .font(.body.weight(.semibold))
                .foregroundStyle(enabled ? FestivalText.primary : FestivalText.disabled)
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Circle())
        }
        .buttonStyle(HighContrastPagerStyle())
        .disabled(!enabled)
        .accessibilityLabel(Self.title(action))
        .accessibilityIdentifier("\(idPrefix).page-\(action.rawValue)")
    }

    /// SF Symbol for an action (web `«`, `‹`, `›`, `»`).
    ///
    /// - Parameter action: Pager step.
    /// - Returns: Symbol name.
    static func symbol(_ action: RankingsPagerAction) -> String {
        switch action {
        case .first: "chevron.backward.2"
        case .previous: "chevron.backward"
        case .next: "chevron.forward"
        case .last: "chevron.forward.2"
        }
    }

    /// Spoken title for an action.
    ///
    /// - Parameter action: Pager step.
    /// - Returns: "First Page", "Previous Page", "Next Page" or "Last Page".
    static func title(_ action: RankingsPagerAction) -> String {
        switch action {
        case .first: "First Page"
        case .previous: "Previous Page"
        case .next: "Next Page"
        case .last: "Last Page"
        }
    }
}

/// Material pill label for a board switcher menu in ``RankingsFloatingBar``: the
/// board's icon, plus its name when there is room (web instrument pill).
struct RankingsSwitcherPillLabel<Icon: View>: View {
    let title: String
    let showsTitle: Bool
    @ViewBuilder let icon: () -> Icon
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 44

    var body: some View {
        HStack(spacing: 8) {
            icon()
            if showsTitle {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .foregroundStyle(FestivalText.primary)
        .padding(.leading, showsTitle ? 8 : 0)
        .padding(.trailing, showsTitle ? 14 : 0)
        .frame(minWidth: height, minHeight: height)
        .contentShape(Capsule())
        .festivalCardCapsule()
    }
}

// MARK: - Ranked-count header

/// The board's ranked count ("868,901 ranked players") as the first line under the
/// large title (web `PageHeader` subtitle, `rankings.totalRanked`).
///
/// Content, not `navigationSubtitle`: the system subtitle renders too small to read
/// comfortably (operator, 2026-09-28), so this uses `.subheadline` semibold in
/// primary white and scales with Dynamic Type.
struct RankingsCountHeader: View {
    let text: String
    let id: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(FestivalText.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
            .accessibilityIdentifier(id)
    }
}

// MARK: - Pager (vertical bar toolbar content)

/// Compact vertical-bar equivalent of ``RankingsFloatingBar``'s pager (B2): First,
/// Previous, Next and Last as `.bottomBar` symbol items (system-placed at the bottom
/// of the rail, above the tab bar), with the page label as a low-priority item so it
/// overflows into the system `…` menu first and still reads as "Page 3 of 34,770"
/// there; Next carries `.high` so it stays in the rail (`/duo` D5: the folded rail fits
/// one bottom item beside 5 tabs, and Next is the action a first page needs).
/// Every item is a `Label(title, systemImage:)`: a title-only item would force
/// the system to keep a horizontal bar just for it (`.agents/design/apple/duo.md`).
///
/// Add alongside ``RankingsFloatingBar`` (in the same page); both read
/// `\.deviceLayout` themselves, so exactly one of the two renders anything for a
/// given chrome.
///
/// iOS-only: `.bottomBar` and `visibilityPriority` don't exist on macOS, and macOS
/// never resolves a vertical-bar `\.deviceLayout` chrome, so there is nothing for
/// this type to do there. Callers wrap their own use of it in `#if os(iOS)`.
#if os(iOS)
struct RankingsPagerToolbarContent: ToolbarContent {
    let page: Int
    let totalPages: Int
    let idPrefix: String
    let onChange: (Int) -> Void
    @Environment(\.deviceLayout) private var layout

    private var previousButton: some View {
        Button { onChange(page - 1) } label: {
            Label("Previous", systemImage: "chevron.backward")
        }
        .disabled(page <= 1)
        .accessibilityIdentifier("\(idPrefix).page-previous")
    }

    private var nextButton: some View {
        Button { onChange(page + 1) } label: {
            Label("Next", systemImage: "chevron.forward")
        }
        .disabled(page >= totalPages)
        .accessibilityIdentifier("\(idPrefix).page-next")
    }

    var body: some ToolbarContent {
        if layout.sectionChrome.isVerticalBar {
            ToolbarItem(placement: .bottomBar) {
                Button { onChange(1) } label: {
                    Label("First", systemImage: "chevron.backward.to.line")
                }
                .disabled(page <= 1)
                .accessibilityIdentifier("\(idPrefix).page-first")
            }
            ToolbarItem(placement: .bottomBar) { previousButton }
            if #available(iOS 27.0, *) {
                ToolbarItem(placement: .bottomBar) {
                    pageIndicator
                }
                .visibilityPriority(.low)
            } else {
                ToolbarItem(placement: .bottomBar) {
                    pageIndicator
                }
            }
            // `/duo` D5: Next stays in the rail. Folded with 5 tabs the rail fits one
            // bottom item; with Previous `.high` too it kept the disabled Previous on
            // page 1 and overflowed Next (measured 2026-10-02).
            if #available(iOS 27.0, *) {
                ToolbarItem(placement: .bottomBar) { nextButton }
                    .visibilityPriority(.high)
            } else {
                ToolbarItem(placement: .bottomBar) { nextButton }
            }
            ToolbarItem(placement: .bottomBar) {
                Button { onChange(totalPages) } label: {
                    Label("Last", systemImage: "chevron.forward.to.line")
                }
                .disabled(page >= totalPages)
                .accessibilityIdentifier("\(idPrefix).page-last")
            }
        }
    }

    /// Disabled, informational "Page X of Y": not an action, but still a
    /// `Label(title, systemImage:)` so it can go vertical instead of forcing a
    /// horizontal bar just for its title.
    private var pageIndicator: some View {
        Button {
        } label: {
            Label("Page \(page) of \(totalPages)", systemImage: "number")
        }
        .disabled(true)
        .accessibilityIdentifier("\(idPrefix).page-info")
    }
}
#endif

// MARK: - Metric picker

/// Native toolbar menu for the shared account rank-by metrics.
struct RankByMenu: View {
    @Binding var selection: RankingMetric

    var body: some View {
        PageToolMenu("Rank By", choices: choices) {
            Picker("Rank By", selection: $selection) {
                ForEach(RankingMetric.allCases) { metric in
                    Text(metric.label).tag(metric)
                }
            }
        } label: {
            Label(selection.label, systemImage: "arrow.up.arrow.down")
        }
        .accessibilityIdentifier("fst.rankings.rank-by-menu")
    }

    /// The metrics for the inline-accessory sheet (``PageToolMenu``).
    private func choices() -> [PageToolMenuChoice] {
        RankingMetric.allCases.map { metric in
            PageToolMenuChoice(
                id: "fst.rankings.rank-by.\(metric.rawValue)", label: AnyView(Text(metric.label)),
                isSelected: metric == selection, action: { selection = metric }
            )
        }
    }
}

/// Native toolbar menu for the band-safe rank-by metrics (no Max Score).
struct BandRankByMenu: View {
    @Binding var selection: BandRankingMetric

    var body: some View {
        PageToolMenu("Rank By", choices: choices) {
            Picker("Rank By", selection: $selection) {
                ForEach(BandRankingMetric.allCases) { metric in
                    Text(metric.label).tag(metric)
                }
            }
        } label: {
            Label(selection.label, systemImage: "arrow.up.arrow.down")
        }
        .accessibilityIdentifier("fst.band-rankings.rank-by-menu")
    }

    /// The metrics for the inline-accessory sheet (``PageToolMenu``).
    private func choices() -> [PageToolMenuChoice] {
        BandRankingMetric.allCases.map { metric in
            PageToolMenuChoice(
                id: "fst.band-rankings.rank-by.\(metric.rawValue)", label: AnyView(Text(metric.label)),
                isSelected: metric == selection, action: { selection = metric }
            )
        }
    }
}
