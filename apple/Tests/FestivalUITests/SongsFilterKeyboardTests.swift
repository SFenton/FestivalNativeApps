#if os(macOS)
import AppKit
import Foundation
import ObjectiveC
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Keyboard host

/// Whether the hosted keyboard journey must run: `apple-ci` turns on Keyboard Navigation
/// and sets `FST_REQUIRE_KEYBOARD_NAVIGATION=1`, so a missing setting fails there rather
/// than skipping.
private let keyboardNavigationRequired =
    ProcessInfo.processInfo.environment["FST_REQUIRE_KEYBOARD_NAVIGATION"] == "1"

/// Whether System Settings › Keyboard › Keyboard navigation is on for this user. Tab moves
/// between buttons, checkboxes and disclosure triangles only then (HIG Keyboards: "people
/// can turn on Keyboard navigation … to move focus to every control"); with it off, Tab
/// reaches only text fields and lists, as in every Mac app.
@MainActor
private var keyboardNavigationEnabled: Bool { NSApplication.shared.isFullKeyboardAccessEnabled }

/// A window that is key without activating the test process (activation would take
/// focus from the person using the Mac).
private final class FilterKeyboardWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var isKeyWindow: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// The front window's focus as a person sees it: the control the key-view loop is on.
private struct FilterKeyboardFocus: CustomStringConvertible {
    /// Identifier of the smallest identified accessibility element under the focus.
    let id: String
    /// The first responder's frame in window coordinates.
    let frame: CGRect

    var description: String { "\(id.isEmpty ? "?" : id) \(frame)" }
}

/// Drives a hosted window with Tab, Shift-Tab and Space key events.
///
/// SwiftUI only moves keyboard focus in the app's key window of an active app, so while
/// the driver lives `NSApplication.keyWindow` returns the hosted window (or its attached
/// sheet) and `isActive` returns true; ``restore()`` puts both back.
@MainActor
private final class FilterKeyboardDriver {
    let window: NSWindow
    private let keyWindowMethod: Method
    private let activeMethod: Method
    private let originalKeyWindow: IMP
    private let originalActive: IMP

