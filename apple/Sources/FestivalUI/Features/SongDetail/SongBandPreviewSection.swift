import Foundation
import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Load state

/// Song Detail's one band read (`/api/leaderboard/{songId}/bands/all`), shared by the
/// Duos, Trios and Quads sections.
enum SongBandPreviewState {
    case loading
    case loaded(SongBandLeaderboardsResponse)
    case failed(String)
}

// MARK: - Loader

/// Reads the band previews for Song Detail's load gate and Retry.
@MainActor
enum SongBandPreviewLoader {
    /// Read every band size's top ten (and the selected player's best band).
    ///
    /// - Parameters:
    ///   - session: Shared app session.
    ///   - songId: Song being shown.
    ///   - accountId: Selected player, sent only as the `accountId` query.
    /// - Returns: The sections' state, or nil when the read was cancelled.
    static func load(session: FestivalSession, songId: String, accountId: String?) async -> SongBandPreviewState? {
        do {
            let payload = try await session.songBandLeaderboards(songId: songId, accountId: accountId)
            try Task.checkCancellation()
            return .loaded(payload.response)
        } catch is CancellationError {
            return nil
        } catch let error as URLError where error.code == .cancelled {
            return nil
        } catch {
            return Task.isCancelled ? nil : .failed(error.localizedDescription)
        }
    }
}

// MARK: - Section

