import Foundation
import SwiftUI
import FestivalCore
import FestivalDesign

/// Scalable score row shared by the native preview and the paginated Solo chart.
struct SongLeaderboardEntryRow: View {
    let entry: LeaderboardEntry
    /// The selected player's own row: rank and name bold (web `LeaderboardEntry`
    /// `isPlayer`, operator batch 6.42).
    var isPlayer = false
    /// Force the season column before the score. Sections normally decide it through
    /// their fitted `leaderboardRowColumns` (`showsSeason`: Song Detail cards and the
    /// Solo chart from 520 pt, `ScoreRowSeasonPolicy`, issues #32 and #37).
    var seasonColumn = false
    /// The catalogue's current season, whose pill is inverted like the web's.
    var currentSeason: Int?
    /// Draw the stars right after the score when the section's columns show stars
    /// (web `LeaderboardEntry` `starsAfterScore`, used by the band leaderboard's pinned
    /// footer, issue #306). Off for the Solo chart, whose rows never draw stars.
    var starsAfterScore = false
    /// Width probe only (``SongLeaderboardNameFit``): draw every one of these names on
    /// its own unscrolled line in the name column, so the row's ideal width is the
    /// one-line row the section's longest name needs. Nil for real rows.
    var probeNames: [RankingRowName]? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The section's shared rank/score widths and visible columns (issue #37).
    @Environment(\.leaderboardRowColumns) private var columns
    @ScaledMetric(relativeTo: .body) private var accuracyTextWidth: CGFloat = 56
    @ScaledMetric(relativeTo: .body) private var accuracyPillHeight: CGFloat = 24

    /// Vertical padding of a multi-row card, as the band card (`SongBandPreviewRow`).
    nonisolated static let stackedVerticalPadding: CGFloat = 10
    /// Space between a multi-row card's name and its rank and score line, as the band
    /// card's members and footer.
    nonisolated static let stackedLineSpacing: CGFloat = 8

    var body: some View {
        if columns?.stacksName == true, probeNames == nil, !dynamicTypeSize.isAccessibilitySize {
            stackedCard
        } else {
            lineLayout
        }
    }

    /// The name the row shows: the display name, or "Unknown User" without one.
    ///
    /// - Parameter entry: A board row.
    /// - Returns: The visible (and spoken) name.
    nonisolated static func displayName(_ entry: LeaderboardEntry) -> String {
        entry.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown User"
    }

    private var rank: some View {
        Text("#\(entry.rank.formatted())")
            .font(.body)
            .fontWeight(isPlayer ? .bold : .regular)
            .monospacedDigit()
            .foregroundStyle(FestivalText.primary)
    }