    init(window: NSWindow) throws {
        self.window = window
        let earlier = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        keyWindowMethod = try #require(class_getInstanceMethod(
            NSApplication.self, #selector(getter: NSApplication.keyWindow)
        ))
        activeMethod = try #require(class_getInstanceMethod(
            NSApplication.self, #selector(getter: NSApplication.isActive)
        ))
        let key: @convention(block) (AnyObject) -> NSWindow? = { [weak window] _ in
            MainActor.assumeIsolated { window.map { FilterKeyboardDriver.sheet(over: $0, excluding: earlier) } }
        }
        let active: @convention(block) (AnyObject) -> Bool = { _ in true }
        originalKeyWindow = method_setImplementation(keyWindowMethod, imp_implementationWithBlock(key))
        originalActive = method_setImplementation(activeMethod, imp_implementationWithBlock(active))
        self.earlier = earlier
    }

    /// Windows from earlier tests, whose emptied sheet windows the process keeps.
    private let earlier: Set<ObjectIdentifier>

    /// Put the real `keyWindow` and `isActive` back.
    func restore() {
        method_setImplementation(keyWindowMethod, originalKeyWindow)
        method_setImplementation(activeMethod, originalActive)
    }

    /// The window receiving keys: the Filter sheet while it is open.
    var front: NSWindow { Self.sheet(over: window, excluding: earlier) }

    /// The Filter sheet's window while it is open, else `window`. SwiftUI presents the sheet
    /// in its own window; it attaches to the parent only when the parent is on screen, which
    /// a hosted (never ordered-in) window is not.
    ///
    /// - Parameters:
    ///   - window: The Songs window.
    ///   - earlier: Windows that existed before the test, never its sheet.
    /// - Returns: The window that has keyboard focus.
    static func sheet(over window: NSWindow, excluding earlier: Set<ObjectIdentifier>) -> NSWindow {
        if let attached = window.attachedSheet { return attached }
        return NSApplication.shared.windows.first { candidate in
            candidate !== window && !earlier.contains(ObjectIdentifier(candidate))
                && "\(type(of: candidate))".contains("SheetPresentation")
                && candidate.contentView.map {
                    nativeHostedAccessibilityElement("fst.songs.filter.form", in: $0) != nil
                } == true
        } ?? window
    }

    /// Whether the Filter sheet is open.
    var sheetOpen: Bool { front !== window }

    /// Press and release one key in the front window.
    ///
    /// - Parameters:
    ///   - characters: The key's characters.
    ///   - keyCode: Its virtual key code.
    ///   - shift: Whether Shift is held.
    func press(_ characters: String, keyCode: UInt16, shift: Bool = false) async throws {
        let target = front
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = try #require(NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: shift ? [.shift] : [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: target.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: keyCode
            ))
            target.sendEvent(event)
        }
        try await settle()
    }

    /// Tab to the next control.
    func tab() async throws { try await press("\t", keyCode: 48) }

    /// Shift-Tab to the previous control.
    func shiftTab() async throws { try await press("\u{19}", keyCode: 48, shift: true) }

    /// Space: activate the focused button, checkbox or disclosure triangle.
    func space() async throws { try await press(" ", keyCode: 49) }

    /// Let SwiftUI apply the key's state change and lay out.
    func settle() async throws {
        for _ in 0..<4 {
            try await Task.sleep(for: .milliseconds(40))
            front.contentView?.layoutSubtreeIfNeeded()
        }
    }

    /// Wait until `condition` holds.
    ///
    /// - Parameters:
    ///   - what: What is awaited, for the failure.
    ///   - condition: The awaited state.
    func wait(_ what: String, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(20)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Timed out waiting for \(what)")
                return
            }
            try await settle()
        }
    }

    /// Identified accessibility elements of the front window (its toolbar included),
    /// with their frames in window coordinates.
    func elements() -> [(id: String, value: String, frame: CGRect)] {
        let target = front
        guard let root = target.contentView?.superview ?? target.contentView else { return [] }
        var found: [(String, String, CGRect)] = []
        var seen = Set<ObjectIdentifier>()
        func read(_ object: NSObject, _ key: String) -> Any? {
            object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
        }
        func walk(_ node: Any, depth: Int) {
            guard depth < 90, let object = node as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return }
            let id = nativeHostedAccessibilityString(object, "accessibilityIdentifier")
            if !id.isEmpty, let screen = (read(object, "accessibilityFrame") as? NSValue)?.rectValue {
                let value = (read(object, "accessibilityValue") as? NSNumber)?.stringValue
                    ?? nativeHostedAccessibilityString(object, "accessibilityValue")
                found.append((id, value, target.convertFromScreen(screen)))
            }
            for child in (read(object, "accessibilityChildren") as? [Any]) ?? [] {
                walk(child, depth: depth + 1)
            }
            if let view = object as? NSView {
                for subview in view.subviews { walk(subview, depth: depth + 1) }
            }
        }
        walk(root, depth: 0)
        return found
    }

    /// The control keyboard focus is on.
    var focus: FilterKeyboardFocus {
        guard let responder = front.firstResponder as? NSView else {
            return FilterKeyboardFocus(id: "", frame: .zero)
        }
        let frame = responder.convert(responder.bounds, to: nil)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let hit = elements()
            .filter { $0.frame.insetBy(dx: -0.5, dy: -0.5).contains(center) }
            .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        return FilterKeyboardFocus(id: hit?.id ?? responder.accessibilityIdentifier(), frame: frame)
    }

    /// The accessibility value of `id` in the front window ("1" on, "0" off).
    func value(_ id: String) -> String? { elements().first { $0.id == id }?.value }

    /// Whether `id` is realized in the front window.
    func has(_ id: String) -> Bool { elements().contains { $0.id == id } }

    /// Tab until focus is on `id`, at most one key-view loop and a half.
    ///
    /// - Parameter id: The control to reach.
    /// - Returns: The identifiers passed on the way, `id` last.
    @discardableResult
    func tab(to id: String) async throws -> [String] {
        var passed: [String] = []
        for _ in 0..<40 {
            try await tab()
            passed.append(focus.id)
            if passed.last == id { return passed }
        }
        Issue.record("Tab never reached \(id); passed \(passed)")
        return passed
    }

    /// One full key-view loop from the current focus, starting with the next control.
    func loop() async throws -> [FilterKeyboardFocus] {
        let start = focus
        var stops: [FilterKeyboardFocus] = []
        for _ in 0..<40 {
            try await tab()
            stops.append(focus)
            if focus.id == start.id, focus.frame == start.frame { return stops }
        }
        Issue.record("The key-view loop never returned to \(start): \(stops)")
        return stops
    }
}

/// Songs without a profile from the checked-in demo catalogue (album art removed: no
/// test-only image requests).
///
/// - Returns: The catalogue payload a loaded Songs page shows.
/// - Throws: A missing or invalid fixture.
private func filterKeyboardCatalogue() throws -> CatalogPayload {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(
        "contracts/fixtures/songs-demo.json"
    )))
    guard var catalogue = object as? [String: Any], var rows = catalogue["songs"] as? [[String: Any]] else {
        throw FestivalAPIError.invalidCatalogue
    }
    for row in rows.indices { rows[row].removeValue(forKey: "albumArt") }
    catalogue["songs"] = rows
    let songs = try JSONDecoder().decode(
        SongsResponse.self, from: JSONSerialization.data(withJSONObject: catalogue)
    )
    try songs.validate()
    return CatalogPayload(catalog: songs, publicationId: 7, observedPublicationId: 7, isStale: false)
}

