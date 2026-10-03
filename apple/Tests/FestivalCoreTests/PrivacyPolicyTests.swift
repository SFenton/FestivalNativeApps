import Foundation
import Testing
@testable import FestivalCore

// MARK: - Privacy policy

@Suite("Privacy policy")
struct PrivacyPolicyTests {
    /// The cross-platform contract every client renders verbatim.
    private func contractPolicy() throws -> PrivacyPolicy {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("contracts/privacy-policy.json"))
        return try JSONDecoder().decode(PrivacyPolicy.self, from: data)
    }

    @Test("Swift copy is identical to contracts/privacy-policy.json")
    func matchesContract() throws {
        let contract = try contractPolicy()
        #expect(PrivacyPolicy.current.schema == contract.schema)
        #expect(PrivacyPolicy.current.title == contract.title)
        #expect(PrivacyPolicy.current.effectiveDate == contract.effectiveDate)
        #expect(PrivacyPolicy.current.sections.map(\.id) == contract.sections.map(\.id))
        for (mine, theirs) in zip(PrivacyPolicy.current.sections, contract.sections) {
            #expect(mine == theirs, "section \(theirs.id) differs from the contract")
        }
        #expect(PrivacyPolicy.current == contract)
    }

    @Test("Industry-standard sections are present")
    func requiredSections() {
        let ids = PrivacyPolicy.current.sections.map(\.id)
        for required in ["information-collected", "how-used", "third-parties", "retention", "your-rights", "contact"] {
            #expect(ids.contains(required), "missing \(required)")
        }
        #expect(ids.last == "contact")
        #expect(Set(ids).count == ids.count)
    }

    @Test("Effective date is a real date that matches its display text")
    func effectiveDate() throws {
        let policy = PrivacyPolicy.current
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd"
        let date = try #require(parser.date(from: policy.effectiveDate))
        parser.dateFormat = "MMMM d, yyyy"
        #expect(policy.effectiveDateText == "Effective \(parser.string(from: date))")
    }

    @Test("Every section has a title and non-empty blocks")
    func blocksAreWellFormed() {
        let policy = PrivacyPolicy.current
        #expect(!policy.title.isEmpty)
        for section in policy.sections {
            #expect(!section.title.isEmpty)
            #expect(!section.blocks.isEmpty, "section \(section.id) is empty")
            for block in section.blocks {
                switch block {
                case .paragraph(let text):
                    #expect(!text.trimmingCharacters(in: .whitespaces).isEmpty)
                case .bullets(let items):
                    #expect(!items.isEmpty)
                    #expect(items.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                }
            }
        }
    }

    @Test("Contact section links to the public GitHub issues page")
    func contactLink() throws {
        let contact = try #require(PrivacyPolicy.current.sections.last)
        let links = contact.blocks.flatMap { block -> [URL] in
            if case .paragraph(let text) = block { return PrivacyPolicy.links(in: text) }
            return []
        }
        #expect(links == [URL(string: "https://github.com/SFenton/FestivalNativeApps/issues")!])
    }

    @Test("Blocks round-trip in the contract's shape; unknown kinds fail")
    func blockCoding() throws {
        let json = #"[{"kind":"paragraph","text":"A"},{"kind":"bullets","items":["B","C"]}]"#
        let blocks = try JSONDecoder().decode([PrivacyPolicy.Block].self, from: Data(json.utf8))
        #expect(blocks == [.paragraph("A"), .bullets(["B", "C"])])
        let again = try JSONDecoder().decode(
            [PrivacyPolicy.Block].self, from: JSONEncoder().encode(blocks)
        )
        #expect(again == blocks)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([PrivacyPolicy.Block].self, from: Data(#"[{"kind":"table"}]"#.utf8))
        }
    }

    @Test("Styled text keeps the words, bolds a short bullet label and links addresses")
    func styledText() throws {
        let bullet = PrivacyPolicy.styledText("GitHub: feedback is public.", boldLead: true)
        #expect(String(bullet.characters) == "GitHub: feedback is public.")
        let lead = try #require(bullet.runs.first)
        #expect(lead.inlinePresentationIntent == .stronglyEmphasized)
        #expect(String(bullet[lead.range].characters) == "GitHub:")

        let long = "Information on your device stays until you remove it: deselect the player."
        #expect(PrivacyPolicy.styledText(long, boldLead: true).runs.allSatisfy { $0.inlinePresentationIntent == nil })
        #expect(PrivacyPolicy.styledText("GitHub: x", boldLead: false).runs.allSatisfy { $0.inlinePresentationIntent == nil })

        let text = "Open https://example.com/issues. Thanks"
        let linked = PrivacyPolicy.styledText(text, boldLead: false)
        #expect(String(linked.characters) == text)
        let linkRun = try #require(linked.runs.first { $0.link != nil })
        #expect(String(linked[linkRun.range].characters) == "https://example.com/issues")
        #expect(PrivacyPolicy.links(in: "no links here") == [])
    }
}
