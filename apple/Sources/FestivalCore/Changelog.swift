import Foundation

// MARK: - Model

/// One titled group of changelog bullets, ported from the web's `ChangelogSection`
/// (`FortniteFestivalWeb/src/changelog.ts`).
public struct ChangelogSection: Sendable, Equatable, Identifiable {
    /// Heading exactly as the web data spells it (upper case; the web upper-cases in CSS).
    public let title: String
    /// Bullet sentences, in web order.
    public let items: [String]

    public var id: String { title }

    /// Create a section.
    ///
    /// - Parameters:
    ///   - title: Heading as written in the web data.
    ///   - items: Bullet sentences.
    public init(title: String, items: [String]) {
        self.title = title
        self.items = items
    }

    /// Native Title Case heading ("SONG DETAILS" → "Song Details").
    public var displayTitle: String { Changelog.titleCase(title) }
}

/// One release's worth of changelog sections, the web's `ChangelogEntry`.
public struct ChangelogEntry: Sendable, Equatable {
    /// Sections in web order.
    public let sections: [ChangelogSection]

    /// Create an entry.
    ///
    /// - Parameter sections: Sections in web order.
    public init(sections: [ChangelogSection]) {
        self.sections = sections
    }
}

// MARK: - Catalog

/// The "What's New" changelog, ported verbatim from the web so its content hash matches the
/// web's `changelogHash()` (`FortniteFestivalWeb/src/changelogHash.ts`).
///
/// The web shows the card whenever the stored hash differs from the current one; natives use
/// the same rule (see `ChangelogSeenStore`). Keep `entries` byte-identical to the web data and
/// update `webHash` in the same commit; `ChangelogTests` fails if the two drift.
public enum Changelog {
    /// Web release the entries were copied from (`package.json` version at capture time).
    public static let webVersion = "0.1.133"

    /// The web's precomputed `CURRENT_CHANGELOG_HASH` for `entries`.
    public static let webHash = "-6p8bh3"

    /// Changelog entries exactly as the web ships them.
    public static let entries: [ChangelogEntry] = [
        ChangelogEntry(sections: [
            ChangelogSection(title: "ITEM SHOP", items: [
                "Newly released songs in the Item Shop have a gold pulse on Songs Page and Song Details.",
                "Songs in the Item Shop that aren't leaving tomorrow now have a green pulse, to match "
                    + "the gold/green/red styles of the instrument chips on Songs Page.",
            ]),
            ChangelogSection(title: "MOBILE", items: [
                "FAB buttons and other dock buttons now animate in for a more visually pleasing experience.",
                "Fixed a bug in search modal where dismissing the keyboard after results show did not "
                    + "expand results view appropriately.",
            ]),
            ChangelogSection(title: "SONG DETAILS", items: [
                "Fixed a bug where leaderboard ranks did not reflect the actual Epic leaderboard value "
                    + "in some cases.",
            ]),
            ChangelogSection(title: "NOTIFICATIONS", items: [
                "Fixed a bug where notification alerts would reset when you re-open the web browser.",
                "Added support for switching profiles/bands and returning to a different profile/band "
                    + "and seeing the appropriate amount of unread notifications, instead of all of them.",
            ]),
            ChangelogSection(title: "RIVALS", items: [
                "Improved performance when viewing a Rival for the first time.",
                "Improved availability of Rivals during scrape.",
            ]),
            ChangelogSection(title: "LEADERBOARDS", items: [
                "Changed to instrument icons on combo leaderboards instead of \"Lead + ...\" text.",
                "Updated FAB dock on mobile to match other pages.",
            ]),
        ]),
    ]

    /// Content hash of the current entries; drives "show once per changelog".
    public static var currentHash: String { hash(entries) }

    // MARK: Display

    /// Entries as natives display them: the deprecated Manual feature is never advertised, so
    /// any section titled Manual or bullet naming it is dropped, and empty sections removed.
    ///
    /// - Parameter entries: Web-identical entries.
    /// - Returns: Entries safe to render natively.
    public static func displayEntries(_ entries: [ChangelogEntry] = entries) -> [ChangelogEntry] {
        entries.compactMap { entry in
            let sections = entry.sections.compactMap { section -> ChangelogSection? in
                guard !mentionsManual(section.title) else { return nil }
                let items = section.items.filter { !mentionsManual($0) }
                return items.isEmpty ? nil : ChangelogSection(title: section.title, items: items)
            }
            return sections.isEmpty ? nil : ChangelogEntry(sections: sections)
        }
    }

    /// Whether text refers to the deprecated in-app Manual.
    ///
    /// - Parameter text: Heading or bullet.
    /// - Returns: True when the word "manual" appears as a whole word, any case.
    static func mentionsManual(_ text: String) -> Bool {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .contains("manual")
    }