// MARK: - Tests

/// Keyboard operation of Songs' Filter without a profile on the Mac (#432, for #77).
///
/// #77 put Filter in the Songs toolbar for every viewer and gave the sheet a General
/// section. With Keyboard navigation on, a person must reach the toolbar's Filter with
/// Tab, open it with Space, move through the General disclosure triangles, Select All /
/// Clear All, the option checkboxes, Reset Filters and Close in visual order (Shift-Tab
/// back), and operate each one with Space (HIG Keyboards; Accessibility, "Make sure people
/// can use your app with a keyboard alone").
@MainActor
@Suite(
    "Songs Filter by keyboard (macOS)",
    .serialized,
    .enabled("System Settings › Keyboard › Keyboard navigation is off; apple-ci turns it on") {
        await MainActor.run { keyboardNavigationRequired || keyboardNavigationEnabled }
    }
)
struct SongsFilterKeyboardTests {
    @Test("Tab reaches Filter; Space opens it and operates every General control")
    func filterSheetByKeyboardAlone() async throws {
        try #require(keyboardNavigationEnabled, """
            Keyboard navigation is off: `defaults write -g AppleKeyboardUIMode -int 2` \
            before the test process starts (apple-ci does).
            """)
        let suiteName = "fst-songs-filter-keyboard-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        defer { storage.removePersistentDomain(forName: suiteName) }
        let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
        let size = CGSize(width: 900, height: 820)
        let catalogue = try filterKeyboardCatalogue()
        let host = nativeHostedView(
            NavigationStack {
                SongsScreen(session: session, initialState: .loaded(catalogue), isVisible: true)
            }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
            size: size
        )
        let window = FilterKeyboardWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        let keys = try FilterKeyboardDriver(window: window)
        defer { keys.restore() }
        window.makeFirstResponder(host)
        try await keys.wait("Songs and its toolbar") { keys.has("fst.songs.list") && keys.has("fst.songs.filter") }

        // The toolbar: Sort, then Filter, in the key-view loop; Shift-Tab goes back.
        let toFilter = try await keys.tab(to: "fst.songs.filter")
        #expect(toFilter.dropLast().last == "fst.songs.sort", "Sort precedes Filter: \(toFilter)")
        try await keys.shiftTab()
        #expect(keys.focus.id == "fst.songs.sort", "\(keys.focus)")
        try await keys.tab()
        #expect(keys.focus.id == "fst.songs.filter", "\(keys.focus)")

        // Space opens the sheet without a profile.
        try await keys.space()
        try await keys.wait("the Filter sheet") { keys.sheetOpen && keys.has("fst.songs.filter.year") }
        let sheet = keys.front
        // The unattached sheet window opens without a first responder; a person's first Tab
        // starts from its content.
        sheet.makeFirstResponder(sheet.contentView)
        #expect(!keys.has("fst.songs.filter.score-sections"), "General only without a profile")

        // Visual order, top to bottom, then the toolbar's Close; Shift-Tab reverses it.
        let general = ["year", "duration", "shop", "double-bass", "reset"].map { "fst.songs.filter.\($0)" }
        try await keys.tab(to: general[0])
        let stops = try await keys.loop()
        let loop = stops.map(\.id)
        let order = loop.filter { general.contains($0) || $0 == "fst.songs.filter.done" }
        #expect(Array(order.prefix(general.count - 1)) == Array(general.dropFirst()), "\(loop)")
        #expect(order.contains("fst.songs.filter.done"), "Close is in the loop: \(loop)")
        // Every stop in the form is a named control. SwiftUI's sheet title bar adds one
        // unlabelled stop in its leading slot, above the form; a plain NavigationStack sheet
        // with a title and Close has the same stop, so it is system chrome, not ours.
        let form = try #require(keys.elements().first { $0.id == "fst.songs.filter.form" }?.frame)
        let unnamed = stops.filter { $0.id.isEmpty }
        #expect(unnamed.count <= 1, "At most the sheet title bar's own stop: \(stops)")
        #expect(unnamed.allSatisfy { !form.intersects($0.frame) }, "Unnamed stop in the form: \(stops)")
        try await keys.tab(to: "fst.songs.filter.double-bass")
        var back: [String] = []
        for _ in 0..<3 {
            try await keys.shiftTab()
            back.append(keys.focus.id)
        }
        #expect(back == ["shop", "duration", "year"].map { "fst.songs.filter.\($0)" }, "\(back)")

        // Year: Space discloses it, then Select All / Clear All and each decade follow.
        #expect(keys.value("fst.songs.filter.year") == "0")
        try await keys.space()
        try await keys.wait("Year to expand") { keys.has("fst.songs.filter.year.select-all") }
        #expect(keys.value("fst.songs.filter.year") == "1")
        let decades = keys.elements().map(\.id).filter {
            $0.hasPrefix("fst.songs.filter.year.") && $0.dropFirst("fst.songs.filter.year.".count).allSatisfy(\.isNumber)
        }
        #expect(!decades.isEmpty)
        let yearStops = try await keys.tab(to: decades.last ?? "")
        let bulk = ["fst.songs.filter.year.select-all", "fst.songs.filter.year.clear-all"]
        #expect(yearStops.filter { bulk.contains($0) || decades.contains($0) } == bulk + decades,
                "Select All, Clear All, then each decade: \(yearStops)")

        // Clear All, Select All and one decade checkbox by Space.
        try await keys.tab(to: bulk[1])
        try await keys.space()
        try await keys.wait("Clear All") { decades.allSatisfy { keys.value($0) == "0" } }
        try await keys.shiftTab()
        #expect(keys.focus.id == bulk[0], "\(keys.focus)")
        try await keys.space()
        try await keys.wait("Select All") { decades.allSatisfy { keys.value($0) == "1" } }
        try await keys.tab(to: decades[0])
        try await keys.space()
        try await keys.wait("the decade checkbox") { keys.value(decades[0]) == "0" }
        #expect(decades.dropFirst().allSatisfy { keys.value($0) == "1" })

        // Reset Filters restores every decade; the disclosure stays open.
        try await keys.tab(to: "fst.songs.filter.reset")
        try await keys.space()
        try await keys.wait("Reset Filters") { decades.allSatisfy { keys.value($0) == "1" } }
        #expect(keys.value("fst.songs.filter.year") == "1")

        // Every change saved as it was made: the filter is back to its default.
        let saved = try #require(storage.data(forKey: SongGeneralFilter.storageKey))
        #expect(try SongGeneralFilter.decodeSaved(saved) == SongGeneralFilter())

        // Close is reachable from the last control; Space on it is covered by
        // `closeBySpaceDismisses` (a hosted sheet window never attaches to its parent, so
        // SwiftUI cannot finish closing the real presenter's sheet here).
        try await keys.tab(to: "fst.songs.filter.done")
        #expect(keys.focus.frame.height >= 20, "\(keys.focus)")
        withExtendedLifetime((window, sheet)) {}
    }

    @Test("Space on Close and Escape each close the Filter sheet", arguments: ["space", "escape"])
    func closeByKeyboard(key: String) async throws {
        try #require(keyboardNavigationEnabled, "Keyboard navigation is off (see filterSheetByKeyboardAlone)")
        let record = FilterKeyboardPresentation()
        let size = CGSize(width: 700, height: 700)
        let host = nativeHostedView(FilterKeyboardPresenter(record: record).preferredColorScheme(.dark), size: size)
        let window = FilterKeyboardWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        window.contentView = host
        let keys = try FilterKeyboardDriver(window: window)
        defer { keys.restore() }
        try await keys.wait("the Filter sheet") { keys.sheetOpen && keys.has("fst.songs.filter.done") }
        keys.front.makeFirstResponder(keys.front.contentView)
        if key == "space" {
            try await keys.tab(to: "fst.songs.filter.done")
            try await keys.space()
        } else {
            try await keys.tab(to: "fst.songs.filter.year")
            try await keys.press("\u{1b}", keyCode: 53)
        }
        try await keys.wait("the sheet to close") { record.dismissals == 1 }
        withExtendedLifetime(window) {}
    }
}

/// Counts a presenter's dismissals.
@MainActor
private final class FilterKeyboardPresentation {
    var dismissals = 0
}

/// Presents the real Filter sheet (no profile) as Songs does, recording each dismissal.
private struct FilterKeyboardPresenter: View {
    let record: FilterKeyboardPresentation
    @State private var shown = false

    var body: some View {
        Color.clear
            .onAppear { shown = true }
            .sheet(isPresented: Binding(get: { shown }, set: { presented in
                if !presented { record.dismissals += 1 }
                shown = presented
            })) {
                SongsFilterSheet(
                    appliedGeneral: SongGeneralFilter(), showShop: true, shopAvailable: true,
                    availableDecades: [2000, 2010, 2020], availableDurations: [2, 3],
                    selectedPlayer: false, scoreAvailable: false, onApply: { _, _, _ in }
                )
                .macSheetFrame()
            }
    }
}
#endif
