import UIKit
import XCTest

// MARK: - Split band and Close on device

/// Device checks for the on-demand split's band and its trailing pane's Close (#344,
/// backfilled by #480; split-panes R1–R2), shared by the iPad bundle's
/// `IPadShellAccessibilityTests` and the iPhone bundle's
/// `DuoSplitBandAccessibilityJourneyTests` so iPad and iPhone Duo prove the same rules.
///
/// - The band gives VoiceOver nothing: no splitter, and the band node (XCUITest lists
///   SwiftUI views hidden with `accessibilityHidden`) is an unlabelled plain view.
/// - Close keeps a 44 × 44 pt hit region (HIG Buttons: "the hit region is at least 44x44
///   pt"; `.agents/testing/strategy.md`): XCUITest reports a system bar button's glass
///   (36 pt on iPadOS 26.5), not UIKit's hit region, so each tap lands off-centre inside a
///   44 pt square and must close the pane, as `NavButtonHitRegionJourneyTests` proves for
///   the shell's bar buttons. When the bar overflows, the system More button gets the same
///   taps and its menu must offer a named Close that closes the pane.
enum SplitBandUITestSupport {
    /// The band between the panes (`OnDemandSplitLayout`'s `SplitDivider`).
    static let bandID = "fst.split.divider"
    /// The trailing pane's container.
    static let paneID = "fst.split.trailing"
    /// The trailing pane's Close.
    static let closeID = "fst.split.close"

    /// Offsets from a button's centre, all inside a 44 × 44 pt square
    /// (`NavButtonHitRegionJourneyTests.nearMisses`).
    static let nearMisses: [CGVector] = [
        CGVector(dx: -20, dy: 0), CGVector(dx: 20, dy: 0),
        CGVector(dx: 0, dy: -20), CGVector(dx: 0, dy: 20),
        CGVector(dx: -15, dy: -15), CGVector(dx: 15, dy: 15),
    ]

    /// Labels of the system bar's overflow button.
    static let overflowLabels = ["More", "Show More"]

    /// Tap a list row again to reopen its item beside the list, as `assertCloseHitRegion`'s
    /// `reopen` does between near-miss taps.
    ///
    /// - Parameters:
    ///   - app: The app, with the split closed.
    ///   - rowID: The row's identifier.
    /// - Returns: Whether the trailing pane opened and settled.
    @MainActor
    static func reopen(_ app: XCUIApplication, row rowID: String,
                       file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let row = app.buttons.matching(identifier: rowID).firstMatch
        guard row.waitForExistence(timeout: FestivalApp.budget(5)) else {
            XCTFail("reopen: no row \(rowID) after Close", file: file, line: line)
            return false
        }
        // The list widens back to full width after Close; wait until the row settles.
        let deadline = Date.now.addingTimeInterval(FestivalApp.budget(5))
        while !row.isHittable, Date.now < deadline { Thread.sleep(forTimeInterval: 0.3) }
        guard row.isHittable else {
            XCTFail("reopen: row \(rowID) \(row.frame) is not hittable after Close", file: file, line: line)
            return false
        }
        row.tap()
        guard waitForPane(app, open: true), trailingPane(app) != nil else {
            XCTFail("reopen: row \(rowID) did not reopen its item", file: file, line: line)
            return false
        }
        return true
    }

    /// The first element with an identifier, of any type.
    @MainActor
    static func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// The trailing pane's frame, or nil while the split is closed.
    @MainActor
    static func trailingPane(_ app: XCUIApplication) -> CGRect? {
        let pane = element(app, paneID)
        return pane.exists ? pane.frame : nil
    }

    /// Wait until the trailing pane is open (and stops sliding in) or closed.
    ///
    /// - Parameters:
    ///   - app: The app.
    ///   - open: Whether to wait for the pane to be open.
    ///   - timeout: Budget on a physical Mac (``FestivalApp/budget(_:inVirtualMachine:)``).
    /// - Returns: Whether the pane reached that state.
    @MainActor
    @discardableResult
    static func waitForPane(_ app: XCUIApplication, open: Bool, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date.now.addingTimeInterval(FestivalApp.budget(timeout))
        var last: CGRect?
        repeat {
            let frame = trailingPane(app)
            if open, let frame, let last, abs(frame.minX - last.minX) < 0.5 { return true }
            if !open, frame == nil { return true }
            last = frame
            Thread.sleep(forTimeInterval: 0.3)
        } while Date.now < deadline
        return open ? last != nil : trailingPane(app) == nil
    }

    /// The band gives VoiceOver nothing to announce: no splitter anywhere, and the band,
    /// if XCUITest lists it, is an unlabelled plain node.
    ///
    /// - Parameters:
    ///   - nodes: One snapshot's nodes, depth first.
    ///   - context: Failure message prefix.
    @MainActor
    static func assertBandIsSilent(
        _ nodes: [XCUIElementSnapshot], _ context: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let splitters = nodes.filter { $0.elementType == .splitter || $0.elementType == .splitGroup }
        XCTAssertTrue(splitters.isEmpty, "\(context): no splitter for VoiceOver to announce: "
                      + "\(splitters.map(\.identifier))", file: file, line: line)
        for band in nodes where band.identifier == bandID {
            XCTAssertEqual(band.elementType, .other, "\(context): the band is a plain view", file: file, line: line)
            XCTAssertTrue(band.label.isEmpty && (band.value as? String ?? "").isEmpty,
                          "\(context): the band has nothing to read ('\(band.label)')", file: file, line: line)
        }
    }

