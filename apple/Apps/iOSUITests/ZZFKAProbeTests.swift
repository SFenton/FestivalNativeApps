import XCTest

// Temporary probe for #665; reverted before the fix lands.
final class ZZFKAProbeTests: XCTestCase {
    @MainActor
    func testE_BoardIdle() {
        let mode = ProcessInfo.processInfo.environment["FST_PROBE_MODE"] ?? "unknown"
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": ProcessInfo.processInfo.environment["FST_BOARD_FADE_FIXTURE_URL"] ?? "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_ROUTE": "playerBands:fixture-player-1",
            "FST_DEBUG_ANIM_LOG": "/tmp/fst-665/anim-\(mode).log",
        ])
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["fst.player-bands.page-info"].waitForExistence(timeout: 60))
        Thread.sleep(forTimeInterval: 10)
        Self.log("PROBE \(mode) mark-before-tap")
        var start = Date()
        app.descendants(matching: .any)["fst.player-bands.page-info"].tap()
        Self.log("PROBE \(mode) tap=\(Int(Date().timeIntervalSince(start)))s")
        for (i, key) in [XCUIKeyboardKey.tab, .downArrow].enumerated() {
            Self.log("PROBE \(mode) mark-before-key\(i)")
            start = Date()
            app.typeKey(key.rawValue, modifierFlags: [])
            Self.log("PROBE \(mode) key\(i)=\(Int(Date().timeIntervalSince(start)))s")
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "board-\(mode)"; shot.lifetime = .keepAlways; add(shot)
        app.terminate()
    }

    static func log(_ line: String) {
        print(line)
        let url = URL(fileURLWithPath: "/tmp/fst-665/fka.log")
        let data = Data("\(Date().timeIntervalSince1970) \(line)\n".utf8)
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { try? data.write(to: url) }
    }
}
