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
                        .accessibilityIdentifier("fst.song-detail.band-retry.\(bandType.rawValue)")
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .festivalGlass(.card, cornerRadius: 12)
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
            .festivalGlass(.card, cornerRadius: 12)
            .accessibilityIdentifier("fst.song-detail.band-empty.\(bandType.rawValue)")
            .festivalFadeInOnAppear()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(displayed.enumerated()), id: \.offset) { index, entry in
                    SongBandPreviewRow(entry: entry, highlighted: preview.isSelected(entry))
                        .accessibilityIdentifier("fst.song-detail.band-row.\(bandType.rawValue).\(index)")
                }
                if let footer {
                    SongBandPreviewRow(entry: footer, highlighted: true)
                        .padding(.top, 4)
                        .accessibilityIdentifier("fst.song-detail.band-selected.\(bandType.rawValue)")
                }
                NavigationLink(value: AppRoute.songBandLeaderboard(song, bandType: bandType.rawValue)) {
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
/// one drill-down button to Band Detail with a disclosure chevron. Shared by the Song
/// Detail band previews and the full band song leaderboard, like the web (issue #90).
struct SongBandPreviewRow: View {
    let entry: SongBandLeaderboardEntry
    /// The selected player's band: the web's purple highlight.
    let highlighted: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationLink(
            value: AppRoute.band(
                bandId: entry.bandId, name: entry.membersLabel,
                bandType: entry.bandType, teamKey: entry.teamKey
            )
        ) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    members
                    footer
                }
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(FestivalText.deemphasized)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: LeaderboardRowMetrics.minHeight)
            .modifier(RankingRowSurface(isSelected: highlighted))
            .contentShape(Rectangle())
        }
        .festivalRowButtonStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SongBandPreviewText.spokenLabel(entry, selected: highlighted))
        .accessibilityHint("Opens band")
        .accessibilityAddTraits(.isButton)
    }

    private var members: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(entry.members) { member in
                HStack(spacing: 8) {
                    Text(member.resolvedName)
                        .font(.body)
                        .fontWeight(highlighted ? .bold : .regular)
                        .foregroundStyle(FestivalText.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 4) {
                        ForEach(member.chartedInstruments) { instrument in
                            InstrumentIcon(instrument, size: 22)
                        }
                    }
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
