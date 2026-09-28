import Foundation
import Testing
@testable import FestivalCore

// MARK: - Fixtures

private func slide(
    id: String = "slide", version: Int = 1, title: String = "Title",
    description: String = "Description", contentKey: String? = nil,
    gate: FirstRunGate = .always
) -> FirstRunSlide {
    FirstRunSlide(
        id: id, version: version, title: title, description: description,
        contentKey: contentKey, gate: gate
    )
}

private func freshStore() -> FirstRunSeenStore {
    FirstRunSeenStore(defaults: UserDefaults(suiteName: "fst.firstRun.tests.\(UUID())")!)
}

// MARK: - Hashing

@Suite("FirstRunHashing")
struct FirstRunHashingTests {
    @Test("Same text always hashes the same")
    func deterministic() {
        #expect(FirstRunHashing.contentHash("abc") == FirstRunHashing.contentHash("abc"))
    }

    @Test("Different text hashes differently")
    func distinguishesContent() {
        #expect(FirstRunHashing.contentHash("abc") != FirstRunHashing.contentHash("abd"))
    }

    @Test("Empty string hashes to a stable, non-empty digest")
    func emptyString() {
        let hash = FirstRunHashing.contentHash("")
        #expect(!hash.isEmpty)
        #expect(hash == FirstRunHashing.contentHash(""))
    }
}

// MARK: - isUnseen

@Suite("FirstRunSlideEvaluator.isUnseen")
struct IsUnseenTests {
    @Test("No record at all is unseen")
    func missingRecord() {
        #expect(FirstRunSlideEvaluator.isUnseen(slide(), in: [:]))
    }

    @Test("Matching version and hash is seen")
    func matchingRecordIsSeen() {
        let target = slide(id: "s", version: 2, title: "T", description: "D")
        let record = FirstRunSlideEvaluator.seenRecord(for: target, at: .now)
        #expect(!FirstRunSlideEvaluator.isUnseen(target, in: ["s": record]))
    }

    @Test("A version bump makes a previously-seen slide unseen again")
    func versionBumpIsUnseen() {
        let old = slide(id: "s", version: 1, title: "T", description: "D")
        let record = FirstRunSlideEvaluator.seenRecord(for: old, at: .now)
        let bumped = slide(id: "s", version: 2, title: "T", description: "D")
        #expect(FirstRunSlideEvaluator.isUnseen(bumped, in: ["s": record]))
    }

    @Test("A lower stored version than the slide's is still unseen (defensive)")
    func recordVersionLowerThanSlideIsUnseen() {
        let record = FirstRunSeenRecord(
            version: 0, hash: FirstRunHashing.contentHash("TD"), seenAt: .now
        )
        let target = slide(id: "s", version: 3, title: "T", description: "D")
        #expect(FirstRunSlideEvaluator.isUnseen(target, in: ["s": record]))
    }

    @Test("Changed copy at the same version makes a slide unseen again")
    func contentChangeIsUnseen() {
        let original = slide(id: "s", version: 1, title: "Old Title", description: "D")
        let record = FirstRunSlideEvaluator.seenRecord(for: original, at: .now)
        let edited = slide(id: "s", version: 1, title: "New Title", description: "D")
        #expect(FirstRunSlideEvaluator.isUnseen(edited, in: ["s": record]))
    }

    @Test("contentKey overrides title+description for hashing, so copy edits under a shared key don't re-trigger")
    func contentKeySharesSeenState() {
        let mobile = slide(
            id: "s", version: 1, title: "Same title", description: "Mobile copy",
            contentKey: "shared-key"
        )
        let record = FirstRunSlideEvaluator.seenRecord(for: mobile, at: .now)
        let desktop = slide(
            id: "s", version: 1, title: "Same title", description: "Desktop copy",
            contentKey: "shared-key"
        )
        #expect(!FirstRunSlideEvaluator.isUnseen(desktop, in: ["s": record]))
    }
}

// MARK: - unseenSlides / gatePassingSlides / allSlides

@Suite("FirstRunSlideEvaluator slide selection")
struct SlideSelectionTests {
    @Test("Gate hides a slide whose predicate fails, independent of seen-state")
    func gateHidesSlide() {
        let gated = slide(id: "gated", gate: .hasPlayer)
        let ctx = FirstRunGateContext(hasPlayer: false)
        #expect(FirstRunSlideEvaluator.unseenSlides([gated], context: ctx, seen: [:]).isEmpty)
    }

    @Test("Gate passing + unseen slide is returned")
    func gatePassingUnseenIsReturned() {
        let gated = slide(id: "gated", gate: .hasPlayer)
        let ctx = FirstRunGateContext(hasPlayer: true)
        let result = FirstRunSlideEvaluator.unseenSlides([gated], context: ctx, seen: [:])
        #expect(result.map(\.id) == ["gated"])
    }

    @Test("ready == false suppresses everything, even brand-new slides")
    func notReadySuppressesAll() {
        let fresh = slide(id: "fresh")
        let ctx = FirstRunGateContext(ready: false)
        #expect(FirstRunSlideEvaluator.unseenSlides([fresh], context: ctx, seen: [:]).isEmpty)
    }

