import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Load state

/// Shared loading/loaded/failed state for every rankings surface in this feature.
enum RankLoadState<Value> {
    case loading
    case loaded(Value)
    case failed(ServiceIssue)
}

// MARK: - Account ranking row

/// One account-rankings row, shared by the overview cards and the full board.
///
/// A compact single-line glass row (rank, name, `728 / 729`, accent-coloured value),
/// matching the web client's `RankingEntry` inside `RankingCard.tsx`: every row is
/// its own frosted card there, so each row here carries its own glass surface and
/// the surrounding page adds none (no glass on glass).
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
    /// Draw the row as its own glass card (Leaderboards, Full Rankings). Off where
    /// the row already sits inside a glass card (Compete previews): no glass on glass.
    var glassSurface: Bool = false

    private var displayName: String { Self.displayName(entry) }

    /// The name a row shows for `entry` ("Unknown User" without one).
    ///
    /// - Parameter entry: A rankings row.
    /// - Returns: The display name as drawn.
    static func displayName(_ entry: AccountRankingEntry) -> String {
        entry.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown User"
    }

    var body: some View {
        Group {
            if entry.hasAccount {
                ListDetailLink(
                    value: AppRoute.player(accountId: entry.accountId, displayName: entry.displayName)
                ) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                // Anonymous production rows have no profile to open.
                rowContent
                    .accessibilityHint("Profile unavailable")
            }
        }
        .accessibilityIdentifier("fst.rankings.row.\(entry.id)")
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
        .modifier(RankingRowSurface(isSelected: isSelected, glass: glassSurface))
    }
}

// MARK: - Shared row layout

