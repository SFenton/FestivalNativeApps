import Foundation
import Testing
@testable import FestivalCore

// MARK: - Hash parity

@Test func changelogHashMatchesWebPrecomputedHash() {
    #expect(Changelog.currentHash == Changelog.webHash)
}

@Test func changelogHashChangesWithContent() {
    let edited = [ChangelogEntry(sections: [ChangelogSection(title: "X", items: ["y"])])]
    #expect(Changelog.hash(edited) != Changelog.webHash)
    #expect(Changelog.hash([]) == Changelog.hash([]))
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
    #expect(Changelog.entries[0].sections.map(\.displayTitle).first == "Item Shop")
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
    // The shipped data has no Manual content, so nothing is dropped.
    #expect(Changelog.displayEntries() == Changelog.entries)
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
    #expect(store.shouldShow())
    store.markSeen(version: "1.0")
    #expect(store.load() == ChangelogSeenRecord(version: "1.0", hash: Changelog.currentHash))
    #expect(store.shouldShow() == false)
    #expect(store.shouldShow(hash: "other"))
    store.reset()
    #expect(store.shouldShow())
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
    #expect(store.shouldShow())
    store.markSeen(version: String(repeating: "9", count: 100))
    #expect(store.load()?.version.count == 64)
}