    @Test("A previously-seen page with one newly-added slide shows only the new slide")
    func onlyNewSlideShowsOnAnAlreadyDismissedPage() {
        let existing = slide(id: "existing", version: 1, title: "Existing", description: "D")
        let seenRecord = FirstRunSlideEvaluator.seenRecord(for: existing, at: .now)
        let brandNew = slide(id: "brand-new", version: 1, title: "New", description: "D2")
        let page = [existing, brandNew]
        let ctx = FirstRunGateContext()
        let result = FirstRunSlideEvaluator.unseenSlides(
            page, context: ctx, seen: ["existing": seenRecord]
        )
        #expect(result.map(\.id) == ["brand-new"])
    }

    @Test("alwaysShow bypasses seen-state but still respects gates")
    func alwaysShowBypassesSeenState() {
        let seenAlways = slide(id: "seen-always", gate: .always)
        let seenRecord = FirstRunSlideEvaluator.seenRecord(for: seenAlways, at: .now)
        let gatedOff = slide(id: "gated-off", gate: .hasPlayer)
        let ctx = FirstRunGateContext(hasPlayer: false, alwaysShow: true)
        let result = FirstRunSlideEvaluator.unseenSlides(
            [seenAlways, gatedOff], context: ctx, seen: ["seen-always": seenRecord]
        )
        #expect(result.map(\.id) == ["seen-always"])
    }

    @Test("gatePassingSlides (debug force) ignores seen-state entirely")
    func gatePassingSlidesIgnoresSeenState() {
        let seen = slide(id: "seen", gate: .always)
        let record = FirstRunSlideEvaluator.seenRecord(for: seen, at: .now)
        let result = FirstRunSlideEvaluator.gatePassingSlides(
            [seen], context: FirstRunGateContext()
        )
        #expect(result.map(\.id) == ["seen"])
        _ = record // seen-state is irrelevant to this path; no seen map is even passed in
    }

    @Test("gatePassingSlides still filters by gate")
    func gatePassingSlidesFiltersByGate() {
        let gated = slide(id: "gated", gate: .shopHighlightEnabled)
        let result = FirstRunSlideEvaluator.gatePassingSlides(
            [gated], context: FirstRunGateContext(shopHighlightEnabled: false)
        )
        #expect(result.isEmpty)
    }

    @Test("allSlides ignores both gates and seen-state, for Settings replay")
    func allSlidesIgnoresGatesAndSeenState() {
        let gated = slide(id: "gated", gate: .hasPlayer)
        let seenRecord = FirstRunSlideEvaluator.seenRecord(for: gated, at: .now)
        let result = FirstRunSlideEvaluator.allSlides([gated])
        #expect(result.map(\.id) == ["gated"])
        _ = seenRecord
    }
}

// MARK: - FirstRunSeenStore

@Suite("FirstRunSeenStore")
struct FirstRunSeenStoreTests {
    @Test("A fresh store loads empty")
    func freshStoreIsEmpty() {
        #expect(freshStore().load().isEmpty)
    }

    @Test("markSeen persists a record readable via load")
    func markSeenPersists() {
        let store = freshStore()
        let target = slide(id: "s", version: 2, title: "T", description: "D")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        store.markSeen([target], at: now)
        let loaded = store.load()
        #expect(loaded["s"]?.version == 2)
        #expect(loaded["s"]?.hash == FirstRunHashing.contentHash("TD"))
        #expect(loaded["s"]?.seenAt == now)
    }

    @Test("markSeen with an empty slide list is a no-op")
    func markSeenEmptyIsNoOp() {
        let store = freshStore()
        store.markSeen([])
        #expect(store.load().isEmpty)
    }

    @Test("save/load round-trips multiple records")
    func saveLoadRoundTrip() {
        let store = freshStore()
        let storage: FirstRunSeenStorage = [
            "a": FirstRunSeenRecord(version: 1, hash: "h1", seenAt: .now),
            "b": FirstRunSeenRecord(version: 2, hash: "h2", seenAt: .now),
        ]
        store.save(storage)
        #expect(store.load().count == 2)
    }

    @Test("resetPage removes only the named ids")
    func resetPageRemovesOnlyNamedIds() {
        let store = freshStore()
        store.markSeen([slide(id: "keep"), slide(id: "drop")])
        store.resetPage(["drop"])
        let loaded = store.load()
        #expect(loaded["keep"] != nil)
        #expect(loaded["drop"] == nil)
    }

    @Test("resetAll clears every record")
    func resetAllClearsEverything() {
        let store = freshStore()
        store.markSeen([slide(id: "a"), slide(id: "b")])
        store.resetAll()
        #expect(store.load().isEmpty)
    }

    @Test("Fully corrupt bytes recover to an empty store rather than crashing")
    func corruptDataRecoversToEmpty() {
        let defaults = UserDefaults(suiteName: "fst.firstRun.tests.\(UUID())")!
        defaults.set(Data("not json at all {{{".utf8), forKey: FirstRunSeenStore.storageKey)
        let store = FirstRunSeenStore(defaults: defaults)
        #expect(store.load().isEmpty)
    }

