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

/// The web demos' swap is fade out → replace while hidden → fade in (issue #27); under Reduce
/// Motion the ticker holds demos still, and a requested swap only updates (issue #380).
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

    @Test("Under Reduce Motion a swap only updates, with no fade")
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

// MARK: - Ticker policy

@Suite("FirstRunDemoTickerPolicy")
struct FirstRunDemoTickerPolicyTests {
    @Test("The swap clock runs only on the visible slide with motion allowed")
    func runsOnlyWhenNothingHoldsStill() {
        #expect(FirstRunDemoTickerPolicy.runs(
            active: true, enabled: true, constrained: false, reduceMotion: false, stillBackground: false
        ))
        #expect(!FirstRunDemoTickerPolicy.runs(
            active: true, enabled: true, constrained: false, reduceMotion: true, stillBackground: false
        ))
        #expect(!FirstRunDemoTickerPolicy.runs(
            active: false, enabled: true, constrained: false, reduceMotion: false, stillBackground: false
        ))
        #expect(!FirstRunDemoTickerPolicy.runs(
            active: true, enabled: false, constrained: false, reduceMotion: false, stillBackground: false
        ))
        #expect(!FirstRunDemoTickerPolicy.runs(
            active: true, enabled: true, constrained: true, reduceMotion: false, stillBackground: false
        ))
        #expect(!FirstRunDemoTickerPolicy.runs(
            active: true, enabled: true, constrained: false, reduceMotion: false, stillBackground: true
        ))
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
///
/// Each host gets its own app storage, so a parallel test's `fst.accessibility.reduceMotion`
/// in the standard defaults cannot hold the active demo still (issue #380), and the active
/// demo is polled for its first swap rather than sampled once, so a busy parallel CI run has
/// time to fire the 2.5 s ticker.
@MainActor
@Test func activeBarSelectDemoAdvancesAndInactiveStaysStill() async throws {
    func frames(active: Bool) async throws -> (CGImage, CGImage) {
        let suiteName = "fst-fre-rotation-active-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        defer { storage.removePersistentDomain(forName: suiteName) }
        storage.set(false, forKey: "fst.accessibility.reduceMotion")
        let size = CGSize(width: 390, height: 300)
        let host = nativeHostedView(
            FirstRunSongInfoBarSelectDemo()
                .environment(\.firstRunDemoActive, active)
                .environment(\._accessibilityReduceMotion, false)
                .defaultAppStorage(storage)
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
        var after = try nativeHostedImage(host)
        if active {
            let deadline = ContinuousClock.now + .seconds(12)
            while nativeHostedSignature(after) == nativeHostedSignature(first), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(250))
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
                after = try nativeHostedImage(host)
            }
        }
        return (first, after)
    }

    let (activeBefore, activeAfter) = try await frames(active: true)
    #expect(nativeHostedSignature(activeBefore) != nativeHostedSignature(activeAfter), "selection did not move")
    let (stillBefore, stillAfter) = try await frames(active: false)
    #expect(nativeHostedSignature(stillBefore) == nativeHostedSignature(stillAfter), "inactive demo changed")
}

/// Reduce Motion, from the system or the app's own setting, holds a visible rotating demo on its
/// first state past the swap interval (issue #380, load-transition R6).
@MainActor
@Test(arguments: [(system: true, app: false), (system: false, app: true)])
func reduceMotionHoldsActiveRotatingDemoStill(setting: (system: Bool, app: Bool)) async throws {
    let suiteName = "fst-fre-rotation-\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suiteName))
    defer { storage.removePersistentDomain(forName: suiteName) }
    storage.set(setting.app, forKey: "fst.accessibility.reduceMotion")
    let size = CGSize(width: 390, height: 300)
    let host = nativeHostedView(
        FirstRunSongInfoBarSelectDemo()
            .environment(\.firstRunDemoActive, true)
            .environment(\._accessibilityReduceMotion, setting.system)
            .defaultAppStorage(storage)
            .padding(20)
            .frame(width: size.width, height: size.height)
            .background(BrandTokens.cardBackground)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let before = try await nativeHostedSettle(host, animationGrace: .milliseconds(200))
    // Past one 2.5 s cycle plus both 300 ms fades.
    try await Task.sleep(for: .milliseconds(3_400))
    let after = try nativeHostedImage(host)
    #expect(nativeHostedSignature(before) == nativeHostedSignature(after), "demo rotated under Reduce Motion")
}
#endif
