import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - suggestions-category-card

/// Ported from `pages/suggestions/firstRun/demo/CategoryCardDemo.tsx`: one themed suggestion
/// card. The web rotates through several category templates on a timer; this static port shows
/// the first ("Almost Full Combo"), matching the carousel's "no timers while off-screen" rule.
struct FirstRunSuggestionsCategoryCardDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Almost Full Combo")
                    .font(.headline)
                    .foregroundStyle(FestivalText.primary)
                Text("Songs where you're just a few notes from a full combo.")
                    .font(.caption)
                    .foregroundStyle(FestivalText.primary)
            }
            ForEach(Array(FirstRunDemoPool.songs.prefix(2).enumerated()), id: \.element.id) { index, song in
                HStack(spacing: 12) {
                    InstrumentIcon(.lead, size: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title).font(.subheadline.weight(.semibold))
                            .foregroundStyle(FestivalText.primary)
                        Text(song.artist).font(.caption)
                            .foregroundStyle(FestivalText.primary)
                    }
                    Spacer(minLength: 0)
                    Text("\(98 - index * 2)%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrandTokens.accentBlue)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .festivalGlass(.card, cornerRadius: 16)
        .accessibilityHidden(true)
    }
}

// MARK: - suggestions-global-filter

/// Ported from `pages/suggestions/firstRun/demo/GlobalFilterDemo.tsx`: the suggestion-type
/// toggle list, all enabled.
struct FirstRunSuggestionsGlobalFilterDemo: View {
    private let types = ["Near Full Combo", "Percentile Push", "Unplayed Songs", "Stale Scores", "Variety Pack"]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(types, id: \.self) { type in
                toggleRow(type)
            }
        }
        .padding(14)
        .festivalGlass(.card, cornerRadius: 16)
        .accessibilityHidden(true)
    }

    private func toggleRow(_ label: String) -> some View {
        HStack {
            Text(label).foregroundStyle(FestivalText.primary).font(.subheadline)
            Spacer(minLength: 0)
            Capsule()
                .fill(BrandTokens.accentBlue)
                .frame(width: 40, height: 24)
                .overlay(Circle().fill(.white).frame(width: 20, height: 20).offset(x: 8))
        }
    }
}

// MARK: - suggestions-instrument-filter

/// Ported from `pages/suggestions/firstRun/demo/InstrumentFilterDemo.tsx`: the instrument
/// selector plus that instrument's own suggestion-type toggles.
struct FirstRunSuggestionsInstrumentFilterDemo: View {
    private let instruments: [Instrument] = [.lead, .bass, .drums, .vocals]
    private let types = ["Near Full Combo", "Percentile Push", "Unplayed Songs"]

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                ForEach(instruments, id: \.self) { instrument in
                    InstrumentIcon(instrument, size: 30)
                        .padding(6)
                        .background(
                            instrument == .lead ? BrandTokens.accentBlue.opacity(0.3) : .clear,
                            in: Circle()
                        )
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(types, id: \.self) { type in
                    HStack {
                        Text(type).foregroundStyle(FestivalText.primary).font(.subheadline)
                        Spacer(minLength: 0)
                        Capsule()
                            .fill(BrandTokens.accentBlue)
                            .frame(width: 36, height: 22)
                            .overlay(Circle().fill(.white).frame(width: 18, height: 18).offset(x: 7))
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .festivalGlass(.card, cornerRadius: 16)
        .accessibilityHidden(true)
    }
}

// MARK: - suggestions-infinite-scroll

/// Ported from `pages/suggestions/firstRun/demo/InfiniteScrollDemo.tsx`: a stack of suggestion
/// cards with a bottom fade hinting more content below. The web auto-scrolls the stack on a
/// `requestAnimationFrame` loop; this static port shows the resting view — a perpetual scroll
/// loop is exactly the "heavy" always-running animation the carousel rule excludes.
struct FirstRunSuggestionsInfiniteScrollDemo: View {
    private let cards: [(String, Instrument)] = [
        ("Near Full Combo", .lead), ("Percentile Push", .bass), ("Unplayed Songs", .drums),
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(cards, id: \.0) { title, instrument in
                HStack(spacing: 10) {
                    InstrumentIcon(instrument, size: 22)
                    Text(title).font(.subheadline.weight(.semibold))
                        .foregroundStyle(FestivalText.primary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .festivalGlass(.card, cornerRadius: 12)
            }
        }
        .mask(
            LinearGradient(
                stops: [.init(color: .black, location: 0.75), .init(color: .clear, location: 1)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .accessibilityHidden(true)
    }
}
