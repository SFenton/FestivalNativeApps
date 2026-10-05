import XCTest

/// Narrow, documented waivers for the iPad accessibility audit journeys
/// (`.agents/testing/apple/accessibility.md`, "iPad audit waivers").
///
/// An issue is waived only when **every** condition of one entry matches: the audit
/// type, the element (identifier, or a system element type we do not own), a phrase of
/// the audit's own reason and, for contrast false positives, a rendered measurement of
/// the element in the same run (``IPadAuditRenderedContrast``) at or above the WCAG
/// threshold. No audit type is ignored wholesale; a waived issue is still written to the
/// run's JSON with its waiver id.
enum IPadAuditWaivers {
    // MARK: - Model

    /// What the audit reported, reduced to the fields a waiver may match.
    struct Issue {
        let auditType: XCUIAccessibilityAuditType
        let summary: String
        let identifier: String
        let label: String
        let elementType: XCUIElement.ElementType?
        let rendered: IPadAuditRenderedContrast.Measurement?
        /// Growth and read-back evidence (Dynamic Type heuristics only).
        var text: IPadAuditTextEvidence.Evidence?
        /// Page-level evidence (issues without an element only).
        var page: IPadAuditPageEvidence.Evidence?
        /// ``containerIdentifiers`` whose frame contains the element's centre.
        var containers: Set<String> = []

        /// True when the audit named no element at all.
        var isUnattributed: Bool { identifier.isEmpty && label.isEmpty && elementType == nil }
    }

    /// Why an issue is accepted.
    enum Kind: String {
        /// The auditor's verdict disagrees with a measurement from the same run.
        case falsePositive
        /// A system control the app does not draw or style.
        case systemControl
    }

    /// One waiver.
    struct Waiver {
        /// Stable id, listed in the docs' waiver table.
        let id: String
        let kind: Kind
        let auditType: XCUIAccessibilityAuditType
        /// A phrase that must appear in the audit's compact description.
        let reason: String
        /// Exact element identifiers this applies to (empty: match by ``elementTypes``).
        var identifiers: Set<String> = []
        /// Identifier prefixes (a family of rows such as `fst.songs.row.`).
        var identifierPrefixes: [String] = []
        /// System element types this applies to (system controls only).
        var elementTypes: Set<XCUIElement.ElementType> = []
        /// The element must lie inside this app element (a system decoration on it), or
        /// ``keyboardContainer`` for the system keyboard.
        var containedIn: String?
        /// Exact system labels this applies to (system controls only).
        var labels: Set<String> = []
        /// Minimum rendered contrast in this run (contrast false positives).
        var minimumRendered: Double?
        /// Minimum glyph pixels, so an empty crop never passes.
        var minimumGlyphPixels = 40
        /// Evidence summary (also in the docs table).
        let evidence: String
        /// Proved per issue instead of per element: any element whose own measurement in
        /// this run passes (``minimumRendered``, ``minimumGrowth``, ``requiresWholeText``),
        /// except the ``excludedTypes``. Only allowed with a measured condition.
        var anyMeasuredElement = false
        /// Element types a per-issue proof never covers (system fields: their own entries).
        var excludedTypes: Set<XCUIElement.ElementType> = []
        /// Minimum AX5 ÷ default height of the same element.
        var minimumGrowth: Double?
        /// Applies only to issues without an element, proved by page-level evidence
        /// (``minimumPageFloor``, ``requiresSheetTextInTree``).
        var unattributedOnly = false
        /// Every static text in the audited region measures at least this ratio.
        var minimumPageFloor: Double?
        /// The page is a sheet and every recognized line inside it names an element.
        var requiresSheetTextInTree = false
        /// Every visible static text on the page is ≥ 1.35× taller at AX5.
        var requiresPageGrowth = false
        /// Every static text on screen at AX5 is read back whole.
        var requiresPageWhole = false
        /// The whole label must be read back at AX5, the size the audit's claim is about
        /// ("may be clipped at larger Dynamic Type sizes"). At the default size a long
        /// title may still end in a marquee that scrolls (or, with Reduce Motion, in an
        /// ellipsis whose full text the row's detail shows: HIG Typography "unless people
        /// can open a separate view for the rest"); that is recorded, not waived here.
        var requiresWholeText = false

