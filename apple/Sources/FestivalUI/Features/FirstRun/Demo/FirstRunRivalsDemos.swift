import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - rivals-overview

/// Ported from `pages/rivals/firstRun/demo/RivalsOverviewDemo.tsx`: Above You / Below You rival
/// sections. Like the web, each 5 s tick alternately fades the whole Above or Below group out
/// (with a 4 pt drop) and brings in the next rivals from its pool.
struct FirstRunRivalsOverviewDemo: View {
    var body: some View {
        FirstRunRivalGroupsDemo(visible: 3, staggers: true)
    }
}

/// Above You / Below You groups that alternate swapping on the web demos' clock
/// (`RivalsOverviewDemo` / `CompeteRivalsDemo`).
struct FirstRunRivalGroupsDemo: View {
    /// Rivals shown per group.
    let visible: Int
    /// Stagger the rows' first appearance (the Rivals page's version does).
    var staggers = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var above: FirstRunWindowRotation<FirstRunDemoPool.RivalEntry>
    @State private var below: FirstRunWindowRotation<FirstRunDemoPool.RivalEntry>
    @State private var nextGroup = 0
    @State private var fading: Set<Int> = []

    init(visible: Int, staggers: Bool = false) {
        self.visible = visible
        self.staggers = staggers
        _above = State(initialValue: FirstRunWindowRotation(pool: FirstRunDemoPool.rivalsAbove, count: visible))
        _below = State(initialValue: FirstRunWindowRotation(pool: FirstRunDemoPool.rivalsBelow, count: visible))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Web `delay={(idx++) * 80}` over headers and rows alike.
            Text("Above You").font(.subheadline.weight(.bold)).foregroundStyle(FestivalText.primary)
                .modifier(FirstRunOptionalStagger(index: 0, enabled: staggers))
            ForEach(Array(above.rows.enumerated()), id: \.offset) { index, rival in
                FirstRunRivalRow(rival: rival, direction: .above)
                    .firstRunSwapRow(0, key: rival.name, rise: 4)
                    .modifier(FirstRunOptionalStagger(index: index + 1, enabled: staggers))
            }
            Text("Below You").font(.subheadline.weight(.bold)).foregroundStyle(FestivalText.primary)
                .modifier(FirstRunOptionalStagger(index: visible + 1, enabled: staggers))
            ForEach(Array(below.rows.enumerated()), id: \.offset) { index, rival in
                FirstRunRivalRow(rival: rival, direction: .below)
                    .firstRunSwapRow(1, key: rival.name, rise: 4)
                    .modifier(FirstRunOptionalStagger(index: index + visible + 2, enabled: staggers))
            }
        }
        .environment(\.firstRunFadingRows, fading)
        .accessibilityHidden(true)
        .firstRunDemoTicker { await swap() }
    }

    private func swap() async {
        let group = nextGroup
        nextGroup = 1 - group
        await FirstRunDemoSwap.run(
            reduceMotion: reduceMotion,
            fadeOut: { fading = [group] },
            update: { if group == 0 { above.advance() } else { below.advance() } },
            fadeIn: { fading = [] }
        )
    }
}

/// ``SwiftUI/View/firstRunStagger(_:interval:)`` on the web rival demos' 80 ms cascade
/// when `enabled`.
private struct FirstRunOptionalStagger: ViewModifier {
    let index: Int
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled { content.firstRunStagger(index, interval: FirstRunMotion.rowStaggerSeconds) } else { content }
    }
}

// MARK: - rivals-instruments

