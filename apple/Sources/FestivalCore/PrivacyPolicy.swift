import Foundation

// MARK: - Privacy policy

/// The privacy policy every client shows from Settings (issue #98).
///
/// This is the Swift copy of `contracts/privacy-policy.json`, the cross-platform source of
/// truth: every platform renders the same words. `PrivacyPolicyTests` decodes that JSON and
/// fails if this copy differs, so change the contract first, then regenerate this copy.
/// The text is compiled in (no network call), so it opens even when the service is down.
public struct PrivacyPolicy: Codable, Equatable, Sendable {
    /// Contract format version.
    public let schema: Int
    /// Modal title ("Privacy Policy").
    public let title: String
    /// Effective date as `yyyy-MM-dd`.
    public let effectiveDate: String
    /// Effective date as shown to people.
    public let effectiveDateText: String
    /// Sections in display order.
    public let sections: [Section]

    /// One titled section of the policy.
    public struct Section: Codable, Equatable, Sendable, Identifiable {
        /// Stable section ID (for example `information-collected`).
        public let id: String
        /// Title Case heading.
        public let title: String
        /// Paragraphs and bullet lists in display order.
        public let blocks: [Block]
    }

    /// One paragraph or bullet list.
    public enum Block: Codable, Equatable, Sendable {
        /// A plain paragraph.
        case paragraph(String)
        /// A bulleted list, one string per item.
        case bullets([String])

        private enum CodingKeys: String, CodingKey { case kind, text, items }

        /// Decode a `{"kind": "paragraph", "text": …}` or `{"kind": "bullets", "items": […]}` block.
        ///
        /// - Parameter decoder: The decoder to read from.
        /// - Throws: `DecodingError` for an unknown kind or a missing field.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(String.self, forKey: .kind)
            switch kind {
            case "paragraph": self = .paragraph(try container.decode(String.self, forKey: .text))
            case "bullets": self = .bullets(try container.decode([String].self, forKey: .items))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .kind, in: container, debugDescription: "Unknown block kind \(kind)"
                )
            }
        }

        /// Encode in the contract's shape.
        ///
        /// - Parameter encoder: The encoder to write to.
        /// - Throws: Any encoding error.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .paragraph(let text):
                try container.encode("paragraph", forKey: .kind)
                try container.encode(text, forKey: .text)
            case .bullets(let items):
                try container.encode("bullets", forKey: .kind)
                try container.encode(items, forKey: .items)
            }
        }
    }
}

// MARK: - Presentation

public extension PrivacyPolicy {
    /// Longest bullet prefix (before `": "`) that counts as a label, such as "Selected player".
    static let maxLeadLength = 32

    /// Styled text for one paragraph or bullet; the words are unchanged.
    ///
    /// A bullet that starts with a short label ("GitHub: …") gets that label, including the
    /// colon, in bold so the list scans like a definition list. Every `https://` address
    /// becomes a link the system browser opens; a trailing full stop stays outside the link.
    ///
    /// - Parameters:
    ///   - text: Contract text.
    ///   - boldLead: Whether to bold a short leading label (bullets only).
    /// - Returns: The attributed text.
    static func styledText(_ text: String, boldLead: Bool) -> AttributedString {
        var styled = AttributedString(text)
        if boldLead, let colon = text.range(of: ": "),
           text.distance(from: text.startIndex, to: colon.lowerBound) <= maxLeadLength,
           let range = styled.range(of: String(text[..<colon.upperBound]).trimmingCharacters(in: .whitespaces)) {
            styled[range].inlinePresentationIntent = .stronglyEmphasized
        }
        for link in links(in: text) {
            if let range = styled.range(of: link.absoluteString) {
                styled[range].link = link
            }
        }
        return styled
    }

    /// The `https://` addresses in a block of text, without trailing punctuation.
    ///
    /// - Parameter text: Contract text.
    /// - Returns: Each address, in order.
    static func links(in text: String) -> [URL] {
        text.split(whereSeparator: \.isWhitespace).compactMap { word in
            guard word.hasPrefix("https://") else { return nil }
            let trimmed = word.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:)"))
            return URL(string: trimmed)
        }
    }
}

// MARK: - Current policy