/// One band size's leaderboard preview on Song Detail, porting the web
/// `SongBandLeaderboardPreview`: a title, up to ten band cards (the selected player's
/// band highlighted, or appended when outside the top ten) and View full leaderboard.
struct SongBandPreviewSection: View {
    let song: Song
    let bandType: BandType
    let state: SongBandPreviewState
    /// Re-read the shared band previews after a failure.
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            switch state {
            case .loading:
                FestivalLoadingView(accessibilityLabel: "Loading \(bandType.label) scores")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            case let .failed(message):
                VStack(alignment: .leading, spacing: 8) {
                    Text("Band scores unavailable: \(message)")
                        .font(.body)
                        .foregroundStyle(FestivalText.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Retry \(bandType.label) scores", action: onRetry)
                        .frame(minHeight: 44)
                        // Readable accent text on the card (the fill tint is below 4.5:1).
                        .tint(AccentText.blue)
                        .accessibilityIdentifier("fst.song-detail.band-retry.\(bandType.rawValue)")
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .festivalCard(cornerRadius: 12)
            case let .loaded(response):
                rows(response.preview(for: bandType))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.song-detail.band.\(bandType.rawValue)")
    }

    // MARK: - Header

    /// Total ranked bands, like the solo cards' subtitle, when the service allows it.
    private var subtitle: String? {
        guard case let .loaded(response) = state else { return nil }
        let preview = response.preview(for: bandType)
        if preview.entries.isEmpty && preview.footerEntry == nil {
            return "No scores recorded yet"
        }
        guard response.showLeaderboardEntryTotals == true else { return nil }
        let total = preview.totalEntries
        return "\(total.formatted()) \(total == 1 ? "band" : "bands")"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(bandType.label)
                .font(.title3.bold())
                .foregroundStyle(FestivalText.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(FestivalText.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("fst.song-detail.band-header.\(bandType.rawValue)")
    }

    // MARK: - Rows

    @ViewBuilder
    private func rows(_ preview: SongBandLeaderboardPreview) -> some View {
        let displayed = Array(preview.entries.prefix(10))
        let footer = preview.footerEntry
        if displayed.isEmpty && footer == nil {
            // Web `InstrumentEmptyState` with `songDetail.noBandScoresSubtitle`; the
            // header subtitle already says "No scores recorded yet".
            Text(
                "When \(bandType.label) scores are submitted for this song, they will show up "
                    + "here on the next leaderboard update."
            )
            .foregroundStyle(FestivalText.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(14)
            .festivalCard(cornerRadius: 12)
            .accessibilityIdentifier("fst.song-detail.band-empty.\(bandType.rawValue)")
            .festivalFadeInOnAppear()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(displayed.enumerated()), id: \.offset) { index, entry in
                    SongBandPreviewRow(entry: entry, highlighted: preview.isSelected(entry))
                        .accessibilityIdentifier("fst.song-detail.band-row.\(bandType.rawValue).\(index)")
                }
                // The selected band's row after the top ten jumps to its place in the
                // full board, like the solo spotlight row (issue #307).
                if let footer {
                    SongBandPreviewRow(
                        entry: footer, highlighted: true,
                        route: SongBandRowNavigation.previewRoute(
                            for: footer, song: song, bandType: bandType, isAppended: true
                        )
                    )
                    .padding(.top, 4)
                    .accessibilityIdentifier("fst.song-detail.band-selected.\(bandType.rawValue)")
                }
                // The full band board opens in the trailing pane where Song Detail can
                // split, like the instrument boards (issue #367).
                ListDetailLink(value: AppRoute.songBandLeaderboard(song, bandType: bandType.rawValue)) {
                    PurpleActionLabel(title: "View full leaderboard")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View full \(bandType.label) leaderboard")
                .accessibilityIdentifier("fst.song-detail.band-leaderboard.\(bandType.rawValue)")
            }
            .festivalFadeInOnAppear()
        }
    }
}

// MARK: - Row

/// One band score card (web `PlayerBandCard` + `SongBandScoreFooter`): each member's
/// name and instruments, then rank, team score, stars and accuracy. The whole card is
/// one drill-down button with a disclosure chevron: to Band Detail, or for the selected
/// band's appended row to its place in the full board (issue #307). Shared by the Song
/// Detail band previews and the full band song leaderboard, like the web (issue #90).
struct SongBandPreviewRow: View {
    let entry: SongBandLeaderboardEntry
    /// The selected player's band: the web's purple highlight.
    let highlighted: Bool
    /// Where tapping goes (``SongBandRowNavigation``).
    let route: AppRoute
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The section's fitted columns; only ``LeaderboardRowColumns/stacksName`` (a
    /// crowded trailing-pane board, #364) changes the card.
    @Environment(\.leaderboardRowColumns) private var columns

    /// Create a band card.
    ///
    /// - Parameters:
    ///   - entry: Band score row.
    ///   - highlighted: Whether it is the selected player's band.
    ///   - route: Tap destination; nil opens the band's page.
    init(entry: SongBandLeaderboardEntry, highlighted: Bool, route: AppRoute? = nil) {
        self.entry = entry
        self.highlighted = highlighted
        self.route = route ?? SongBandRowNavigation.bandRoute(entry)
    }

    var body: some View {
        link {
            Self.card {
                VStack(alignment: .leading, spacing: 8) {
                    members
                    footer
                }
            }
            .padding(.vertical, 10)
            .frame(minHeight: LeaderboardRowMetrics.minHeight)
            .modifier(RankingRowSurface(isSelected: highlighted))
            .contentShape(Rectangle())
        }
        .festivalRowButtonStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SongBandPreviewText.spokenLabel(entry, selected: highlighted))
        .accessibilityHint(SongBandRowNavigation.hint(for: route))
        .accessibilityAddTraits(.isButton)
    }

    /// The card's link: a jump to the full band board opens in the trailing pane where
    /// Song Detail can split, like the solo spotlight row (issue #367); a band page
    /// always pushes (profiles are full pages, #352).
    ///
    /// - Parameter label: The card content.
    /// - Returns: The link wrapping the card.
    @ViewBuilder private func link<Label: View>(@ViewBuilder _ label: () -> Label) -> some View {
        if case .songBandLeaderboard = route {
            ListDetailLink(value: route, label: label)
        } else {
            NavigationLink(value: route, label: label)
        }
    }

    /// The card's horizontal layout: its content, then the disclosure chevron centred
    /// on the whole card, so it stays centred however many lines the card grows to
    /// (#364). Shared with the section's width probe (``SongBandMemberWidthProbe``).
    ///
    /// - Parameter content: Members and score footer, or the probe's member lines.
    /// - Returns: The padded card row, without its surface.
    static func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(FestivalText.deemphasized)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
    }

    /// A member's charted instruments, trailing their name.
    ///
    /// - Parameter member: A band member.
    /// - Returns: The member's instrument icons.
    static func instrumentIcons(_ member: BandMember) -> some View {
        HStack(spacing: 4) {
            ForEach(member.chartedInstruments) { instrument in
                InstrumentIcon(instrument, size: 22)
            }
        }
    }

    /// One line per member. A long name scrolls in its column (leaderboard-row R3),
    /// except on a crowded trailing-pane board (``LeaderboardRowColumns/stacksName``,
    /// owner-approved variant #364), where it wraps onto more lines in full beside
    /// its instruments and the card grows.
    private var members: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(entry.members) { member in
                HStack(spacing: 8) {
                    LeaderboardNameText(
                        name: member.resolvedName, emphasized: highlighted,
                        stacked: columns?.stacksName == true
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Self.instrumentIcons(member)
                }
            }
        }
    }

    private var footer: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Text("#\(entry.rank.formatted())")
                .font(.body)
                .fontWeight(highlighted ? .bold : .regular)
                .monospacedDigit()
                .foregroundStyle(FestivalText.primary)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Text(entry.score.formatted())
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(FestivalText.primary)
                .fixedSize()
            if entry.stars > 0 {
                StarRating(stars: entry.stars)
            }
            SongBandAccuracyBadge(accuracy: entry.accuracy, fullCombo: entry.isFullCombo)
        }
    }
}