/// Ported from `pages/rivals/firstRun/demo/RivalsInstrumentsDemo.tsx`: a rival section per
/// instrument. As on the web, each 5 s tick fades two of the six rows out (4 pt drop) and
/// brings in the next rival from that instrument and direction's pool.
struct FirstRunRivalsInstrumentsDemo: View {
    private static let instruments: [Instrument] = [.lead, .drums, .vocals]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Pool position per slot: instrument `i` above is slot `2i`, below is `2i + 1`.
    @State private var positions = Array(repeating: 0, count: 6)
    @State private var tick = 0
    @State private var lastSwapped: Set<Int> = []
    @State private var fading: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(Self.instruments.enumerated()), id: \.offset) { section, instrument in
                // The Rivals page's real section header; web `delay={(idx++) * 80}`.
                VStack(alignment: .leading, spacing: 6) {
                    InstrumentSectionHeader(instrument, title: "\(instrument.label) Rivals")
                        .firstRunStagger(section * 3, interval: FirstRunMotion.rowStaggerSeconds)
                    rivalRow(slot: section * 2, direction: .above)
                        .firstRunStagger(section * 3 + 1, interval: FirstRunMotion.rowStaggerSeconds)
                    rivalRow(slot: section * 2 + 1, direction: .below)
                        .firstRunStagger(section * 3 + 2, interval: FirstRunMotion.rowStaggerSeconds)
                }
            }
        }
        .environment(\.firstRunFadingRows, fading)
        .accessibilityHidden(true)
        .firstRunDemoTicker { await swap() }
    }

    @ViewBuilder
    private func rivalRow(slot: Int, direction: FirstRunRivalRow.Direction) -> some View {
        if let rival = Self.rival(slot: slot, position: positions[slot]) {
            FirstRunRivalRow(rival: rival, direction: direction)
                .firstRunSwapRow(slot, key: rival.name, rise: 4)
        }
    }

    /// The rival a slot shows at `position` in its pool.
    static func rival(slot: Int, position: Int) -> FirstRunDemoPool.RivalEntry? {
        guard instruments.indices.contains(slot / 2),
              let pools = FirstRunDemoPool.instrumentRivals[instruments[slot / 2]] else { return nil }
        let pool = slot.isMultiple(of: 2) ? pools.above : pools.below
        return pool.isEmpty ? nil : pool[position % pool.count]
    }

    private func swap() async {
        let slots = FirstRunDemoRotation.swapIndices(rowCount: positions.count, tick: tick, avoiding: lastSwapped)
        tick += 1
        lastSwapped = Set(slots)
        await FirstRunDemoSwap.run(
            reduceMotion: reduceMotion,
            fadeOut: { fading = Set(slots) },
            update: { for slot in slots { positions[slot] += 1 } },
            fadeIn: { fading = [] }
        )
    }
}

// MARK: - rivals-detail

/// Ported from `pages/rivals/firstRun/demo/RivalsDetailDemo.tsx`: a rivalry category's
/// song-by-song comparison rows over real catalogue songs (the web's `useDemoSongs`). As on the
/// web, every 5 s the whole card fades out (4 pt drop), some songs swap, the header moves to the
/// next category (Closest Battles → Almost Passed → … → Dominating Them) with its rank data,
/// and the rows restagger in.
struct FirstRunRivalsDetailDemo: View {
    var body: some View {
        FirstRunCatalogueSongs(count: 3, rotates: true, swapsWhole: true) { songs, session in
            FirstRunRivalsDetailCard(songs: songs, session: session)
        }
        .accessibilityHidden(true)
    }
}

/// The Rivals detail demo's category header and rows; reads the swap count to pick the
/// category, as the web advances `headerIdx` after each swap.
private struct FirstRunRivalsDetailCard: View {
    let songs: [Song]
    let session: FestivalSession?
    @Environment(\.firstRunSwapTick) private var tick

    var body: some View {
        let categories = FirstRunDemoPool.rivalDetailCategories
        let category = categories[tick % categories.count]
        VStack(alignment: .leading, spacing: 10) {
            Text(category.title).font(.subheadline.weight(.bold)).foregroundStyle(FestivalText.primary)
                .firstRunStagger(0)
            ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                comparisonRow(song, session: session, ranks: category.ranks[index % category.ranks.count])
                    .firstRunStagger(index + 1, interval: FirstRunMotion.detailStaggerSeconds)
            }
        }
        // Rows remount after each swap so they restagger in, like the web's `staggerKey`.
        .id(tick)
        .firstRunSwapRow(0, key: tick, rise: 4)
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
        .festivalCard(cornerRadius: 12)
    }
}