/// Compact rankings row content: `#rank`, a truncating name, the songs column and
/// the accent-coloured value (web `RankingEntry.tsx`: `colRank`, `colName`,
/// `colSongs`, `colRating` = `Colors.accentBlue*`), on one line. Text is primary
/// white throughout (operator rule: no gray de-emphasis on these pages).
///
/// Adjusted/Weighted add their Bayesian value as a second, smaller line under the
/// value (the web's compact two-row percentile layout). At accessibility Dynamic Type
/// sizes the row stacks (rank + name, then songs + value) instead of truncating the
/// name to nothing.
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
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        songsText
                        Spacer(minLength: 8)
                        ratingColumn
                    }
                }
            } else {
                HStack(spacing: Self.columnSpacing) {
                    LeaderboardColumnSlot(template: columns?.rankLabel) { rankText }
                        .frame(minWidth: columns == nil ? rankWidth : nil, alignment: .leading)
                    nameText
                        .lineLimit(1)
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
        .frame(minHeight: 44)
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
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(FestivalText.deemphasized)
            .accessibilityHidden(true)
    }

    /// A row name as drawn: body text, bold for the selected player's row.
    ///
    /// - Parameters:
    ///   - name: Display name.
    ///   - emphasized: The selected player's own row.
    /// - Returns: A one-line, tail-truncating name.
    static func nameText(_ name: String, emphasized: Bool) -> some View {
        Text(name)
            .lineLimit(1)
            .truncationMode(.tail)
            .font(.body)
            .fontWeight(emphasized ? .bold : .regular)
            .foregroundStyle(FestivalText.primary)
    }

    private var rankText: some View {
        Text("#\(rank.formatted())")
            .font(.body)
            .monospacedDigit()
            .foregroundStyle(FestivalText.primary)
            .fixedSize()
    }

    /// Truncates like the web's `colName` (`truncate`): leaderboard names never marquee
    /// (operator batch 7.7).
    private var nameText: some View {
        Self.nameText(name, emphasized: emphasized)
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

    private var ratingColumn: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(rating)
                .font(.body)
                .fontWeight(emphasized ? .bold : .semibold)
                .monospacedDigit()
                .foregroundStyle(BrandTokens.accentBlue)
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
    /// - Returns: This view with the decided columns in its environment.
    func leaderboardSectionColumns(
        _ columns: LeaderboardRowColumns, hidingCrowdedSongsFor names: [RankingRowName]
    ) -> some View {
        modifier(RankingSongsFit(columns: columns, names: names))
    }
}

/// Measures a rankings section and its widest possible row, then hides the songs
/// column when that row would not fit (`LeaderboardRowColumns.fittingSongs`).
private struct RankingSongsFit: ViewModifier {
    let columns: LeaderboardRowColumns
    let names: [RankingRowName]
    @State private var availableWidth: CGFloat = 0
    @State private var requiredWidth: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .leaderboardSectionColumns(columns.fittingSongs(
                availableWidth: Double(availableWidth), requiredWidth: Double(requiredWidth)
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

/// Per-row glass card, with the selected player's accent fill and border on top
/// (web `entryRow` / `playerEntryRow`: `purpleHighlight` rgba(75,15,99,0.75) and a
/// `purpleHighlightBorder` rgba(124,58,237,0.5) hairline). The one leaderboard row design
/// for Song Detail cards, song leaderboards, Leaderboards, Full Rankings and Compete
/// (operator batch 7.4).
struct RankingRowSurface: ViewModifier {
    /// Web `Colors.purpleHighlight`.
    static let playerFill = Color(.sRGB, red: 75 / 255, green: 15 / 255, blue: 99 / 255, opacity: 0.75)
    /// Web `Colors.purpleHighlightBorder`.
    static let playerBorder = Color(.sRGB, red: 124 / 255, green: 58 / 255, blue: 237 / 255, opacity: 0.5)

    let isSelected: Bool
    /// False keeps only the selected-row accent, for rows already inside a card.
    var glass: Bool = true

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        content
            .background {
                if isSelected {
                    shape.fill(Self.playerFill)
                }
            }
            .modifier(OptionalGlass(enabled: glass && !isSelected))
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

/// Applies the row glass only when enabled.
private struct OptionalGlass: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.festivalGlass(.card, cornerRadius: 12)
        } else {
            content
        }
    }
}

// MARK: - Band ranking row

/// One band-rankings row, shared by the overview cards and the full board, in the
/// same compact glass layout as ``AccountRankingRow``.
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
    /// Draw the row as its own glass card; see ``AccountRankingRow/glassSurface``.
    var glassSurface: Bool = false

    var body: some View {
        let songs = entry.songsLabel(for: metric)
        NavigationLink(
            value: AppRoute.band(
                bandId: entry.bandId, name: nil,
                bandType: bandType.rawValue, teamKey: entry.teamKey
            )
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
            .modifier(RankingRowSurface(isSelected: false, glass: glassSurface))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("fst.band-rankings.row.\(entry.teamKey)")
    }
}

// MARK: - Skeleton

/// Redacted placeholder rows shown while a rankings request is in flight; glass
/// rows where the loaded rows are glass.
struct RankingsSkeletonRows: View {
    let count: Int
    /// Match glass rows (Leaderboards) instead of plain rows inside a card.
    var glassRows: Bool = false

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
                .padding(.horizontal, glassRows ? 14 : 0)
                .frame(minHeight: glassRows ? 44 : nil)
                .modifier(RankingRowSurface(isSelected: false, glass: glassRows))
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

/// Discoverable first/previous/next/last text paging footer, still used by the
/// song leaderboards and Player Bands (the overall Full/Band Rankings boards use
/// ``RankingsFloatingBar`` instead, Lane PB 2026-09-28).
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
    let onChange: (Int) -> Void
    @Environment(\.deviceLayout) private var layout

    var body: some View {
        if layout.sectionChrome.isVerticalBar {
            EmptyView()
        } else {
            // Web `FixedLeaderboardPagination` / `Paginator`: one centred row of
            // frosted circle arrows around a "page / total" badge (operator batch 7.5).
            HStack(spacing: 10) {
                arrow("chevron.left.2", "First page", id: "page-first", enabled: page > 1) { onChange(1) }
                arrow("chevron.left", "Previous page", id: "page-previous", enabled: page > 1) { onChange(page - 1) }
                Text("\(page) / \(totalPages)")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(FestivalText.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .modifier(PagerPlate(cornerRadius: 12))
                    .accessibilityIdentifier("\(idPrefix).page-info")
                arrow("chevron.right", "Next page", id: "page-next", enabled: page < totalPages) { onChange(page + 1) }
                arrow("chevron.right.2", "Last page", id: "page-last", enabled: page < totalPages) { onChange(totalPages) }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
        }
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
                .modifier(PagerPlate(cornerRadius: 22))
                .contentShape(Circle())
        }
        .buttonStyle(HighContrastPagerStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier("\(idPrefix).\(id)")
    }
}

/// Near-opaque frosted plate (web `frostedCard`) behind the pager's arrows and badge:
/// rows scroll beneath them, and see-through glass there failed the contrast audit.
private struct PagerPlate: ViewModifier {
    /// 22 for the 44 pt arrow circles; the badge uses a rounded rectangle so its whole
    /// accessibility frame is opaque (capsule corners showed rows through, audit).
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(BrandTokens.cardBackground, in: shape)
            .overlay(shape.stroke(BrandTokens.glassBorder, lineWidth: 1))
    }
}

// MARK: - Floating pager

/// Floating bottom bar for the paginated rankings boards: a Liquid Glass pager
/// capsule (`« ‹ 1 / 34,757 › »`) beside the board's switcher menu, mirroring the
/// web's floating pagination pill and instrument pill (`FullRankingsPage.tsx`).
///
/// Place it with `.safeAreaInset(edge: .bottom)` on the page: inside a `TabView` the
/// page's bottom safe area already ends above the floating tab bar and the tab-bar
/// bottom accessory (global Search, `Common/TabAccessory`), so the bar sits above
/// both and the scroll content insets under it. On the iPhone Duo vertical bar it
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
            FestivalGlassGroup(spacing: 8) {
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

/// The glass pager capsule: First, Previous, the `page / total` label, Next, Last.
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
                .frame(minHeight: buttonSize)
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
        .festivalGlassCapsule(.control)
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
        case .first: "chevron.left.2"
        case .previous: "chevron.left"
        case .next: "chevron.right"
        case .last: "chevron.right.2"
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

/// Instrument artwork for a board switcher (toolbar menu or floating pill), sized so
/// its visible disc matches the height of the SF Symbols beside it.
///
/// The artwork's white disc fills about 84% of its square (the dark ring vanishes on
/// dark glass), and toolbar symbols such as the rank-by `arrow.up.arrow.down` draw
/// about 20 pt tall at the default size. A 24 pt square (scaled with Dynamic Type)
/// therefore renders at the symbol's height; the surrounding pill grows sideways
/// rather than shrinking the icon (operator, 2026-09-28, Duo toolbar).
struct RankingsSwitcherInstrumentIcon: View {
    let instrument: Instrument
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 24

    var body: some View {
        InstrumentIcon(instrument, size: size)
            .fixedSize()
    }
}

/// Glass pill label for a board switcher menu in ``RankingsFloatingBar``: the
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
        .festivalGlassCapsule(.control, interactive: true)
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
/// there. Every item is a `Label(title, systemImage:)`: a title-only item would force
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

    var body: some ToolbarContent {
        if layout.sectionChrome.isVerticalBar {
            ToolbarItem(placement: .bottomBar) {
                Button { onChange(1) } label: {
                    Label("First", systemImage: "chevron.left.to.line")
                }
                .disabled(page <= 1)
                .accessibilityIdentifier("\(idPrefix).page-first")
            }
            ToolbarItem(placement: .bottomBar) {
                Button { onChange(page - 1) } label: {
                    Label("Previous", systemImage: "chevron.left")
                }
                .disabled(page <= 1)
                .accessibilityIdentifier("\(idPrefix).page-previous")
            }
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
            ToolbarItem(placement: .bottomBar) {
                Button { onChange(page + 1) } label: {
                    Label("Next", systemImage: "chevron.right")
                }
                .disabled(page >= totalPages)
                .accessibilityIdentifier("\(idPrefix).page-next")
            }
            ToolbarItem(placement: .bottomBar) {
                Button { onChange(totalPages) } label: {
                    Label("Last", systemImage: "chevron.right.to.line")
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
        Menu {
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
}

/// Native toolbar menu for the band-safe rank-by metrics (no Max Score).
struct BandRankByMenu: View {
    @Binding var selection: BandRankingMetric

    var body: some View {
        Menu {
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
}
