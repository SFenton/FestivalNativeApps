import XCTest

/// The journeys' shared harness logic, checked without launching the app: how a timed-out
/// audit is split into smaller ones, and which elements count as Quick Links rows (#686).
final class UITestHarnessTests: XCTestCase {
    // MARK: - Audit passes

    /// A set of named types splits into one audit per type, in XCTest's order, covering
    /// exactly the original set.
    func testAuditPassesSplitNamedTypesOnePerType() {
        let types: XCUIAccessibilityAuditType = [.contrast, .dynamicType, .textClipped, .hitRegion, .sufficientElementDescription]
        let passes = SongsUITestSupport.auditPasses(types)
        XCTAssertEqual(
            passes.map(\.rawValue),
            [.contrast, .hitRegion, .sufficientElementDescription, .dynamicType, .textClipped]
                .map { (type: XCUIAccessibilityAuditType) in type.rawValue }
        )
        let union = passes.reduce(into: XCUIAccessibilityAuditType()) { $0.formUnion($1) }
        XCTAssertEqual(union, types)
    }

    /// `.all` keeps its spare bits, so it stays one audit rather than losing any type.
    func testAuditPassesKeepAllWhole() {
        XCTAssertEqual(SongsUITestSupport.auditPasses(.all).map(\.rawValue), [XCUIAccessibilityAuditType.all.rawValue])
    }

    /// A single type is one audit of that type.
    func testAuditPassesKeepASingleType() {
        XCTAssertEqual(
            SongsUITestSupport.auditPasses(.contrast).map(\.rawValue), [XCUIAccessibilityAuditType.contrast.rawValue]
        )
    }

    /// Every type XCTest names on iOS is known, so none is dropped by a split.
    func testEveryNamedAuditTypeIsKnown() {
        let named: [XCUIAccessibilityAuditType] = [
            .contrast, .elementDetection, .hitRegion, .sufficientElementDescription,
            .dynamicType, .textClipped, .trait,
        ]
        for type in named {
            XCTAssertEqual(SongsUITestSupport.auditPasses(type).map(\.rawValue), [type.rawValue], "\(type.rawValue)")
        }
    }

    /// The audit retry treats only XCTest's two deadline errors as timeouts.
    func testOnlyDeadlineErrorsAreAuditTimeouts() {
        XCTAssertTrue(SongsUITestSupport.isAuditTimeout(NSError(domain: "com.apple.xcode.xctest.accessibilityAudit", code: -56)))
        XCTAssertTrue(SongsUITestSupport.isAuditTimeout(NSError(domain: "com.apple.dt.XCTest.XCTFuture", code: 1000)))
        XCTAssertFalse(SongsUITestSupport.isAuditTimeout(NSError(domain: "com.apple.xcode.xctest.accessibilityAudit", code: -1)))
        XCTAssertFalse(SongsUITestSupport.isAuditTimeout(NSError(domain: NSCocoaErrorDomain, code: -56)))
    }

    // MARK: - Quick Links rows

    /// A row is a button with a Quick Links identifier, or an unidentified button that reads a
    /// known section's title (iOS 27 menus, R6); nothing else matches.
    func testQuickLinkRowMatchesIdentifierOrSpokenTitle() {
        let labels: Set<String> = ["Accessibility", "Item Shop"]
        func isRow(_ type: XCUIElement.ElementType, _ id: String, _ label: String) -> Bool {
            FestivalApp.isQuickLinkRow(elementType: type, identifier: id, label: label, labels: labels)
        }
        XCTAssertTrue(isRow(.button, "fst.quick-links.item.accessibility", "Accessibility"))
        XCTAssertTrue(isRow(.button, "fst.quick-links.item.version", "Festival Score Tracker Version"))
        XCTAssertTrue(isRow(.button, "", "Item Shop"))
        XCTAssertFalse(isRow(.button, "", "Licenses"), "an unidentified button with an unknown title")
        XCTAssertFalse(isRow(.button, "fst.settings.item-shop", "Item Shop"), "another identified button")
        XCTAssertFalse(isRow(.staticText, "fst.quick-links.item.accessibility", "Accessibility"), "not a button")
        XCTAssertFalse(isRow(.staticText, "", "Accessibility"), "a heading reading a section's title")
    }
}