        /// True when the issue matches every condition.
        func matches(_ issue: Issue) -> Bool {
            guard issue.auditType == auditType, issue.summary.localizedCaseInsensitiveContains(reason) else {
                return false
            }
            if unattributedOnly {
                guard issue.isUnattributed, let page = issue.page else { return false }
                if let minimumPageFloor {
                    guard page.textsMeasured > 0, page.textsUnmeasured == 0, let floor = page.contrastFloor,
                          floor >= minimumPageFloor else { return false }
                }
                if requiresSheetTextInTree {
                    guard page.isSheet, page.linesRecognized > 0, page.textOutsideTree.isEmpty else { return false }
                }
                if requiresPageGrowth {
                    guard page.growthChecked > 0, page.notGrowing.isEmpty else { return false }
                }
                if requiresPageWhole {
                    guard page.wholeChecked > 0, page.notWhole.isEmpty else { return false }
                }
                return minimumPageFloor != nil || requiresSheetTextInTree || requiresPageGrowth || requiresPageWhole
            }
            let byIdentifier = identifiers.contains(issue.identifier)
                || (!issue.identifier.isEmpty && identifierPrefixes.contains { issue.identifier.hasPrefix($0) })
            let byType = issue.elementType.map { elementTypes.contains($0) } ?? false
            let measured = minimumRendered != nil || minimumGrowth != nil || requiresWholeText
            let byProof = anyMeasuredElement && measured
                && !(issue.elementType.map { excludedTypes.contains($0) } ?? false)
            guard byIdentifier || byType || byProof else { return false }
            if let containedIn {
                guard issue.containers.contains(containedIn) else { return false }
            }
            if !labels.isEmpty {
                guard labels.contains(issue.label) else { return false }
            }
            if let minimumRendered {
                guard let rendered = issue.rendered, rendered.ratio >= minimumRendered,
                      rendered.glyphPixels >= minimumGlyphPixels else { return false }
            }
            if let minimumGrowth {
                guard let growth = issue.text?.growth, growth >= minimumGrowth else { return false }
            }
            if requiresWholeText {
                guard issue.text?.wholeAtLargest == true else { return false }
            }
            return true
        }
    }

    // MARK: - Table

    /// App elements whose frames are checked as ``Waiver/containedIn`` scopes.
    static let containerIdentifiers = ["fst.shell.notifications"]

    /// The ``Waiver/containedIn`` scope for the system keyboard (`app.keyboards`).
    static let keyboardContainer = "system-keyboard"

    /// System fields: their placeholders and clear buttons are drawn by UIKit.
    static let systemFields: Set<XCUIElement.ElementType> = [.searchField, .textField, .secureTextField]