    /// The overflow button of the trailing pane's bar, when Close is not in the bar.
    @MainActor
    static func overflowButton(_ app: XCUIApplication, pane: CGRect) -> XCUIElement? {
        let candidates = app.buttons.matching(NSPredicate(format: "label IN %@", overflowLabels))
        for index in 0..<candidates.count {
            let button = candidates.element(boundBy: index)
            if button.exists, button.isHittable, pane.contains(CGPoint(x: button.frame.midX, y: button.frame.midY)) {
                return button
            }
        }
        return nil
    }

    /// Close's (or, when the bar overflows, the More button's) 44 pt hit region and name,
    /// on an open split.
    ///
    /// In the bar, Close must be named "Close" and every near-miss tap must close the pane;
    /// `reopen` opens the same item again between taps. In the overflow menu, every
    /// near-miss tap on More must open a menu whose named Close item is at least 44 pt
    /// tall; the last one is chosen and must close the pane. Ends with the pane closed.
    ///
    /// - Parameters:
    ///   - app: The app, with the trailing pane open.
    ///   - context: Failure message prefix.
    ///   - reopen: Opens the same item again (``reopen(_:row:file:line:)``); returns whether
    ///     the pane opened, failing with its reason when not.
    /// - Returns: Whether Close was in the bar (false: it overflowed into More).
    @MainActor
    @discardableResult
    static func assertCloseHitRegion(
        _ app: XCUIApplication, _ context: String, reopen: () -> Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) -> Bool {
        guard let pane = trailingPane(app) else {
            XCTFail("\(context): no trailing pane to close", file: file, line: line)
            return false
        }
        let close = app.buttons.matching(identifier: closeID).firstMatch
        let origin = app.coordinate(withNormalizedOffset: .zero)
        if close.waitForExistence(timeout: FestivalApp.budget(3)), close.isHittable {
            XCTAssertEqual(close.label, "Close", "\(context): Close is named", file: file, line: line)
            XCTAssertTrue(pane.contains(CGPoint(x: close.frame.midX, y: close.frame.midY)),
                          "\(context): Close \(close.frame) is in the trailing pane \(pane)", file: file, line: line)
            for (index, offset) in nearMisses.enumerated() {
                let frame = close.frame
                origin.withOffset(CGVector(dx: frame.midX + offset.dx, dy: frame.midY + offset.dy)).tap()
                guard waitForPane(app, open: false, timeout: 5) else {
                    XCTFail("\(context): Close \(frame) ignored a tap at (\(Int(offset.dx)), \(Int(offset.dy))) pt "
                            + "from its centre: its hit region is under 44 × 44 pt", file: file, line: line)
                    return true
                }
                if index < nearMisses.count - 1 {
                    guard reopen() else { return true }
                    guard close.waitForExistence(timeout: FestivalApp.budget(5)) else {
                        XCTFail("\(context): the reopened pane has no Close", file: file, line: line)
                        return true
                    }
                    // A tap during the slide-in can land on the moving bar.
                    RunLoop.current.run(until: Date().addingTimeInterval(FestivalApp.budget(0.6)))
                    guard close.isHittable else {
                        XCTFail("\(context): the reopened pane's Close \(close.frame) is not hittable",
                                file: file, line: line)
                        return true
                    }
                }
            }
            return true
        }
        guard let more = overflowButton(app, pane: pane) else {
            XCTFail("\(context): the trailing pane's Close is neither in its bar nor in its More menu",
                    file: file, line: line)
            return false
        }
        let item = app.buttons.matching(NSPredicate(format: "label == 'Close'")).firstMatch
        for offset in nearMisses {
            let frame = more.frame
            origin.withOffset(CGVector(dx: frame.midX + offset.dx, dy: frame.midY + offset.dy)).tap()
            guard item.waitForExistence(timeout: FestivalApp.budget(3)) else {
                XCTFail("\(context): More \(frame) ignored a tap at (\(Int(offset.dx)), \(Int(offset.dy))) pt "
                        + "from its centre, or its menu has no Close", file: file, line: line)
                return false
            }
            XCTAssertGreaterThanOrEqual(item.frame.height, 44, "\(context): the Close menu item \(item.frame)",
                                        file: file, line: line)
            if offset != nearMisses.last {
                // Dismiss the menu without choosing (a tap on the dimmed leading pane).
                origin.withOffset(CGVector(dx: pane.minX / 2, dy: app.windows.firstMatch.frame.midY)).tap()
                let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: item)
                _ = XCTWaiter.wait(for: [gone], timeout: FestivalApp.budget(3))
                XCTAssertNotNil(trailingPane(app), "\(context): dismissing More kept the pane", file: file, line: line)
            }
        }
        item.tap()
        XCTAssertTrue(waitForPane(app, open: false), "\(context): More › Close closes the pane", file: file, line: line)
        return false
    }
}
