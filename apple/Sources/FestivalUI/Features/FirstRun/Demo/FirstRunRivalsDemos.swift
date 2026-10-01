import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - rivals-overview

/// Ported from `pages/rivals/firstRun/demo/RivalsOverviewDemo.tsx`: Above You / Below You rival
/// sections.
struct FirstRunRivalsOverviewDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Above You").font(.subheadline.weight(.bold)).foregroundStyle(FestivalText.primary)
            ForEach(Array(FirstRunDemoPool.rivalsAbove.enumerated()), id: \.element.id) { index, rival in
                FirstRunRivalRow(rival: rival, direction: .above).firstRunStagger(index)
            }
            Text("Below You").font(.subheadline.weight(.bold)).foregroundStyle(FestivalText.primary)
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
/// song-by-song comparison rows over real catalogue songs (the web's `useDemoSongs`) with its
/// static rank data. The web cycles categories on a timer; this static port shows "Closest
/// Battles", matching the carousel's "no timers while off-screen" rule.
struct FirstRunRivalsDetailDemo: View {
    private let ranks = FirstRunDemoPool.closestBattles

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Closest Battles").font(.subheadline.weight(.bold)).foregroundStyle(FestivalText.primary)
            FirstRunCatalogueSongs(count: ranks.count) { songs, session in
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    comparisonRow(song, session: session, ranks: ranks[index % ranks.count])
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func comparisonRow(
        _ song: Song, session: FestivalSession?, ranks: FirstRunDemoPool.RivalComparison
    ) -> some View {
        HStack(spacing: 12) {
            FirstRunSongArt(song: song, session: session)
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(song.title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(FestivalText.primary)
                    .lineLimit(1)
                    .firstRunRedacted(song)
                HStack(spacing: 10) {
                    Label("#\(ranks.userRank)", systemImage: "person.fill")
                        .foregroundStyle(BrandTokens.accentBlue)
                    Label("#\(ranks.rivalRank)", systemImage: "person.fill.badge.plus")
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