    /// Every waiver. Keep in sync with the docs table.
    static let all: [Waiver] = [
        // (b) Contrast over translucent material, glass and artwork: the audit samples the
        // material's backdrop, not the composited pixels. Proved per issue from this run's
        // own capture (WCAG 4.5:1 for all text sizes, never the 3:1 large-text allowance).
        // Reduce Transparency removes nearly all of these (accessibility.md).
        Waiver(
            id: "contrast-rendered", kind: .falsePositive, auditType: .contrast,
            reason: "Contrast", minimumRendered: 4.5,
            evidence: "Rendered ≥ 4.5:1 in the run's own capture (measured 5–19.5:1 across modes)",
            anyMeasuredElement: true, excludedTypes: systemFields
        ),
        // (b) "User will not be able to change the font size": the same element in an AX5
        // launch is ≥ 1.35× taller.
        Waiver(
            id: "dynamic-type-grows", kind: .falsePositive, auditType: .dynamicType,
            reason: "partially unsupported",
            evidence: "Same element in an AX5 launch is ≥ 1.35× taller",
            anyMeasuredElement: true, excludedTypes: systemFields, minimumGrowth: 1.35
        ),
        // (b) "may be clipped at larger Dynamic Type sizes": the app's accessibility-size
        // layouts (wrapping marquees, stacked rows) keep the whole label visible at AX5,
        // read back from the AX5 capture.
        Waiver(
            id: "text-clipped-whole", kind: .falsePositive, auditType: .textClipped,
            reason: "Text clipped",
            evidence: "Whole label read back from the AX5 capture; ≥ 1.35× growth",
            anyMeasuredElement: true, excludedTypes: systemFields, minimumGrowth: 1.35,
            requiresWholeText: true
        ),
        // (b) Contrast verdicts without an element ("Contrast failed for
        // SwiftUI.AccessibilityNode"): every static text in the page's capture measures
        // ≥ 4.5:1, so none of the nodes the audit could mean fails.
        Waiver(
            id: "unattributed-contrast-page-floor", kind: .falsePositive, auditType: .contrast,
            reason: "Contrast",
            evidence: "No element; every static text on the page renders ≥ 4.5:1 in the run's capture",
            unattributedOnly: true, minimumPageFloor: 4.5
        ),
        // (b) "partially unsupported" without an element: every static text on screen is
        // ≥ 1.35× taller in an AX5 launch of the same page.
        Waiver(
            id: "unattributed-dynamic-type-page-growth", kind: .falsePositive, auditType: .dynamicType,
            reason: "partially unsupported",
            evidence: "No element; every visible static text on the page is ≥ 1.35× taller at AX5",
            unattributedOnly: true, requiresPageGrowth: true
        ),
        // (b) "Text clipped" without an element: every static text on screen at AX5 is read
        // back whole from the capture.
        Waiver(
            id: "unattributed-text-clipped-page-whole", kind: .falsePositive, auditType: .textClipped,
            reason: "Text clipped",
            evidence: "No element; every static text on screen at AX5 is read back whole",
            unattributedOnly: true, requiresPageWhole: true
        ),
        // (c) "Potentially inaccessible text" without an element over a sheet: every line
        // of text recognized inside the sheet names an element; the remaining text is the
        // page behind the sheet, visible through the dimming and (correctly) outside the
        // tree while the system sheet is modal.
        Waiver(
            id: "unattributed-text-behind-sheet", kind: .systemControl, auditType: .elementDetection,
            reason: "Potentially inaccessible text",
            evidence: "No element; all recognized text inside the sheet is in the tree (the rest is behind the modal sheet)",
            unattributedOnly: true, requiresSheetTextInTree: true
        ),
        // (c) The system search field (`.searchable`, UISearchBarTextField): UIKit draws
        // its placeholder in `placeholderText`, which the audit reads as nearly passing;
        // HIG Search fields asks for the system field (the iPhone journeys accept the same
        // issue, #92). Measured 5.6:1 glyph core for "Filter Songs" on iPadOS 26.5.
        Waiver(
            id: "system-search-placeholder-contrast", kind: .systemControl, auditType: .contrast,
            reason: "Contrast", elementTypes: [.searchField],
            evidence: "System search field placeholder (UIKit placeholderText)"
        ),
        // (c) The unread count on the bell is the iOS 26 system toolbar-item badge
        // (`.badge` on a toolbar button: white digits on the system red capsule, about
        // 4:1 by the system colours, drawn by UIKit). It is hidden from VoiceOver; the
        // bell's label says "N unread".
        Waiver(
            id: "system-toolbar-badge", kind: .systemControl, auditType: .contrast,
            reason: "Contrast", elementTypes: [.staticText], containedIn: "fst.shell.notifications",
            evidence: "System toolbar-item badge on the Notifications bell (UIKit)"
        ),
        // (c) The search field's own clear button (UIKit, 20.5 pt): the field itself is
        // the 44 pt target, and Clear is also reachable by selecting and deleting.
        Waiver(
            id: "system-search-clear-button", kind: .systemControl, auditType: .hitRegion,
            reason: "Hit area", elementTypes: [.button], labels: ["Clear text"],
            evidence: "UISearchBar clear button (system label Clear text)"
        ),
        // (c) Predictive-text candidates on the system keyboard (unlabelled cells while the
        // candidate bar is empty), present because the compact Search page focuses its field.
        Waiver(
            id: "system-keyboard-candidates", kind: .systemControl, auditType: .sufficientElementDescription,
            reason: "no description", elementTypes: [.other], containedIn: keyboardContainer,
            evidence: "Inside the system keyboard's frame (QuickType candidate bar)"
        ),
        // (c) A search field's placeholder is one line by construction (UIKit truncates it);
        // the typed query scrolls within the field.
        Waiver(
            id: "system-search-placeholder-clipped", kind: .systemControl, auditType: .textClipped,
            reason: "Text clipped", elementTypes: [.searchField],
            evidence: "System search field placeholder is single-line (UIKit)"
        ),
    ]

    /// The first waiver accepting `issue`, if any.
    ///
    /// - Parameters:
    ///   - issue: The reported issue.
    ///   - page: Audited page name (for future page-scoped entries).
    ///   - mode: Audit mode raw value.
    /// - Returns: The matching waiver.
    static func match(_ issue: Issue, page: String, mode: String) -> Waiver? {
        all.first { $0.matches(issue) }
    }
}