public extension PrivacyPolicy {
    /// The policy in force, identical to `contracts/privacy-policy.json` (generated from it).
    static let current = PrivacyPolicy(
        schema: 1,
        title: "Privacy Policy",
        effectiveDate: "2026-10-03",
        effectiveDateText: "Effective October 3, 2026",
        sections: [
            Section(id: "overview", title: "Overview", blocks: [
                .paragraph("Festival Score Tracker is an independent, fan-made app for browsing Fortnite Festival songs, leaderboards and player statistics. It is not affiliated with, endorsed by or sponsored by Epic Games."),
                .paragraph("This policy explains what information the Festival Score Tracker website, its iPhone, iPad, Mac, Android and Windows apps, and the Festival Score Tracker service at festivalscoretracker.com handle, why, and the choices you have."),
            ]),
            Section(id: "information-collected", title: "Information We Collect", blocks: [
                .paragraph("There is no account. You never sign in, and we never ask for your name, email address, phone number, contacts, location or Epic Games login."),
                .bullets([
                    "Selected player: when you choose a player, the public Epic account ID and display name of that player are saved on your device so the app can show their scores. Requests for that player's data include the account ID.",
                    "Player search: the names you type into player search are sent to our service to find matching public players.",
                    "Settings: your preferences, such as visible instruments, sorting, filters and which guides you have seen, are stored only on your device or in your browser.",
                    "Technical data: like any internet service, our servers and our network provider receive your IP address and standard request details, such as the time, the address requested and the app version, whenever the app loads data.",
                    "Feedback you choose to send: if you use Report an Issue or Request a Feature, we receive what you type, any images or videos you attach, the app version, and your operating system version and device model.",
                ]),
                .paragraph("The app contains no advertising, analytics or tracking code. We do not build profiles about you or track you across other companies' apps and websites."),
            ]),
            Section(id: "how-used", title: "How We Use Information", blocks: [
                .bullets([
                    "To show the songs, leaderboards, rankings and statistics you ask for, and to keep the selected player's public score history up to date.",
                    "To keep the service reliable and secure, for example by limiting abusive traffic and diagnosing errors.",
                    "To file, read and respond to feedback you send.",
                ]),
                .paragraph("We do not sell your information or share it for advertising."),
            ]),
            Section(id: "public-game-data", title: "Public Game Data", blocks: [
                .paragraph("The scores, rankings, Epic account IDs and display names shown in the app are public Fortnite Festival leaderboard data that our service collects from Epic Games' services. Players appear under their public Epic display name. To ask us to remove or hide your leaderboard information from Festival Score Tracker, contact us as described below."),
            ]),
            Section(id: "third-parties", title: "Third Parties", blocks: [
                .bullets([
                    "Epic Games: the source of the song, shop and leaderboard data. Album artwork loads directly from Epic Games' content servers, which receive your IP address with each image request. Item Shop links open fortnite.com, which follows Epic Games' own privacy policy.",
                    "Cloudflare: our network provider, which carries and protects traffic to festivalscoretracker.com.",
                    "GitHub: feedback you send is filed as a public issue on GitHub, together with its attachments. Do not include personal information you do not want to be public.",
                    "Apple, Google and Microsoft: your app store and operating system may collect information when you download, update or use the app, under their own privacy policies.",
                ]),
            ]),
            Section(id: "retention", title: "Data Retention", blocks: [
                .bullets([
                    "Information on your device stays until you remove it: deselect the player, use Reset Settings, clear the website's data or uninstall the app.",
                    "Server request logs are kept only as long as needed to run, secure and troubleshoot the service, and are then deleted.",
                    "Feedback status is held in memory for about an hour. The GitHub issue it creates stays public until it is removed; you can ask us to remove it.",
                    "Public leaderboard data is kept to provide score history and rankings.",
                ]),
            ]),
            Section(id: "your-rights", title: "Your Choices and Rights", blocks: [
                .paragraph("You can use the app without selecting a player, and you can deselect the player or reset your settings at any time."),
                .paragraph("Depending on where you live, for example under the GDPR in the European Union and United Kingdom or the CCPA in California, you may have the right to access, correct or delete personal information about you, or to object to its use. Because there are no accounts, include your Epic display name or account ID so we can find the information. We respond within the time the law requires and never treat you differently for making a request."),
            ]),
            Section(id: "children", title: "Children", blocks: [
                .paragraph("Festival Score Tracker does not knowingly collect personal information from children under 13, or the minimum age in your country. If you believe a child has sent us personal information, contact us and we will delete it."),
            ]),
            Section(id: "security", title: "Security", blocks: [
                .paragraph("All app traffic to our service is encrypted with HTTPS, and we limit what we collect in the first place. No method of transmission or storage is completely secure, but we work to protect the information we hold."),
            ]),
            Section(id: "changes", title: "Changes to This Policy", blocks: [
                .paragraph("If this policy changes, we will update the effective date above and describe significant changes in the app's What's New."),
            ]),
            Section(id: "contact", title: "Contact Us", blocks: [
                .paragraph("For questions or privacy requests, use Report an Issue in Settings or open an issue at https://github.com/SFenton/FestivalNativeApps/issues. Issues are public, so say only that you have a privacy request and we will arrange a private way to continue."),
            ]),
        ]
    )
}
