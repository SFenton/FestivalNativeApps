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
        var found: [XCUIElementSnapshot] = []
        func walk(_ node: XCUIElementSnapshot) {
            if matches(node) { found.append(node) }
            node.children.forEach(walk)
        }
        walk(try root.snapshot())
        return found
    }
}
