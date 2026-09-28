import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - rivals-overview

/// Ported from `pages/rivals/firstRun/demo/RivalsOverviewDemo.tsx`: Above You / Below You rival
/// sections.
struct FirstRunRivalsOverviewDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Above You").font(.subheadline.weight(.bold)).foregroundStyle(BrandTokens.textPrimary)
            ForEach(Array(FirstRunDemoPool.rivalsAbove.enumerated()), id: \.element.id) { index, rival in
                FirstRunRivalRow(rival: rival, direction: .above).firstRunStagger(index)
            }
            Text("Below You").font(.subheadline.weight(.bold)).foregroundStyle(BrandTokens.textPrimary)
            ForEach(Array(FirstRunDemoPool.rivalsBelow.enumerated()), id: \.element.id) { index, rival in
                FirstRunRivalRow(rival: rival, direction: .below).firstRunStagger(index + FirstRunDemoPool.rivalsAbove.count)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - rivals-instruments

/// Ported from `pages/rivals/firstRun/demo/RivalsInstrumentsDemo.tsx`: a rival section per
/// instrument.
struct FirstRunRivalsInstrumentsDemo: View {
    private let instruments: [Instrument] = [.lead, .drums, .vocals]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(instruments, id: \.self) { instrument in
                if let pair = FirstRunDemoPool.instrumentRivals[instrument] {
                    VStack(alignment: .leading, spacing: 6) {
                        FirstRunInstrumentHeader(instrument: instrument)
                        FirstRunRivalRow(rival: pair.above, direction: .above)
                        FirstRunRivalRow(rival: pair.below, direction: .below)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - rivals-detail

/// Ported from `pages/rivals/firstRun/demo/RivalsDetailDemo.tsx`: one rivalry category's
/// song-by-song comparison rows. The web cycles categories on a timer; this static port shows
/// "Closest Battles", matching the carousel's "no timers while off-screen" rule.
struct FirstRunRivalsDetailDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Closest Battles").font(.subheadline.weight(.bold)).foregroundStyle(BrandTokens.textPrimary)
            ForEach(FirstRunDemoPool.closestBattles) { comparison in
                comparisonRow(comparison)
            }
        }
        .accessibilityHidden(true)
    }

    private func comparisonRow(_ comparison: FirstRunDemoPool.RivalComparison) -> some View {
        HStack(spacing: 12) {
            FirstRunAlbumArtPlaceholder()
            VStack(alignment: .leading, spacing: 2) {
                Text(comparison.title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrandTokens.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Label("#\(comparison.userRank)", systemImage: "person.fill")
                        .foregroundStyle(BrandTokens.accentBlue)
                    Label("#\(comparison.rivalRank)", systemImage: "person.fill.badge.plus")
                        .foregroundStyle(BrandTokens.statusRed)
                }
                .font(.caption2.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .festivalGlass(.card, cornerRadius: 12)
    }
}