    /// One row line: rank, name, then the value columns; stacked at accessibility sizes.
    private var lineLayout: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        let valuesLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            HStack(spacing: 8) {
                LeaderboardColumnSlot(template: columns?.rankLabel) { rank }
                // One line that scrolls when it does not fit (wrapping at accessibility
                // sizes), so a long name never grows or overflows the row (issue #292).
                nameColumn.frame(maxWidth: .infinity, alignment: .leading)
            }
            valuesLayout { values }
        }
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
    }

    /// The multi-row card of a crowded trailing-pane board (owner-approved variant of
    /// leaderboard-row R3, #364): the full name on its own line, wrapping rather than
    /// scrolling, above the rank and the right-aligned score columns, laid out like the
    /// band card (`SongBandPreviewRow`) on the same boards. The shared rank and score
    /// slots keep every row and the pinned row aligned; VoiceOver still reads rank,
    /// name, then values.
    private var stackedCard: some View {
        VStack(alignment: .leading, spacing: Self.stackedLineSpacing) {
            LeaderboardNameText(name: Self.displayName(entry), emphasized: isPlayer, stacked: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilitySortPriority(1)
            HStack(spacing: 8) {
                LeaderboardColumnSlot(template: columns?.rankLabel) { rank }
                    .accessibilitySortPriority(2)
                Spacer(minLength: 0)
                values
            }
        }
        .padding(.vertical, Self.stackedVerticalPadding)
    }

    /// The name column: the scrolling row name, or the probe's stacked names.
    @ViewBuilder
    private var nameColumn: some View {
        if let probeNames {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(probeNames.enumerated()), id: \.offset) { _, row in
                    RankingRowLayout.nameText(row.name, emphasized: row.emphasized)
                        .fixedSize()
                }
            }
        } else {
            LeaderboardNameText(name: Self.displayName(entry), emphasized: isPlayer)
        }
    }

    /// Season, score, stars and accuracy, in the section's columns.
    @ViewBuilder
    private var values: some View {
        if seasonColumn || columns?.showsSeason == true {
            let season = entry.season.flatMap { $0 > 0 ? $0 : nil }
            ScoreSeasonPill(season: season, current: season != nil && season == currentSeason)
        }
        LeaderboardColumnSlot(template: columns?.scoreLabel, alignment: .trailing) {
            Text(entry.score.formatted())
                .font(.body)
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
        }
        if starsAfterScore, columns?.showsStars == true, let stars = entry.stars, stars > 0 {
            StarRating(stars: stars)
        }
        if let value = entry.accuracy {
            let color: Result<ScoreAccuracyTint, Error> = Result {
                try ScoreFormatting.accuracyTint(value)
            }
            switch color {
            case let .failure(error):
                Text("Accuracy unavailable: \(error.localizedDescription)")
                    .font(.body)
                    .foregroundStyle(FestivalText.primary)
                    .accessibilityIdentifier("fst.score.accuracy.\(entry.accountId)")
            case let .success(tint):
                let fullCombo = entry.isFullCombo == true
                let percent = "\(ScoreFormatting.accuracy(value))%"
                let spoken = fullCombo
                    ? "Full combo, accuracy \(percent)" : "Accuracy \(percent)"
                accuracyBadge(
                    text: dynamicTypeSize.isAccessibilitySize ? spoken : percent,
                    spoken: spoken,
                    fill: fullCombo ? Color.clear
                        : Color(
                            .sRGB,
                            red: Double(tint.red) / 255,
                            green: Double(tint.green) / 255,
                            blue: Double(tint.blue) / 255,
                            opacity: 0.25
                        ),
                    fullCombo: fullCombo
                )
            }
        } else if entry.isFullCombo == true {
            accuracyBadge(
                text: dynamicTypeSize.isAccessibilitySize ? "Full combo" : "FC",
                spoken: "Full combo; accuracy unavailable",
                fill: Color.clear, fullCombo: true
            )
        } else if !dynamicTypeSize.isAccessibilitySize {
            Color.clear
                .frame(
                    width: accuracyTextWidth + 16,
                    height: accuracyPillHeight
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Keep the compact and large-text accuracy states legible and independently spoken.
    ///
    /// A full combo uses the web's gold treatment (`goldOutlineSkew`): gold bold italic
    /// text in a transparent pill with a 2pt gold outline, skewed -8°; the percentage
    /// alone is shown, since the colour already means FC. Graded accuracy keeps white
    /// text on its 25%-opaque tint.
    ///
    /// - Parameters:
    ///   - text: Visible percentage (or "FC" when a full combo has no accuracy).
    ///   - spoken: Expanded VoiceOver label that never infers a missing FC flag.
    ///   - fill: Clear for an FC, or graded 25%-opaque accuracy color otherwise.
    ///   - fullCombo: Whether to use the source's gold full-combo outline.
    /// - Returns: One scalable, accessible score-accuracy pill.
    private func accuracyBadge(
        text: String, spoken: String, fill: Color, fullCombo: Bool
    ) -> some View {
        let compact = !dynamicTypeSize.isAccessibilitySize
        // Only the outline is skewed, and it is drawn inside the badge's frame, so the
        // accessibility frame stays the shared column slot (XCUITest column checks).
        let shape = GoldSkewBadgeShape(skewed: fullCombo && compact)
        let width: CGFloat? = compact ? accuracyTextWidth + 16 : nil
        let height: CGFloat? = compact ? accuracyPillHeight : nil
        // A plain Text element (hittable inside the Solo row's link) whose decorations
        // are drawn on the full, non-inset badge path: an inset `strokeBorder` became
        // the reported frame (94pt) and split the column, and a container element with
        // an accessibility content shape stopped being hittable inside the row link.
        return Text(text)
            .font(fullCombo ? .body.bold().italic() : .body)
            .foregroundStyle(fullCombo ? BrandTokens.gold : FestivalText.primary)
            .lineLimit(compact ? 1 : nil)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: !compact)
            .padding(compact ? 0 : 4)
            .frame(width: width, height: height)
            .background(fill, in: shape)
            .overlay {
                if fullCombo {
                    shape.stroke(BrandTokens.gold, lineWidth: 2)
                }
            }
            .accessibilityLabel(spoken)
            .accessibilityIdentifier("fst.score.accuracy.\(entry.accountId)")
    }

    /// The web's `GOLD_SKEW` (`skewX(-8deg)`) about the badge's vertical centre.
    ///
    /// - Parameter height: Rendered pill height, so the skew pivots on its middle.
    /// - Returns: Affine shear leaning the top edge right, like CSS `skewX(-8deg)`.
    nonisolated static func goldSkew(height: CGFloat) -> CGAffineTransform {
        let shear = tan(8 * CGFloat.pi / 180)
        return CGAffineTransform(a: 1, b: 0, c: -shear, d: 1, tx: shear * height / 2, ty: 0)
    }
}

/// Rounded badge outline, optionally sheared like the web's `GOLD_SKEW`, whose sheared
/// path still fits inside the proposed rect (it is inset horizontally before shearing).
struct GoldSkewBadgeShape: InsettableShape {
    /// Apply the -8° shear.
    var skewed: Bool
    /// Inset applied by `strokeBorder`.
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = max(0, 8 - insetAmount)
        guard skewed, box.width > 0, box.height > 0 else {
            return RoundedRectangle(cornerRadius: radius).path(in: box)
        }
        let shift = tan(8 * CGFloat.pi / 180) * box.height / 2
        let local = CGRect(
            x: shift, y: 0, width: max(0, box.width - 2 * shift), height: box.height
        )
        let transform = SongLeaderboardEntryRow.goldSkew(height: box.height)
            .concatenating(CGAffineTransform(translationX: box.minX, y: box.minY))
        return RoundedRectangle(cornerRadius: radius).path(in: local).applying(transform)
    }

    func inset(by amount: CGFloat) -> GoldSkewBadgeShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
