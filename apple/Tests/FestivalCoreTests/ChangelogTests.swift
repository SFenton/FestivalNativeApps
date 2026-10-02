import Foundation
import Testing
@testable import FestivalCore

// MARK: - Generated document

private let sampleDocument = #"""
{"schema": 1, "platform": "ios", "version": "2610.01.04", "baseline": "2610.01.03", "extra": true,
 "entries": [
  {"version": "2610.01.04", "released": false, "items": ["Rivals refresh correctly.", "  "]},
  {"version": "2610.01.03", "released": true, "items": ["The Item Shop badge is back.", "Songs load faster."]},
  {"version": "2610.01.02", "released": true, "items": []},
  {"version": "2610.01.01", "items": ["The first release of Festival Score Tracker for iPhone."]}
 ]}
"""#

@Test func decodesOneHeadedEntryPerVersion() throws {
    let entries = try Changelog.decode(Data(sampleDocument.utf8))
    #expect(entries.map(\.version) == ["2610.01.04", "2610.01.03", "2610.01.01"])
    #expect(entries.map(\.released) == [false, true, true])
    #expect(entries[0].heading == "Version 2610.01.04")
    #expect(entries[0].sections == [ChangelogSection(title: "", items: ["Rivals refresh correctly."])])
    #expect(entries[1].sections[0].items == ["The Item Shop badge is back.", "Songs load faster."])
    #expect(entries[1].displayHeading == "Version 2610.01.03")
}

@Test func decodeBoundsAndRejectsMalformedDocuments() throws {
    let longItem = String(repeating: "a", count: 2000)
    let many = (0..<50).map { #"{"version":"2610.\#($0)","items":["\#(longItem)"]}"# }.joined(separator: ",")
    let entries = try Changelog.decode(Data(#"{"entries":[\#(many)]}"#.utf8))
    #expect(entries.count == Changelog.maxEntries)
    #expect(entries[0].sections[0].items[0].count == Changelog.maxItemLength)
    #expect(throws: (any Error).self) { try Changelog.decode(Data("[]".utf8)) }
    #expect(throws: (any Error).self) { try Changelog.decode(Data(#"{"entries":[{"items":[]}]}"#.utf8)) }
}

@Test func loadReadsBundleResourceOrFallsBackToEmpty() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("changelog-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let bundle = try #require(Bundle(path: directory.path))
    #expect(Changelog.load(bundle: bundle).isEmpty)
    try Data("not json".utf8).write(to: directory.appendingPathComponent("WhatsNew.json"))
    #expect(Changelog.load(bundle: try #require(Bundle(path: directory.path))).isEmpty)
    try Data(sampleDocument.utf8).write(to: directory.appendingPathComponent("WhatsNew.json"))
    // Bundle caches lookups per instance path; a fresh directory avoids stale negative caching.
    let fresh = directory.appendingPathComponent("fresh", isDirectory: true)
    try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
    try Data(sampleDocument.utf8).write(to: fresh.appendingPathComponent("WhatsNew.json"))
    #expect(Changelog.load(bundle: try #require(Bundle(path: fresh.path))).count == 3)
}

@Test func checkedInPlaceholdersDecode() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    for app in ["iOS", "macOS"] {
        let data = try Data(contentsOf: root.appendingPathComponent("Apps/\(app)/WhatsNew.json"))
        #expect(try Changelog.decode(data).count == 1)
    }
}

// MARK: - Hash

@Test func changelogHashChangesWithContent() {
    let one = [ChangelogEntry(version: "2610.01.01", sections: [ChangelogSection(title: "Version 2610.01.01", items: ["y"])])]
    let two = [ChangelogEntry(version: "2610.01.02", sections: [ChangelogSection(title: "Version 2610.01.02", items: ["y"])])]
        + one
    #expect(Changelog.hash(one) != Changelog.hash(two))
    #expect(Changelog.hash([]) == Changelog.emptyHash)
    #expect(Changelog.hash([]) == "28y")  // "[]": 91 * 31 + 93 = 2914, "28y" in base 36
}

@Test func canonicalJSONMatchesJSONStringifyShape() {
    let entries = [ChangelogEntry(sections: [ChangelogSection(title: "A", items: ["b\"c", "d\\e"])])]
    #expect(
        Changelog.canonicalJSON(entries)
            == #"[{"sections":[{"title":"A","items":["b\"c","d\\e"]}]}]"#
    )
}

@Test func jsonStringEscapesControlCharacters() {
    #expect(Changelog.jsonString("a\nb\tc\r\u{08}\u{0C}\u{01}é") == #""a\nb\tc\r\b\f\u0001é""#)
}

// MARK: - Display

@Test func titleCaseHeadings() {
    #expect(Changelog.titleCase("SONG DETAILS") == "Song Details")
    #expect(Changelog.titleCase("ITEM SHOP") == "Item Shop")
    #expect(Changelog.titleCase("RIVALS AND OF THE WORLD") == "Rivals and of the World")
    #expect(Changelog.titleCase("THE  SHOP") == "The Shop")
    #expect(Changelog.titleCase("In this build vs. release (no release yet)")
        == "In This Build vs. Release (No Release Yet)")
    #expect(Changelog.titleCase("New since 2610.01.03") == "New Since 2610.01.03")
}

// MARK: - Category groups and tester list

/// A `versioning.py whats-new` document with `groups` and a `testflight` block.
private let groupedDocument = #"""
{"entries": [
  {"version": "2610.01.04", "released": false, "items": ["The first release of Festival Score Tracker for iPhone."],
   "groups": [{"category": null, "items": ["The first release of Festival Score Tracker for iPhone."]}],
   "testflight": {"since": "2610.01.03", "new": ["Songs: Rows load faster."], "release": null,
                  "vs_release": ["Songs: Rows load faster.", "Rivals: Cards are clearer.", "Fixed a crash."],
                  "groups": [{"category": "Songs", "items": ["Rows load faster.", " "]},
                             {"category": "Rivals", "items": ["Cards are clearer."]},
                             {"category": null, "items": ["Fixed a crash."]}]}},
  {"version": "2610.01.03", "released": true, "items": ["Item Shop: Badge is back.", "Songs: Faster."],
   "groups": [{"category": "Songs", "items": ["Faster."]}, {"category": "Item Shop", "items": ["Badge is back."]}],
   "testflight": {"release": "2610.01.01", "vs_release": ["Kept."], "groups": [{"category": null, "items": ["Kept."]}]}}
]}
"""#

@Test func decodesCategoryGroupsInDocumentOrderWithOtherLast() throws {
    let entries = try Changelog.decode(Data(groupedDocument.utf8))
    // Release notes: the version heading, then one section per category in the generator's order.
    #expect(entries[1].heading == "Version 2610.01.03")
    #expect(entries[1].sections == [
        ChangelogSection(title: "Songs", items: ["Faster."]),
        ChangelogSection(title: "Item Shop", items: ["Badge is back."]),
    ])
    // Uncategorized-only notes form one unheaded list, like TestFlight's text.
    #expect(entries[0].sections == [
        ChangelogSection(title: "", items: ["The first release of Festival Score Tracker for iPhone."]),
    ])
    // Tester list: every change since the release, grouped word for word; null category is "Other".
    #expect(entries[0].testerHeading == "Changes so far (no release yet)")
    #expect(entries[0].testerSections == [
        ChangelogSection(title: "Songs", items: ["Rows load faster."]),
        ChangelogSection(title: "Rivals", items: ["Cards are clearer."]),
        ChangelogSection(title: "Other", items: ["Fixed a crash."]),
    ])
    #expect(entries[1].testerHeading == "Changes since release 2610.01.01")
    #expect(entries[1].testerSections == [ChangelogSection(title: "", items: ["Kept."])])
}

@Test func documentsWithoutGroupsFallBackToFlatNotes() throws {
    let entries = try Changelog.decode(Data(sampleDocument.utf8))
    #expect(entries[0].sections == [ChangelogSection(title: "", items: ["Rivals refresh correctly."])])
    #expect(entries.allSatisfy { $0.testerSections.isEmpty && $0.testerHeading == nil })
    let legacy = #"{"entries":[{"version":"2","items":["A"],"testflight":{"release":"1","vs_release":["B"]}}]}"#
    let decoded = try Changelog.decode(Data(legacy.utf8))
    #expect(decoded[0].testerSections == [ChangelogSection(title: "", items: ["B"])])
    #expect(decoded[0].testerHeading == "Changes since release 1")
    // An empty tester list has no heading, so testers fall back to the release notes.
    let empty = #"{"entries":[{"version":"2","items":["A"],"testflight":{"vs_release":[],"groups":[]}}]}"#
    #expect(try Changelog.decode(Data(empty.utf8))[0].testerHeading == nil)
}

@Test func categorySectionsMergeRepeatsAndBoundBullets() {
    typealias Group = Changelog.WhatsNewDocument.Group
    let many = (0..<30).map { "Note \($0)." }
    let sections = Changelog.categorySections([
        Group(category: "Songs", items: many), Group(category: " ", items: ["Odd."]),
        Group(category: "Songs", items: many), Group(category: nil, items: ["Late."]),
    ], fallback: [])
    #expect(sections.map(\.title) == ["Songs", "Other"])
    #expect(sections.map(\.items.count).reduce(0, +) == Changelog.maxItems)
    #expect(sections[1].items == ["Odd."])
    #expect(Changelog.categorySections([], fallback: [" "]).isEmpty)
}

@Test func testerListKeepsEveryChangeSinceReleaseUpToItsOwnBound() throws {
    typealias Group = Changelog.WhatsNewDocument.Group
    // The real 2610.02.39 tester list has 44 notes: more than a release entry's 40, all kept.
    let notes = (0..<44).map { "\"Note \($0).\"" }.joined(separator: ",")
    let document = """
    {"entries":[{"version":"2","released":false,"items":["Store."],
      "testflight":{"release":null,"vs_release":[],"groups":[{"category":"Songs","items":[\(notes)]}]}}]}
    """
    let entries = try Changelog.decode(Data(document.utf8))
    let tester = Changelog.displayEntries(entries, distribution: .testFlight)
    #expect(tester[0].sections.flatMap(\.items).count == 44)
    let many = (0..<200).map { "Note \($0)." }
    let capped = Changelog.categorySections(
        [Group(category: "Songs", items: many)], fallback: [], limit: Changelog.maxTesterItems)
    #expect(capped.flatMap(\.items).count == Changelog.maxTesterItems)
    let groups = (0..<30).map { Group(category: "C\($0)", items: ["x"]) }
    #expect(Changelog.categorySections(groups, fallback: []).count == Changelog.maxGroups)
}

@Test func testersSeeTheTesterListAndAppStoreSeesTheRelease() throws {
    let entries = try Changelog.decode(Data(groupedDocument.utf8))
    let store = Changelog.displayEntries(entries, distribution: .appStore)
    #expect(store[0].displayHeading == "Version 2610.01.04")
    #expect(store[0].sections.map(\.items) == [["The first release of Festival Score Tracker for iPhone."]])
    for channel in [AppDistribution.testFlight, .development] {
        let tester = Changelog.displayEntries(entries, distribution: channel)
        #expect(tester[0].displayHeading == "Changes So Far (No Release Yet)")
        #expect(tester[0].sections.map(\.displayTitle) == ["Songs", "Rivals", "Other"])
        #expect(tester[1].displayHeading == "Changes Since Release 2610.01.01")
    }
    // Entries without tester sections keep their release notes for testers too.
    let plain = [ChangelogEntry(version: "1", heading: "Version 1", sections: [ChangelogSection(title: "", items: ["x"])])]
    #expect(Changelog.displayEntries(plain, distribution: .testFlight)[0].heading == "Version 1")
    // The show-once hash follows the release notes only.
    #expect(Changelog.hash(entries) == Changelog.hash(entries.map {
        ChangelogEntry(version: $0.version, released: $0.released, heading: $0.heading, sections: $0.sections)
    }))
}

@Test func hashIncludesTheVersionHeading() {
    let section = [ChangelogSection(title: "Songs", items: ["y"])]
    #expect(Changelog.hash([ChangelogEntry(heading: "Version 1", sections: section)])
        != Changelog.hash([ChangelogEntry(heading: "Version 2", sections: section)]))
    #expect(Changelog.canonicalJSON([ChangelogEntry(heading: "V", sections: section)])
        == #"[{"title":"V","sections":[{"title":"Songs","items":["y"]}]}]"#)
}

// MARK: - Install channel

@Test func distributionOverridesAndStoreKitMapping() {
    #expect(AppDistribution.parse("TestFlight") == .testFlight)
    #expect(AppDistribution.parse("appstore") == .appStore)
    #expect(AppDistribution.parse("bogus") == nil)
    #expect(AppDistribution.channel(for: .sandbox) == .testFlight)
    #expect(AppDistribution.channel(for: .xcode) == .development)
    #expect(AppDistribution.channel(for: .production) == .appStore)
    #expect(AppDistribution.appStore.showsTesterNotes == false)
    #expect(AppDistribution.testFlight.showsTesterNotes)
    let storeKit = URL(fileURLWithPath: "/app/StoreKit")
    #expect(AppDistribution.receiptChannel(storeKit.appendingPathComponent("sandboxReceipt")) == .testFlight)
    #expect(AppDistribution.receiptChannel(storeKit.appendingPathComponent("receipt")) == nil)
    #expect(AppDistribution.receiptChannel(nil) == nil)
}

@MainActor
@Test func liveResolverHonorsTheDebugOverride() async {
    #if DEBUG
    #expect(await AppDistributionResolver.live(environment: [:]).current() == .development)
    #expect(await AppDistributionResolver.live(environment: ["FST_DEBUG_DISTRIBUTION": "appstore"]).current() == .appStore)
    #expect(await AppDistributionResolver.live(environment: ["FST_DEBUG_DISTRIBUTION": "testflight"]).current() == .testFlight)
    #endif
}

/// A StoreKit probe the test answers by hand, counting calls.
private actor ManualProbe {
    private var waiters: [CheckedContinuation<AppDistribution?, Never>] = []
    private(set) var calls = 0

    func next() async -> AppDistribution? {
        calls += 1
        return await withCheckedContinuation { waiters.append($0) }
    }

    func answer(_ value: AppDistribution?) {
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume(returning: value) }
    }
}

@MainActor
@Test func sandboxReceiptIsTestFlightWithoutStoreKit() async {
    let resolver = AppDistributionResolver(
        receiptURL: { URL(fileURLWithPath: "/app/StoreKit/sandboxReceipt") },
        storeKit: { Issue.record("StoreKit must not be asked"); return .appStore }
    )
    #expect(resolver.channel == nil)
    #expect(await resolver.current() == .testFlight)
    #expect(resolver.channel == .testFlight && resolver.isFinal)
}

@MainActor
@Test func storeKitAnswerIsCachedForTheProcess() async throws {
    let probe = ManualProbe()
    let resolver = AppDistributionResolver(receiptURL: { nil }, storeKit: { await probe.next() }, timeout: .seconds(30))
    async let first = resolver.current()
    while await probe.calls == 0 { try await Task.sleep(for: .milliseconds(2)) }
    #expect(resolver.channel == nil)  // pending: views show a spinner, not the App Store notes
    await probe.answer(.testFlight)
    #expect(await first == .testFlight)
    #expect(await resolver.current() == .testFlight)
    #expect(await probe.calls == 1)
}

@MainActor
@Test func timeoutIsProvisionalAndALateAnswerUpgradesIt() async throws {
    let probe = ManualProbe()
    let resolver = AppDistributionResolver(
        receiptURL: { URL(fileURLWithPath: "/app/StoreKit/receipt") }, storeKit: { await probe.next() },
        timeout: .milliseconds(50)
    )
    #expect(await resolver.current() == .appStore)
    #expect(resolver.channel == .appStore && !resolver.isFinal)
    // A second call reuses the still-running probe instead of starting another.
    #expect(await resolver.current() == .appStore)
    #expect(await probe.calls == 1)
    await probe.answer(.testFlight)
    for _ in 0..<200 where !resolver.isFinal { try await Task.sleep(for: .milliseconds(5)) }
    #expect(resolver.channel == .testFlight && resolver.isFinal)
    #expect(await resolver.current() == .testFlight)
}

@MainActor
@Test func storeKitErrorIsRetriedOnTheNextCall() async throws {
    let probe = ManualProbe()
    let resolver = AppDistributionResolver(receiptURL: { nil }, storeKit: { await probe.next() }, timeout: .seconds(30))
    async let failed = resolver.current()
    while await probe.calls == 0 { try await Task.sleep(for: .milliseconds(2)) }
    await probe.answer(nil)
    #expect(await failed == .appStore)
    #expect(resolver.channel == .appStore && !resolver.isFinal)
    async let retried = resolver.current()
    while await probe.calls < 2 { try await Task.sleep(for: .milliseconds(2)) }
    await probe.answer(.appStore)
    #expect(await retried == .appStore)
    #expect(resolver.isFinal)
}

@Test func displayEntriesDropManualContent() {
    let entries = [
        ChangelogEntry(sections: [
            ChangelogSection(title: "MANUAL", items: ["New manual pages."]),
            ChangelogSection(title: "SONGS", items: ["See the Manual for help.", "Faster rows."]),
            ChangelogSection(title: "OTHER", items: ["Read the manual."]),
        ]),
        ChangelogEntry(sections: [ChangelogSection(title: "MANUAL", items: ["x"])]),
    ]
    let shown = Changelog.displayEntries(entries)
    #expect(shown.count == 1)
    #expect(shown[0].sections.map(\.title) == ["SONGS"])
    #expect(shown[0].sections[0].items == ["Faster rows."])
    #expect(Changelog.mentionsManual("Manually") == false)
    let versioned = [ChangelogEntry(version: "2610.01.02", released: false, sections: [
        ChangelogSection(title: "Version 2610.01.02", items: ["Faster rows.", "Manual removed."]),
    ])]
    let kept = Changelog.displayEntries(versioned)
    #expect(kept.map(\.version) == ["2610.01.02"])
    #expect(kept.map(\.released) == [false])
    #expect(kept[0].sections[0].items == ["Faster rows."])
}

// MARK: - Seen store

private func isolatedDefaults() -> UserDefaults {
    let name = "changelog-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Test func seenStoreShowsUntilDismissedForCurrentHash() {
    let defaults = isolatedDefaults()
    let store = ChangelogSeenStore(defaults: defaults)
    #expect(store.load() == nil)
    #expect(store.shouldShow(hash: "abc"))
    store.markSeen(version: "2610.01.01", hash: "abc")
    #expect(store.load() == ChangelogSeenRecord(version: "2610.01.01", hash: "abc"))
    #expect(store.shouldShow(hash: "abc") == false)
    #expect(store.shouldShow(hash: "other"))
    store.reset()
    #expect(store.shouldShow(hash: "abc"))
}

@Test func seenStoreNeverShowsAnEmptyChangelog() {
    let store = ChangelogSeenStore(defaults: isolatedDefaults())
    #expect(store.shouldShow(hash: Changelog.emptyHash) == false)
}

@Test func seenStoreTreatsCorruptOrOversizedDataAsUnseen() {
    let defaults = isolatedDefaults()
    let store = ChangelogSeenStore(defaults: defaults)
    defaults.set(Data("not json".utf8), forKey: ChangelogSeenStore.storageKey)
    #expect(store.load() == nil)
    defaults.set(Data(repeating: 0x20, count: 2048), forKey: ChangelogSeenStore.storageKey)
    #expect(store.load() == nil)
    defaults.set(
        Data(#"{"version":"1","hash":""}"#.utf8), forKey: ChangelogSeenStore.storageKey
    )
    #expect(store.load() == nil)
    defaults.set(
        Data(#"{"version":"1","hash":"\#(String(repeating: "a", count: 40))"}"#.utf8),
        forKey: ChangelogSeenStore.storageKey
    )
    #expect(store.shouldShow(hash: "abc"))
    store.markSeen(version: String(repeating: "9", count: 100))
    #expect(store.load()?.version.count == 64)
}
