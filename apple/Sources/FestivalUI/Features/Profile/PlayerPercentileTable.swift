import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - PlayerPercentileTableCard

/// One instrument's percentile table, its own card after the stat cards (web
/// `PlayerPercentileHeader`/`PlayerPercentileRow`, `InstrumentStatsSection.tsx`): a
/// "Percentile | Songs" header, then one row per non-empty "Top N%" band.
///
/// Each row opens Songs filtered to that band on this instrument (web
/// `instPercentileBucketUpdater`, ``SongsFilterPreset/percentileBucket(_:percentile:)``);
/// a viewed player is selected first, like every other stat link. While a Songs link
/// cannot be followed (selection paused, no root navigator) the rows are plain.
struct PlayerPercentileTableCard: View {
    let buckets: [PlayerPercentileBucket]
    let instrument: Instrument
    /// The page's rule for which links may be drawn (`PlayerProfileContent.tileLink`).
    let linkFilter: (PlayerStatLink?) -> PlayerStatLink?
    let onSelect: (PlayerStatLink) -> Void

    private var title: String { "\(instrument.label) Percentiles" }

    var body: some View {
        if !buckets.isEmpty {
            VStack(spacing: 0) {
                header
                ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                    if index > 0 {
                        Rectangle()
                            .fill(BrandTokens.glassBorder)
                            .frame(height: 1)
                            .accessibilityHidden(true)
                    }
                    row(bucket)
                }
            }
            .frame(maxWidth: .infinity)
            .festivalCard(cornerRadius: 16)
            // `.contain` first, or the identifier replaces every row's own.
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
            .accessibilityIdentifier("fst.player.percentiles.\(instrument.rawValue)")
            .quickLinkSection(QuickLinkSection(
                id: "percentiles:\(instrument.rawValue)", title: "Percentiles",
                icon: .system("chart.bar.xaxis"), depth: 1, spokenTitle: title
            ))
        }
    }

    /// Uppercase column captions (web `headerText`).
    private var header: some View {
        HStack {
            Text("Percentile")
            Spacer(minLength: 8)
            Text("Songs")
        }
        .font(.caption.weight(.semibold))
        .textCase(.uppercase)
        .foregroundStyle(FestivalText.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityHidden(true)
    }

    /// One band: a percentile pill and the song count, a Songs link when allowed.
    ///
    /// - Parameter bucket: Non-empty band.
    /// - Returns: The row.
    @ViewBuilder
    private func row(_ bucket: PlayerPercentileBucket) -> some View {
        let label = Self.label(bucket)
        let identifier = "fst.player.percentile-row.\(instrument.rawValue).\(bucket.topPercent)"
        if let link = linkFilter(PlayerStatLinks.percentileBucket(instrument, percentile: bucket.topPercent)) {
            Button {
                onSelect(link)
            } label: {
                rowContent(bucket, showsChevron: true)
            }
            .buttonStyle(PercentileRowButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue("\(bucket.count.formatted()) \(bucket.count == 1 ? "song" : "songs")")
            .accessibilityHint("Shows these songs in Songs")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(identifier)
        } else {
            rowContent(bucket, showsChevron: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityValue("\(bucket.count.formatted()) \(bucket.count == 1 ? "song" : "songs")")
                .accessibilityIdentifier(identifier)
        }
    }

    private func rowContent(_ bucket: PlayerPercentileBucket, showsChevron: Bool) -> some View {
        HStack(spacing: 10) {
            PercentilePill(topPercent: bucket.topPercent)
            Spacer(minLength: 8)
            Text(bucket.count.formatted())
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(FestivalText.primary)
            if showsChevron {
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(FestivalText.deemphasized)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }

    /// "Top N%", the web's `PercentilePill` text.
    ///
    /// - Parameter bucket: One non-empty band.
    /// - Returns: Row and VoiceOver label.
    nonisolated static func label(_ bucket: PlayerPercentileBucket) -> String {
        "Top \(bucket.topPercent)%"
    }
}

/// Web row press feedback (`rowItemPressed`: 4% white).
private struct PercentileRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.06 : 0))
    }
}

// MARK: - PercentilePill

/// The web's `PercentilePill`: "Top N%" in a small rounded pill; gold outline for the top
/// 5%, sheared gold outline (web `goldOutlineSkew`) for the top 1%, else a subtle fill.
struct PercentilePill: View {
    let topPercent: Int

    var body: some View {
        let isTopOne = topPercent <= 1
        let isGold = topPercent <= 5
        let shape = GoldSkewBadgeShape(skewed: isTopOne)
        Text("Top \(topPercent)%")
            .font(isGold ? (isTopOne ? .subheadline.bold().italic() : .subheadline.bold()) : .subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(isGold ? BrandTokens.gold : FestivalText.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(minWidth: 76)
            .background(isGold ? Color.clear : Color.white.opacity(0.1), in: shape)
            .overlay {
                if isGold { shape.stroke(BrandTokens.goldStroke, lineWidth: 2) }
            }
    }
}