    /// Words kept lower case inside a Title Case heading (never the first word).
    private static let minorWords: Set<String> = [
        "a", "an", "and", "as", "at", "by", "for", "in", "of", "on", "or", "the", "to", "vs",
    ]

    /// Convert a heading to Title Case.
    ///
    /// - Parameter text: Heading in any case.
    /// - Returns: Title Case heading with minor words lower-cased after the first word.
    public static func titleCase(_ text: String) -> String {
        text.lowercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .enumerated()
            .map { index, word in
                let lower = String(word)
                if index > 0 && minorWords.contains(lower) { return lower }
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }

    // MARK: Hash (web-compatible)

    /// The web's `calculateChangelogHash`: a 32-bit `((h << 5) - h) + code` over the UTF-16
    /// code units of `JSON.stringify(entries)`, printed in base 36 with a sign.
    ///
    /// - Parameter entries: Entries to hash.
    /// - Returns: Hash string identical to the web's for identical data.
    public static func hash(_ entries: [ChangelogEntry]) -> String {
        var value: Int32 = 0
        for unit in canonicalJSON(entries).utf16 {
            value = (value &<< 5) &- value &+ Int32(unit)
        }
        return String(value, radix: 36)
    }

    /// Reproduce `JSON.stringify` for the entry array (no whitespace, key order
    /// `sections` → `title`, `items`).
    ///
    /// - Parameter entries: Entries to serialize.
    /// - Returns: Compact JSON text.
    static func canonicalJSON(_ entries: [ChangelogEntry]) -> String {
        let body = entries.map { entry in
            let sections = entry.sections.map { section in
                let items = section.items.map(jsonString).joined(separator: ",")
                return "{\"title\":\(jsonString(section.title)),\"items\":[\(items)]}"
            }
            return "{\"sections\":[\(sections.joined(separator: ","))]}"
        }
        return "[\(body.joined(separator: ","))]"
    }

    /// Quote a string the way `JSON.stringify` does (escapes `"`, `\` and control characters;
    /// leaves other Unicode as-is).
    ///
    /// - Parameter text: Raw string.
    /// - Returns: Quoted JSON string literal.
    static func jsonString(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}

// MARK: - Seen state

/// What the user last dismissed, the web's `fst:changelog` `{ version, hash }` record.
public struct ChangelogSeenRecord: Codable, Sendable, Equatable {
    /// App version shown in the dismissed card's title.
    public let version: String
    /// Changelog content hash at dismissal.
    public let hash: String

    /// Create a record.
    ///
    /// - Parameters:
    ///   - version: App version at dismissal.
    ///   - hash: Changelog content hash at dismissal.
    public init(version: String, hash: String) {
        self.version = version
        self.hash = hash
    }
}

/// `UserDefaults`-backed "What's New" dismissal state, mirroring the web's
/// `localStorage['fst:changelog']` gate in `App.tsx`: the card shows when nothing valid is
/// stored or the stored hash differs from the current changelog hash.
public final class ChangelogSeenStore: @unchecked Sendable {
    /// Persisted key (JSON-encoded `ChangelogSeenRecord`).
    public static let storageKey = "fst.changelog.seen.v1"

    private let defaults: UserDefaults
    private let lock = NSLock()

    /// Create a store.
    ///
    /// - Parameter defaults: Backing store; `.standard` in the app, a suite in tests.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The last dismissal, or nil when absent, oversized or corrupt (the web treats a parse
    /// failure as "show again").
    ///
    /// - Returns: Validated record or nil.
    public func load() -> ChangelogSeenRecord? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = defaults.data(forKey: Self.storageKey), data.count <= 1024,
              let record = try? JSONDecoder().decode(ChangelogSeenRecord.self, from: data),
              !record.hash.isEmpty, record.hash.count <= 32, record.version.count <= 64
        else { return nil }
        return record
    }

    /// Whether the card should show for a changelog hash.
    ///
    /// - Parameter hash: Current changelog hash.
    /// - Returns: True when never dismissed or dismissed for different content.
    public func shouldShow(hash: String = Changelog.currentHash) -> Bool {
        load()?.hash != hash
    }

    /// Persist a dismissal.
    ///
    /// - Parameters:
    ///   - version: App version shown in the card.
    ///   - hash: Changelog hash that was shown.
    public func markSeen(version: String, hash: String = Changelog.currentHash) {
        let record = ChangelogSeenRecord(version: String(version.prefix(64)), hash: hash)
        guard let data = try? JSONEncoder().encode(record) else { return }
        lock.lock()
        defaults.set(data, forKey: Self.storageKey)
        lock.unlock()
    }

    /// Forget the dismissal so the card shows again on next launch.
    public func reset() {
        lock.lock()
        defaults.removeObject(forKey: Self.storageKey)
        lock.unlock()
    }
}
