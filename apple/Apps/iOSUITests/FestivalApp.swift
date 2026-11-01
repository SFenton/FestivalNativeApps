import XCTest

/// Shared entry point for every `XCUIApplication` launch in this test target.
///
/// Every journey file used to construct `XCUIApplication()` directly and hand-roll
/// its own `launchEnvironment` dictionary. More than one forgot
/// `FST_DEBUG_STILL_BACKGROUND=1`: `SongsUITestSupport.fixtureApp()` (shared by
/// `SongsJourneyTests`/`SongDetailJourneyTests`/`ShopJourneyTests`) and
/// `FestivalMobileUITests.fixtureApp()` never set it at all. XCUITest waits for
/// the app to go idle before every synthetic action; the shared artwork
/// background carousel (and, since 2026-09-28, any overflowing `MarqueeText`
/// row) never idles without this flag, so a forgotten flag silently turns
/// every step of a journey into a multi-second-or-worse wait, and a long
/// enough journey exhausts the shared simulator's lock-hold budget entirely
/// (`.agents/workflow/simulator-driver.md`'s "Simulator queue stall").
///
/// Routing every launch through ``makeApp(_:)``/``launch(_:)`` makes that flag
/// structurally impossible to forget again: `tools/tests/test_launch_helper.py`
/// fails the build if any file under this directory other than this one
/// constructs `XCUIApplication()`.
enum FestivalApp {
    /// Launch environment every journey gets unless it explicitly overrides a key.
    ///
    /// - `FST_DEBUG_STILL_BACKGROUND`: freezes the shared artwork background and
    ///   any scrolling `MarqueeText` row so XCUITest's app-idle wait can settle.
    ///   `tools/ios_sim.py drive` sets this by default too (`--animate` opts out);
    ///   `DriverTests` reads it back out of its own passed-through environment
    ///   rather than through this helper, so that opt-out keeps working.
    private static let defaultEnvironment: [String: String] = [
        "FST_DEBUG_STILL_BACKGROUND": "1",
    ]

    /// Build a configured, not-yet-launched app.
    ///
    /// - Parameter env: Environment entries beyond the shared defaults; a key
    ///   repeated here overrides that default (e.g. to explicitly re-enable
    ///   animation for a test that needs it).
    /// - Returns: An `XCUIApplication` with `launchEnvironment` populated,
    ///   `launch()` not yet called.
    @MainActor
    static func makeApp(_ env: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        for (key, value) in defaultEnvironment {
            app.launchEnvironment[key] = value
        }
        for (key, value) in env {
            app.launchEnvironment[key] = value
        }
        return app
    }

    /// Build and immediately launch an app.
    ///
    /// - Parameter env: Environment entries beyond the shared defaults.
    /// - Returns: The launched `XCUIApplication`.
    @MainActor
    @discardableResult
    static func launch(_ env: [String: String] = [:]) -> XCUIApplication {
        let app = makeApp(env)
        app.launch()
        return app
    }

    // MARK: - Virtual machine budgets

