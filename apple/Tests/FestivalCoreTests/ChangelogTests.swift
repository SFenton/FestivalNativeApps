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

@Test func decodesOneVersionSectionPerEntry() throws {
    let entries = try Changelog.decode(Data(sampleDocument.utf8))
    #expect(entries.map(\.version) == ["2610.01.04", "2610.01.03", "2610.01.01"])
    #expect(entries.map(\.released) == [false, true, true])
    #expect(entries[0].sections == [ChangelogSection(title: "Version 2610.01.04", items: ["Rivals refresh correctly."])])
    #expect(entries[1].sections[0].items == ["The Item Shop badge is back.", "Songs load faster."])
    #expect(entries[1].sections[0].displayTitle == "Version 2610.01.03")
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

// MARK: - Tester sections

private let testerDocument = #"""
{"entries": [
  {"version": "2610.01.04", "released": false, "items": ["The first release of Festival Score Tracker for iPhone."],
   "testflight": {"since": "2610.01.03", "new": ["Quick Links follow page order.", " "], "release": null,
                  "vs_release": ["Close buttons are native.", "Quick Links follow page order."]}},
  {"version": "2610.01.03", "released": true, "items": ["Older."],
   "testflight": {"since": "2610.01.02", "new": [], "release": "2610.01.01", "vs_release": ["Kept."]}}
]}
"""#

@Test func decodesTesterSectionsForTheBuiltVersion() throws {
    let entries = try Changelog.decode(Data(testerDocument.utf8))
    #expect(entries[0].testerSections == [
        ChangelogSection(title: "New since 2610.01.03", items: ["Quick Links follow page order."]),
        ChangelogSection(title: "In this build vs. release (no release yet)",
                         items: ["Close buttons are native.", "Quick Links follow page order."]),
    ])
    // No "New since" section without new items; a named release appears in the heading.
    #expect(entries[1].testerSections.map(\.title) == ["In this build vs. release 2610.01.01"])
    // Older documents without the block decode with no tester sections.
    #expect(try Changelog.decode(Data(sampleDocument.utf8)).allSatisfy { $0.testerSections.isEmpty })
}

@Test func testersSeeTesterSectionsAndAppStoreSeesTheRelease() throws {
    let entries = try Changelog.decode(Data(testerDocument.utf8))
    let store = Changelog.displayEntries(entries, distribution: .appStore)
    #expect(store[0].sections.map(\.title) == ["Version 2610.01.04"])
    for channel in [AppDistribution.testFlight, .development] {
        let tester = Changelog.displayEntries(entries, distribution: channel)
        #expect(tester[0].sections.map(\.displayTitle)
            == ["New Since 2610.01.03", "In This Build vs. Release (No Release Yet)"])
    }
    // Entries without tester sections keep their release section for testers too.
    let plain = [ChangelogEntry(version: "1", sections: [ChangelogSection(title: "Version 1", items: ["x"])])]
    #expect(Changelog.displayEntries(plain, distribution: .testFlight)[0].sections.map(\.title) == ["Version 1"])
    // The show-once hash follows the release sections only.
    #expect(Changelog.hash(entries) == Changelog.hash(entries.map {
        ChangelogEntry(version: $0.version, released: $0.released, sections: $0.sections)
    }))
}

@Test func distributionOverridesAndStoreKitMapping() async {
    #expect(AppDistribution.parse("TestFlight") == .testFlight)
    #expect(AppDistribution.parse("appstore") == .appStore)
    #expect(AppDistribution.parse("bogus") == nil)
    #expect(AppDistribution.channel(for: .sandbox) == .testFlight)
    #expect(AppDistribution.channel(for: .xcode) == .development)
    #expect(AppDistribution.channel(for: .production) == .appStore)
    #expect(AppDistribution.appStore.showsTesterNotes == false)
    #expect(AppDistribution.testFlight.showsTesterNotes)
    #if DEBUG
    #expect(await AppDistribution.detect(environment: [:]) == .development)
    #expect(await AppDistribution.detect(environment: ["FST_DEBUG_DISTRIBUTION": "appstore"]) == .appStore)
    #endif
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
