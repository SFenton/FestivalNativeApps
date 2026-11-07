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

    // MARK: - Snapshot waits

    /// The element wait finds an identifier anywhere in a snapshot, the root included, and
    /// nothing else (#690).
    @MainActor
    func testSnapshotContainsMatchesAnyNodeByIdentifier() {
        let tree = FakeSnapshot("app", [
            FakeSnapshot("fst.songs.list", [FakeSnapshot("fst.songs.row.fixture-pulse")]),
            FakeSnapshot(""),
        ])
        XCTAssertTrue(FestivalApp.contains("app", in: tree))
        XCTAssertTrue(FestivalApp.contains("fst.songs.list", in: tree))
        XCTAssertTrue(FestivalApp.contains("fst.songs.row.fixture-pulse", in: tree))
        XCTAssertFalse(FestivalApp.contains("fst.song-detail.intensity", in: tree))
        XCTAssertFalse(FestivalApp.contains("fst.songs", in: tree), "a prefix is not a match")
    }

    /// The node lookup returns the first depth-first match, so a row read from a snapshot
    /// is the same row a live `firstMatch` would find (#693).
    @MainActor
    func testSnapshotNodeReturnsTheFirstDepthFirstMatch() {
        let first = FakeSnapshot("fst.history.row.0")
        let later = FakeSnapshot("fst.history.row.0")
        let tree = FakeSnapshot("app", [
            FakeSnapshot("fst.history.list", [FakeSnapshot("fst.history.header"), first]),
            later,
        ])
        XCTAssertTrue(FestivalApp.node("fst.history.row.0", in: tree) === first)
        XCTAssertTrue(FestivalApp.node("app", in: tree) === tree)
        XCTAssertNil(FestivalApp.node("fst.history.row", in: tree), "a prefix is not a match")
        XCTAssertNil(FestivalApp.node("fst.history.row.1", in: tree))
    }

    // MARK: - Switch taps

    /// The bare-track point sits `switchBareTrackInset` in from the end the thumb has left,
    /// on the inner switch when there is one, else on a track ending at the row's trailing
    /// edge; live and snapshot switch taps share it (#659, #694).
    func testBareTrackPointAvoidsTheThumb() {
        let row = CGRect(x: 24, y: 324, width: 358, height: 52)
        let inner = CGRect(x: 301, y: 336, width: 63, height: 28)
        func point(_ inner: CGRect?, on: Bool, in row: CGRect = row) -> [CGFloat] {
            let point = SongsUITestSupport.bareTrackPoint(row: row, inner: inner, isOn: on)
            return [point.x, point.y].map { ($0 * 100).rounded() / 100 }
        }
        XCTAssertEqual(point(inner, on: true), [313, 350])
        XCTAssertEqual(point(inner, on: false), [352, 350])
        XCTAssertEqual(point(nil, on: true), [331, 350])
        XCTAssertEqual(point(nil, on: false), [370, 350])
        XCTAssertEqual(point(row, on: false), [370, 350], "a switch reporting itself as its inner switch uses the row")
        XCTAssertEqual(point(nil, on: true, in: CGRect(x: 0, y: 0, width: 63, height: 28)), [31.5, 14],
                       "never left of a narrow switch's middle")
    }
}

/// A hand-built accessibility snapshot node: only its identifier and children matter.
private final class FakeSnapshot: NSObject, XCUIElementSnapshot {
    let identifier: String
    let children: [any XCUIElementSnapshot]
    let frame: CGRect = .zero
    let value: Any? = nil
    let title = ""
    let label = ""
    let elementType: XCUIElement.ElementType = .other
    let isEnabled = true
    let horizontalSizeClass: XCUIElement.SizeClass = .unspecified
    let verticalSizeClass: XCUIElement.SizeClass = .unspecified
    let placeholderValue: String? = nil
    let isSelected = false
    let hasFocus = false
    var dictionaryRepresentation: [XCUIElement.AttributeName: Any] { [:] }

    init(_ identifier: String, _ children: [FakeSnapshot] = []) {
        self.identifier = identifier
        self.children = children
    }
}