    /// Whether the journeys run in a virtual machine (`kern.hv_vmm_present`), such as the
    /// `apple-ci` runner; read once per process. Simulator processes share the host's kernel.
    static let inVirtualMachine: Bool = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("kern.hv_vmm_present", &value, &size, nil, 0) == 0 && value == 1
    }()

    /// Factor applied to wait and settle budgets in a virtual machine, as the hosted tests'
    /// `nativeHostedVirtualMachineTimeoutScale`.
    static let virtualMachineTimeoutScale: TimeInterval = 4

    /// A wait or settle budget for this host.
    ///
    /// The `apple-ci` runner (~3 cores, paravirtual GPU) runs sheet and bar animations several
    /// times slower than a Mac: a Notifications sheet took over 5 s to leave the hierarchy
    /// there (#394). A budget is an upper bound, so scaling it costs nothing when the UI is
    /// ready; scale settle pauses too, since a tap during an animation can be ignored.
    ///
    /// - Parameters:
    ///   - seconds: The budget on a physical Mac.
    ///   - inVirtualMachine: Whether the run is in a VM.
    /// - Returns: `seconds`, scaled by ``virtualMachineTimeoutScale`` in a VM.
    static func budget(_ seconds: TimeInterval, inVirtualMachine: Bool = inVirtualMachine) -> TimeInterval {
        inVirtualMachine ? seconds * virtualMachineTimeoutScale : seconds
    }

    // MARK: - Accessibility snapshots

    /// The nodes of one accessibility snapshot of `root` that match, in depth-first order
    /// (the order an element query lists them).
    ///
    /// Walk a lazy list's elements with this, never with `query.allElementsBoundByIndex`:
    /// every bound element re-resolves the query when read, and a `List` that is still
    /// recycling cells (after a scroll, or after an audit cycles the text sizes) can shrink
    /// mid-walk, so reading the vanished last index fails the test outright ("No matches
    /// found for Element at index 51", #572). One snapshot reads every frame and label from
    /// the same instant. To act on a node, bind a new element to its identifier.
    ///
    /// - Parameters:
    ///   - root: The element to snapshot, usually the app.
    ///   - matches: Selects the wanted nodes.
    /// - Returns: Every matching node, `root` included when it matches.
    /// - Throws: A snapshot XCTest cannot take.
    @MainActor
    static func snapshotNodes(
        in root: XCUIElement, where matches: (XCUIElementSnapshot) -> Bool
    ) throws -> [XCUIElementSnapshot] {
        nodes(in: try root.snapshot(), where: matches)
    }

    /// The nodes of a snapshot already taken that match, in depth-first order.
    ///
    /// - Parameters:
    ///   - root: The snapshot to walk.
    ///   - matches: Selects the wanted nodes.
    /// - Returns: Every matching node, `root` included when it matches.
    @MainActor
    static func nodes(
        in root: XCUIElementSnapshot, where matches: (XCUIElementSnapshot) -> Bool
    ) -> [XCUIElementSnapshot] {
        var found: [XCUIElementSnapshot] = []
        func walk(_ node: XCUIElementSnapshot) {
            if matches(node) { found.append(node) }
            node.children.forEach(walk)
        }
        walk(root)
        return found
    }

    /// Most snapshots ``snapshot(of:within:until:)`` lets fail before it gives up.
    static let snapshotAttempts = 3

    /// One accessibility snapshot of `root` that satisfies `ready`, polled within `timeout`.
    ///
    /// Use this instead of `waitForExistence` followed by `allElementsBoundByIndex` where a
    /// journey waits for something to appear and then reads many of its elements: the wait
    /// and every bound element's identifier, label and frame each evaluate the query again,
    /// and on a slow runner one of those evaluations can time out and fail the test outright
    /// ("Failed to get matching snapshots: Timed out while evaluating UI query", the Settings
    /// Quick Links menu just after a simulator reboot, #686). A snapshot that throws is
    /// retried, at least once even past the deadline, up to ``snapshotAttempts``; nothing a
    /// caller asserts on the result is relaxed.
    ///
    /// - Parameters:
    ///   - root: The element to snapshot, usually the app.
    ///   - timeout: How long to wait for `ready`; size it with ``budget(_:inVirtualMachine:)``.
    ///   - ready: Whether a snapshot shows what the caller waits for.
    /// - Returns: The first ready snapshot, or the last one taken when none was ready in time.
    /// - Throws: The snapshot error once the attempts or the deadline (after one retry) run out.
    @MainActor
    static func snapshot(
        of root: XCUIElement, within timeout: TimeInterval, until ready: (XCUIElementSnapshot) -> Bool
    ) throws -> XCUIElementSnapshot {
        let deadline = Date().addingTimeInterval(timeout)
        var failures = 0
        while true {
            do {
                let snapshot = try root.snapshot()
                if ready(snapshot) || Date() >= deadline { return snapshot }
            } catch {
                failures += 1
                if failures >= snapshotAttempts || (failures > 1 && Date() >= deadline) { throw error }
                XCTContext.runActivity(named: "Snapshot \(failures) failed (\(error.localizedDescription)); retrying") { _ in }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
    }

    // MARK: - Notifications bell

    /// Whether the bell's accessibility value is acceptable: empty, or on iOS 27+ exactly
    /// the system toolbar-item badge's own count phrase for the bell's current unread
    /// count ("2 items").
    ///
    /// From iOS 27 UIKit publishes the badge as the bar button's value, and SwiftUI's
    /// `accessibilityValue` cannot replace it (measured, #678). HIG Notifications rules
    /// out a custom badge ("Avoid custom images or components that mimic a badge"), so
    /// that one system phrase is allowed; any other value, a stale count, or a value
    /// with no unread rows still fails, and iOS 26 must stay empty
    /// (`.agents/controls/notifications/ios.md`).
    ///
    /// - Parameters:
    ///   - value: The bell's accessibility value.
    ///   - label: The bell's label, "Notifications" or "Notifications, N unread".
    ///   - osMajor: The simulator's iOS major version.
    /// - Returns: True when the value is empty or the current count's system phrase.
    static func isAllowedBellValue(
        _ value: Any?, label: String,
        osMajor: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    ) -> Bool {
        let text = (value as? String) ?? ""
        if text.isEmpty { return true }
        guard osMajor >= 27,
              let match = label.firstMatch(of: /^Notifications, ([0-9]+) unread$/),
              let unread = Int(match.1), (1...9).contains(unread)
        else { return false }
        return text == (unread == 1 ? "1 item" : "\(unread) items")
    }

    /// The bottom of what the navigation bar draws: its lowest title, button or search
    /// field.
    ///
    /// On iOS 26.5 and 27 a bar with the editor-role inline title and the drawer search
    /// reports an accessibility frame about 90 pt taller than what it draws (Songs: frame
    /// to 250 pt, search field ending at 160 pt), so content pinned under the visible
    /// chrome reads as overlapping the bar (#678). Read this line instead of
    /// `navigationBars.firstMatch.frame.maxY` where the pin line matters.
    ///
    /// - Parameter app: The app.
    /// - Returns: The lowest drawn item's bottom edge, or the bar's frame bottom when it
    ///   has no such item.
    /// - Throws: A snapshot XCTest cannot take.
    @MainActor
    static func navigationBarContentBottom(in app: XCUIApplication) throws -> CGFloat {
        let bar = app.navigationBars.firstMatch
        let drawn: Set<XCUIElement.ElementType> = [.button, .staticText, .searchField, .textField, .image]
        let items = try snapshotNodes(in: bar) { drawn.contains($0.elementType) && !$0.frame.isEmpty }
        return items.map(\.frame.maxY).max() ?? bar.frame.maxY
    }

    // MARK: - Quick Links

    /// Matches a Quick Links row by its identifier or, in a native menu that drops its rows'
    /// identifiers (iOS 27 on iPad and the Duo, #626, #662), an unidentified element whose
    /// VoiceOver label is exactly `label` (pattern `quick-links` R6).
    ///
    /// - Parameters:
    ///   - id: The row's full `fst.quick-links.item.*` identifier.
    ///   - label: The row's full VoiceOver label (the section's spoken title).
    /// - Returns: The predicate.
    static func quickLinkRowPredicate(id: String, label: String) -> NSPredicate {
        NSPredicate(format: "identifier == %@ OR (identifier == '' AND label == %@)", id, label)
    }

    /// The open Quick Links chooser's row for `section`, whether a sheet (identified rows) or
    /// a native menu (iOS 27 drops the identifiers, so the exact spoken label finds it).
    ///
    /// - Parameters:
    ///   - section: The section ID after `fst.quick-links.item.`, e.g. `band-Band_Duets`.
    ///   - label: The row's VoiceOver label, e.g. `Duos`.
    ///   - app: The app with the chooser open.
    /// - Returns: The row's button.
    @MainActor
    static func quickLinkRow(_ section: String, label: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(quickLinkRowPredicate(id: "fst.quick-links.item.\(section)", label: label)).firstMatch
    }

    /// One Quick Links section a journey expects: its ID after `fst.quick-links.item.` and
    /// its spoken title, which finds the row when an iOS 27 menu drops the identifier.
    typealias QuickLinkSection = (id: String, label: String)

    /// Every row of the open Quick Links chooser: identified rows, or unidentified ones
    /// (iOS 27 native menus, R6) whose label is exactly one of `sections`' spoken titles.
    ///
    /// - Parameters:
    ///   - sections: The sections the journey may meet, including ones it must not see.
    ///   - app: The app with the chooser open.
    /// - Returns: The rows' buttons, in hierarchy order (sort by frame for page order).
    @MainActor
    static func quickLinkRows(_ sections: [QuickLinkSection], in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(quickLinkRowsPredicate(sections))
    }

    /// Matches any row of ``quickLinkRows(_:in:)``, e.g. to find the chooser's list with
    /// `containing(_:)`.
    ///
    /// - Parameter sections: The sections the journey may meet.
    /// - Returns: The predicate.
    static func quickLinkRowsPredicate(_ sections: [QuickLinkSection]) -> NSPredicate {
        NSPredicate(
            format: "identifier BEGINSWITH 'fst.quick-links.item.' OR (identifier == '' AND label IN %@)",
            sections.map(\.label)
        )
    }

    /// Every row of the open Quick Links chooser in one snapshot, matched as
    /// ``quickLinkRowsPredicate(_:)`` matches them, in hierarchy order.
    ///
    /// Read the chooser's rows from ``snapshot(of:within:until:)`` with this rather than
    /// walking ``quickLinkRows(_:in:)`` (#686): every identifier, label and frame then comes
    /// from the same instant and no read can time out a query.
    ///
    /// - Parameters:
    ///   - sections: The sections the journey may meet, including ones it must not see.
    ///   - root: A snapshot of the app with the chooser open.
    /// - Returns: The rows' button snapshots.
    @MainActor
    static func quickLinkRowNodes(_ sections: [QuickLinkSection], in root: XCUIElementSnapshot) -> [XCUIElementSnapshot] {
        let labels = Set(sections.map(\.label))
        return nodes(in: root) {
            isQuickLinkRow(elementType: $0.elementType, identifier: $0.identifier, label: $0.label, labels: labels)
        }
    }

    /// Whether an element is a Quick Links row: a button with an `fst.quick-links.item.`
    /// identifier, or an unidentified button whose label is one of `labels` (R6), as
    /// ``quickLinkRowsPredicate(_:)``.
    ///
    /// - Parameters:
    ///   - elementType: The element's type.
    ///   - identifier: Its accessibility identifier, possibly empty.
    ///   - label: Its VoiceOver label.
    ///   - labels: The spoken titles of the sections the journey may meet.
    /// - Returns: True for a Quick Links row.
    static func isQuickLinkRow(
        elementType: XCUIElement.ElementType, identifier: String, label: String, labels: Set<String>
    ) -> Bool {
        guard elementType == .button else { return false }
        return identifier.hasPrefix("fst.quick-links.item.") || (identifier.isEmpty && labels.contains(label))
    }

    /// The section ID of a row from ``quickLinkRows(_:in:)``: its identifier after
    /// `fst.quick-links.item.` or, when a menu dropped it, the section its label names.
    ///
    /// - Parameters:
    ///   - identifier: The row's accessibility identifier, possibly empty.
    ///   - label: The row's VoiceOver label.
    ///   - sections: The sections the rows were found by.
    /// - Returns: The section ID, or the label itself when no section has that title.
    static func quickLinkSectionID(identifier: String, label: String, in sections: [QuickLinkSection]) -> String {
        let prefix = "fst.quick-links.item."
        if identifier.hasPrefix(prefix) { return String(identifier.dropFirst(prefix.count)) }
        return sections.first { $0.label == label }?.id ?? label
    }
}