    @Test("An oversized payload is rejected wholesale")
    func oversizedPayloadRejected() {
        let defaults = UserDefaults(suiteName: "fst.firstRun.tests.\(UUID())")!
        let huge = Data(repeating: 0x41, count: 300 * 1024)
        defaults.set(huge, forKey: FirstRunSeenStore.storageKey)
        let store = FirstRunSeenStore(defaults: defaults)
        #expect(store.load().isEmpty)
    }

    @Test("Individually malformed records are dropped while valid ones are kept")
    func malformedRecordsAreDroppedIndividually() {
        let defaults = UserDefaults(suiteName: "fst.firstRun.tests.\(UUID())")!
        let json = """
        {
          "valid": {"version": 1, "hash": "abc", "seenAt": "2024-01-01T00:00:00Z"},
          "negative-version": {"version": -1, "hash": "abc", "seenAt": "2024-01-01T00:00:00Z"},
          "empty-hash": {"version": 1, "hash": "", "seenAt": "2024-01-01T00:00:00Z"}
        }
        """
        defaults.set(Data(json.utf8), forKey: FirstRunSeenStore.storageKey)
        let store = FirstRunSeenStore(defaults: defaults)
        let loaded = store.load()
        #expect(loaded["valid"] != nil)
        #expect(loaded["negative-version"] == nil)
        #expect(loaded["empty-hash"] == nil)
    }

    @Test("The store is bounded so it can never grow without limit")
    func boundedRecordCount() {
        let store = freshStore()
        let extra = 10
        for index in 0..<(FirstRunSeenStore.maxRecords + extra) {
            store.markSeen(
                [slide(id: "slide-\(index)")],
                at: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        #expect(store.load().count <= FirstRunSeenStore.maxRecords)
    }

    @Test("Bounding keeps the most recently-seen records over the oldest")
    func boundingKeepsMostRecent() {
        let store = freshStore()
        for index in 0..<(FirstRunSeenStore.maxRecords + 5) {
            store.markSeen(
                [slide(id: "slide-\(index)")],
                at: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let loaded = store.load()
        #expect(loaded["slide-0"] == nil)
        #expect(loaded["slide-\(FirstRunSeenStore.maxRecords + 4)"] != nil)
    }
}

// MARK: - FirstRunCatalog

@Suite("FirstRunCatalog")
struct FirstRunCatalogTests {
    @Test("Every page key resolves to a non-empty slide list")
    func everyPageHasSlides() {
        for page in FirstRunPageKey.allCases {
            #expect(!FirstRunCatalog.slides(for: page).isEmpty)
        }
    }

    @Test("Songs has all 9 ported slides")
    func songsHasNineSlides() {
        #expect(FirstRunCatalog.songs.count == 9)
    }

    @Test("Slide ids are unique within every page")
    func idsAreUniqueWithinEachPage() {
        for page in FirstRunPageKey.allCases {
            let ids = FirstRunCatalog.slides(for: page).map(\.id)
            #expect(Set(ids).count == ids.count)
        }
    }

    @Test("Slide ids are unique across the entire catalog")
    func idsAreGloballyUnique() {
        let allIds = FirstRunPageKey.allCases.flatMap { FirstRunCatalog.slides(for: $0) }.map(\.id)
        #expect(Set(allIds).count == allIds.count)
    }

    @Test("Shop-highlight-gated Songs slides are gated on shopHighlightEnabled")
    func songsShopSlidesAreGated() {
        let gatedIds = ["songs-shop-highlight", "songs-new-in-shop", "songs-leaving-tomorrow"]
        for id in gatedIds {
            let match = FirstRunCatalog.songs.first { $0.id == id }
            #expect(match?.gate == .shopHighlightEnabled)
        }
    }

    @Test("Player-dependent Songs slides are gated on hasPlayer")
    func songsPlayerSlidesAreGated() {
        let gatedIds = ["songs-filter", "songs-icons", "songs-metadata"]
        for id in gatedIds {
            let match = FirstRunCatalog.songs.first { $0.id == id }
            #expect(match?.gate == .hasPlayer)
        }
    }

    @Test("Experimental ranking metrics slide is gated on experimentalRanksEnabled")
    func leaderboardsExperimentalSlideIsGated() {
        let match = FirstRunCatalog.leaderboards.first {
            $0.id == "leaderboards-experimental-metrics"
        }
        #expect(match?.gate == .experimentalRanksEnabled)
    }

    @Test("Page key raw values match the web's registered pageKey strings")
    func pageKeyRawValuesMatchWeb() {
        let expected: Set<String> = [
            "songs", "songinfo", "playerhistory", "statistics", "suggestions",
            "leaderboards", "compete", "rivals", "shop",
        ]
        #expect(Set(FirstRunPageKey.allCases.map(\.rawValue)) == expected)
    }
}