// MARK: - Width probe (#364)

/// One band card's member names for the section's width probe, bold for the selected
/// band, as the card draws them.
struct SongBandNameRow: Equatable {
    let members: [BandMember]
    let emphasized: Bool
}

/// Width probe only (``SongLeaderboardNameFit``): every member line of `rows` drawn
/// unscrolled in the real card's columns (name, instruments, chevron and padding), so
/// its ideal width is the card width the section's longest member line needs. Never
/// shown.
struct SongBandMemberWidthProbe: View {
    let rows: [SongBandNameRow]

    var body: some View {
        SongBandPreviewRow.card {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    ForEach(row.members) { member in
                        HStack(spacing: 8) {
                            RankingRowLayout.nameText(member.resolvedName, emphasized: row.emphasized)
                                .fixedSize()
                            SongBandPreviewRow.instrumentIcons(member)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Navigation

/// Where a band score card goes: the web's `PlayerBandCard` link to the band page, or,
/// for the selected band's row appended after Song Detail's top ten, the full board at
/// the page containing its rank with the row highlighted and brought into view, the
/// same rule as the solo spotlight row (``SelectedRowAction``, issue #307).
enum SongBandRowNavigation {
    /// Rows per page of the full band board.
    static let pageSize = 25

    /// The band's own page.
    ///
    /// - Parameter entry: Band score row.
    /// - Returns: Band Detail for that band, carrying its size and roster key.
    static func bandRoute(_ entry: SongBandLeaderboardEntry) -> AppRoute {
        .band(
            bandId: entry.bandId, name: entry.membersLabel,
            bandType: entry.bandType, teamKey: entry.teamKey
        )
    }

    /// Where a Song Detail band preview row goes.
    ///
    /// - Parameters:
    ///   - entry: Band score row.
    ///   - song: Song being shown.
    ///   - bandType: Previewed band size.
    ///   - isAppended: The row is the selected band's, appended after the top rows.
    /// - Returns: The full board at the row's page for an appended row with a rank,
    ///   otherwise the band's page.
    static func previewRoute(
        for entry: SongBandLeaderboardEntry, song: Song, bandType: BandType, isAppended: Bool
    ) -> AppRoute {
        switch SelectedRowAction.preview(rank: entry.rank, isAppended: isAppended, pageSize: pageSize) {
        case let .jump(page):
            .songBandLeaderboard(
                song, bandType: bandType.rawValue, page: page, focus: SongBandRowFocus(entry)
            )
        case .openProfile:
            bandRoute(entry)
        }
    }

    /// Spoken hint naming where a band card goes.
    ///
    /// - Parameter route: The card's route.
    /// - Returns: "Opens band", or the jump to the band's position.
    static func hint(for route: AppRoute) -> String {
        if case .songBandLeaderboard = route {
            return "Jumps to your band's position in the full leaderboard"
        }
        return "Opens band"
    }

    // MARK: - Full-board footer

    /// What the full band board's pinned selected-band footer does: the Solo chart's
    /// footer rule (issue #307). While the band's row is on the shown page it opens the
    /// Band page; otherwise it jumps to the page containing the band's rank, focused on it.
    ///
    /// - Parameters:
    ///   - entry: The selected band's row (the response's `selectedEntry`).
    ///   - pageEntries: Rows of the page on screen.
    /// - Returns: The footer's action.
    static func footerAction(
        for entry: SongBandLeaderboardEntry, pageEntries: [SongBandLeaderboardEntry]
    ) -> SelectedRowAction {
        let focus = SongBandRowFocus(entry)
        return SelectedRowAction.footer(
            rank: entry.rank, isVisible: pageEntries.contains(where: focus.matches), pageSize: pageSize
        )
    }
}

// MARK: - Accuracy badge

/// The band score's accuracy pill, drawn like the solo rows' badge: graded tint, or the
/// web's skewed gold outline for a full combo.
private struct SongBandAccuracyBadge: View {
    let accuracy: Int
    let fullCombo: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var width: CGFloat = 72
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 24

    var body: some View {
        let compact = !dynamicTypeSize.isAccessibilitySize
        let shape = GoldSkewBadgeShape(skewed: fullCombo && compact)
        Text("\(ScoreFormatting.accuracy(Double(accuracy)))%")
            .font(fullCombo ? .body.bold().italic() : .body)
            .foregroundStyle(fullCombo ? BrandTokens.gold : FestivalText.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(compact ? 0 : 4)
            .frame(width: compact ? width : nil, height: compact ? height : nil)
            .background(fullCombo ? Color.clear : tint, in: shape)
            .overlay {
                if fullCombo { shape.stroke(BrandTokens.gold, lineWidth: 2) }
            }
    }

    private var tint: Color {
        guard let tint = try? ScoreFormatting.accuracyTint(Double(accuracy)) else { return .clear }
        return Color(
            .sRGB, red: Double(tint.red) / 255, green: Double(tint.green) / 255,
            blue: Double(tint.blue) / 255, opacity: 0.25
        )
    }
}

// MARK: - Spoken text

/// VoiceOver wording for band preview rows (web `bandList.viewBand` +
/// `songDetail.bandScoreFooter`).
enum SongBandPreviewText {
    /// One combined label: rank, members, score, stars and accuracy.
    ///
    /// - Parameters:
    ///   - entry: Band score row.
    ///   - selected: Whether it is the selected player's band.
    /// - Returns: A spoken label such as "Rank 1, A + B, score 1,234, 5 stars, full combo, accuracy 100%".
    static func spokenLabel(_ entry: SongBandLeaderboardEntry, selected: Bool) -> String {
        var parts = [
            "Rank \(entry.rank.formatted())",
            entry.membersLabel.isEmpty ? "Band" : entry.membersLabel,
            "score \(entry.score.formatted())",
        ]
        if entry.stars >= 6 {
            parts.append("5 gold stars")
        } else if entry.stars > 0 {
            parts.append("\(entry.stars) \(entry.stars == 1 ? "star" : "stars")")
        }
        let accuracy = "accuracy \(ScoreFormatting.accuracy(Double(entry.accuracy)))%"
        parts.append(entry.isFullCombo ? "full combo, \(accuracy)" : accuracy)
        if selected { parts.insert("Your band", at: 0) }
        return parts.joined(separator: ", ")
    }
}
