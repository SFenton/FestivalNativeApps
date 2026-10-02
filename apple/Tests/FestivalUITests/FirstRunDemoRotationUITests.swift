import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
#if os(macOS)
import AppKit
import FestivalDesign
#endif

// MARK: - Swap sequence

/// The web demos' swap is fade out → replace while hidden → fade in; under Reduce Motion it is
/// a single cross-fade with no hidden phase (issue #27).
@Suite("FirstRunDemoSwap")
@MainActor
struct FirstRunDemoSwapTests {
    @Test("A normal swap fades out, updates, then fades in")
    func normalSequence() async {
        var steps: [String] = []
        await FirstRunDemoSwap.run(
            reduceMotion: false, seconds: 0.01,
            fadeOut: { steps.append("out") }, update: { steps.append("update") }, fadeIn: { steps.append("in") }
        )
        #expect(steps == ["out", "update", "in"])
    }

    @Test("Under Reduce Motion a swap only updates, as one cross-fade")
    func reduceMotionSequence() async {
        var steps: [String] = []
        await FirstRunDemoSwap.run(
            reduceMotion: true, seconds: 0.01,
            fadeOut: { steps.append("out") }, update: { steps.append("update") }, fadeIn: { steps.append("in") }
        )
        #expect(steps == ["update"])
    }

    @Test("A swap cancelled mid-fade still completes, so rows are never left hidden")
    func cancelledSwapCompletes() async {
        var steps: [String] = []
        let task = Task { @MainActor in
            await FirstRunDemoSwap.run(
                reduceMotion: false, seconds: 5,
                fadeOut: { steps.append("out") }, update: { steps.append("update") }, fadeIn: { steps.append("in") }
            )
        }
        task.cancel()
        await task.value
        #expect(steps == ["out", "update", "in"])
    }
}

// MARK: - Demo data

@Suite("First-run rotating demo data")
@MainActor
struct FirstRunRotatingDemoDataTests {
    @Test("The category card cycles the web's four templates in order")
    func categoryTemplates() {
        let templates = FirstRunSuggestionsCategoryCardDemo.templates
        #expect(templates.map(\.title) == [
            "Finish the Lead FCs", "Percentile Push: Bass", "FC These Next!", "New on Drums",
        ])
        #expect(templates.map(\.instrument) == [.lead, .bass, nil, .drums])
    }

    @Test("Each template shows the next window of songs, wrapping the pool")
    func categoryWindows() {
        let pool = FirstRunDemoSongs.placeholders(count: 8)
        #expect(FirstRunSuggestionsCategoryCardDemo.window(of: pool, template: 0).map(\.songId) == pool[0...1].map(\.songId))
        #expect(FirstRunSuggestionsCategoryCardDemo.window(of: pool, template: 3).map(\.songId) == pool[6...7].map(\.songId))
        let small = Array(pool.prefix(3))
        #expect(FirstRunSuggestionsCategoryCardDemo.window(of: small, template: 1).map(\.songId) == [small[2].songId, small[0].songId])
        #expect(FirstRunSuggestionsCategoryCardDemo.window(of: [], template: 2).isEmpty)
    }

    @Test("Template song details follow the web's songMeta")
    func categoryItems() {
        let songs = FirstRunDemoSongs.placeholders(count: 2)
        let templates = FirstRunSuggestionsCategoryCardDemo.templates
        #expect(templates[0].category(songs).songs.map(\.percent) == [100, 98])
        #expect(templates[1].category(songs).songs.map(\.percentileDisplay) == ["Top 3%", "Top 4%"])
        #expect(templates[2].category(songs).songs.map(\.instrument) == [.lead, .bass])
        #expect(templates[3].category(songs).songs.map(\.instrument) == [.drums, .drums])
    }

    @Test("Instrument rival slots walk their own above/below pools and wrap")
    func instrumentRivalSlots() {
        let names = (0..<4).map { FirstRunRivalsInstrumentsDemo.rival(slot: 0, position: $0)?.name }
        #expect(names == ["StageKnight", "FretPhenom", "NeonPick", "StageKnight"])
        #expect(FirstRunRivalsInstrumentsDemo.rival(slot: 3, position: 1)?.name == "OffBeat")
        #expect(FirstRunRivalsInstrumentsDemo.rival(slot: 5, position: 2)?.name == "KeyDrifter")
        #expect(FirstRunRivalsInstrumentsDemo.rival(slot: 6, position: 0) == nil)
    }

    @Test("Rival overview pools match the web's six above and six below")
    func rivalPools() {
        #expect(FirstRunDemoPool.rivalsAbove.map(\.name) == [
            "KeyDrifter", "DeepGroove", "SonicRush", "FretPhenom", "NeonPick", "BeatForge",
        ])
        #expect(FirstRunDemoPool.rivalsBelow.map(\.name) == [
            "DrumSurge", "ShredLord", "NoteCrush", "AxelStrike", "LowTide", "OffBeat",
        ])
    }

    @Test("Rivals detail cycles the web's six categories, four rank rows each")
    func rivalDetailCategories() {
        let categories = FirstRunDemoPool.rivalDetailCategories
        #expect(categories.map(\.title) == [
            "Closest Battles", "Almost Passed", "Slipping Away", "Barely Winning", "Pulling Forward",
            "Dominating Them",
        ])
        #expect(categories.allSatisfy { $0.ranks.count == 4 })
    }

    @Test("Metadata demo picks a web META_DATA record from the song's title")
    func metadataRecord() {
        let songs = FirstRunDemoSongs.placeholders(count: 3)
        for song in songs {
            let expected = Int(Int64(FirstRunDemoScorePattern.hash(song.title)).magnitude % 10)
            #expect(FirstRunNativeMetadataDemo.meta(for: song).score == FirstRunNativeMetadataDemo.records[expected].score)
        }
        #expect(FirstRunNativeMetadataDemo.records.count == 10)
        let gold = FirstRunNativeMetadataDemo.records[0].pills
        #expect(gold.contains(.stars(count: 5, gold: true)))
    }
}

// MARK: - Hosted rotation

#if os(macOS)
/// A demo on the visible page advances on the web clock; the same demo off-screen does not.
@MainActor
@Test func activeBarSelectDemoAdvancesAndInactiveStaysStill() async throws {
    func frames(active: Bool) async throws -> (CGImage, CGImage) {
        let size = CGSize(width: 390, height: 300)
        let host = nativeHostedView(
            FirstRunSongInfoBarSelectDemo()
                .environment(\.firstRunDemoActive, active)
                .padding(20)
                .frame(width: size.width, height: size.height)
                .background(BrandTokens.cardBackground)
                .preferredColorScheme(.dark),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        let first = try await nativeHostedSettle(host, animationGrace: .milliseconds(200))
        // One 2.5 s cycle plus the 300 ms fade-out and fade-in.
        try await Task.sleep(for: .milliseconds(3_400))
        return (first, try nativeHostedImage(host))
    }

    let (activeBefore, activeAfter) = try await frames(active: true)
    #expect(nativeHostedSignature(activeBefore) != nativeHostedSignature(activeAfter), "selection did not move")
    let (stillBefore, stillAfter) = try await frames(active: false)
    #expect(nativeHostedSignature(stillBefore) == nativeHostedSignature(stillAfter), "inactive demo changed")
}
#endif
