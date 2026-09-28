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
/// Navigates to the viewed player's profile, matching the web client's row link
/// to `/player/:accountId` (or Statistics for the signed-in player, which native
/// resolves the same way once a selected-profile route exists).
struct AccountRankingRow: View {
    let entry: AccountRankingEntry
    let metric: RankingMetric
    /// True for the selected player's own row, whether it is highlighted in place
    /// among the top rows or shown as a separate spotlight below them — matching
    /// the web client's `isPlayer` accent treatment
    /// (`RankingCard.tsx`'s `playerEntryRow` style: a tinted fill plus border).
    var isSelected: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var displayName: String {
        entry.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown User"
    }

    var body: some View {
        Group {
            if entry.hasAccount {
                NavigationLink(
                    value: AppRoute.player(accountId: entry.accountId, displayName: entry.displayName)
                ) {
                    rowContent
                }
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
            HStack(alignment: .top, spacing: 12) {
                Text("#\(entry.rank(for: metric).formatted())")
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(BrandTokens.textSecondary)
                    .frame(minWidth: 36, alignment: .trailing)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.body)
                        .foregroundStyle(BrandTokens.textPrimary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    Text("\(entry.songsLabel(for: metric)) songs")
                        .font(.caption)
                        .foregroundStyle(BrandTokens.textSecondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(RankingFormatting.rating(entry.ratingValue(for: metric), metric: metric))
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(BrandTokens.textPrimary)
                    if let bayesian = entry.bayesianValue(for: metric) {
                        Text(RankingFormatting.bayesian(bayesian))
                            .font(.caption2)
                            .foregroundStyle(BrandTokens.textSecondary)
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, isSelected ? 8 : 0)
            .contentShape(Rectangle())
            .background(
                isSelected ? BrandTokens.accentPurple.opacity(0.18) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(BrandTokens.accentPurple, lineWidth: 1)
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
            ProgressView().controlSize(.small)
            Text("Loading your rank…")
                .font(.footnote)
                .foregroundStyle(BrandTokens.textSecondary)
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
            .font(.footnote)
            .foregroundStyle(BrandTokens.textSecondary)
    }
}

// MARK: - Band ranking row

/// One band-rankings row, shared by the overview cards and the full board.
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationLink(
            value: AppRoute.band(
                bandId: entry.bandId, name: nil,
                bandType: bandType.rawValue, teamKey: entry.teamKey
            )
        ) {
            HStack(alignment: .top, spacing: 12) {
                Text("#\(entry.rank(for: metric).formatted())")
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(BrandTokens.textSecondary)
                    .frame(minWidth: 36, alignment: .trailing)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.membersLabel)
                        .font(.body)
                        .foregroundStyle(BrandTokens.textPrimary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    Text("\(entry.songsLabel(for: metric)) songs")
                        .font(.caption)
                        .foregroundStyle(BrandTokens.textSecondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(
                        RankingFormatting.rating(
                            entry.ratingValue(for: metric), metric: metric.asRankingMetric
                        )
                    )
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(BrandTokens.textPrimary)
                    if let bayesian = entry.bayesianValue(for: metric) {
                        Text(RankingFormatting.bayesian(bayesian))
                            .font(.caption2)
                            .foregroundStyle(BrandTokens.textSecondary)
                    }
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("fst.band-rankings.row.\(entry.teamKey)")
    }
}

// MARK: - Skeleton

/// Redacted placeholder rows shown while a rankings request is in flight.
struct RankingsSkeletonRows: View {
    let count: Int

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { _ in
                HStack {
                    Capsule().frame(width: 28, height: 14)
                    Capsule().frame(width: 120, height: 14)
                    Spacer()
                    Capsule().frame(width: 56, height: 14)
                }
                .foregroundStyle(BrandTokens.surfaceMuted)
                .redacted(reason: .placeholder)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Pager

/// Discoverable first/previous/next/last paging control shared by every
/// paginated rankings board, matching the Solo chart's native pager.
struct RankingsPagerView: View {
    let page: Int
    let totalPages: Int
    let idPrefix: String
    let onChange: (Int) -> Void

    var body: some View {
        let first = pagerButton("First", enabled: page > 1) { onChange(1) }
            .accessibilityIdentifier("\(idPrefix).page-first")
        let previous = pagerButton("Previous", enabled: page > 1) { onChange(page - 1) }
            .accessibilityIdentifier("\(idPrefix).page-previous")
        let indicator = Text("\(page) / \(totalPages)")
            .monospacedDigit()
            .accessibilityIdentifier("\(idPrefix).page-info")
        let next = pagerButton("Next", enabled: page < totalPages) { onChange(page + 1) }
            .accessibilityIdentifier("\(idPrefix).page-next")
        let last = pagerButton("Last", enabled: page < totalPages) { onChange(totalPages) }
            .accessibilityIdentifier("\(idPrefix).page-last")
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                first
                previous
                Spacer(minLength: 0)
            }
            indicator
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                next
                last
            }
        }
        .padding(12)
        .background(BrandTokens.cardBackground)
    }

    /// Keep native pager actions scalable and large enough to touch on every row.
    ///
    /// - Parameters:
    ///   - title: Visible First, Previous, Next or Last action name.
    ///   - enabled: Whether the current page can move in that direction.
    ///   - action: Page transition to run when activated.
    /// - Returns: A native Button with a Fluent opaque plate and Dynamic Type text.
    private func pagerButton(
        _ title: String, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body)
                .foregroundStyle(
                    enabled ? BrandTokens.textPrimary : BrandTokens.textSecondary
                )
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
                .background(
                    BrandTokens.cardBackground,
                    in: RoundedRectangle(cornerRadius: 12)
                )
        }
        .buttonStyle(HighContrastPagerStyle())
        .disabled(!enabled)
    }
}

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
