import XCTest

// Temporary probe for #665; not committed.
final class ZZFKAProbeTests: XCTestCase {
    @MainActor
    private func probe(_ name: String, env: [String: String], ax5: Bool) {
        var environment = [
            "FST_API_BASE_URL": ProcessInfo.processInfo.environment["FST_BOARD_FADE_FIXTURE_URL"] ?? "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
        ]
        environment.merge(env) { $1 }
        let app = FestivalApp.makeApp(environment)
        if ax5 {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        }
        app.launch()
        Thread.sleep(forTimeInterval: 8)
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true"))
        let before = focused.allElementsBoundByIndex.map { "\($0.elementType.rawValue):\($0.identifier):\($0.label):\($0.frame)" }
        for i in 0..<3 {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "\(name)-shot\(i)"; shot.lifetime = .keepAlways; add(shot)
            Thread.sleep(forTimeInterval: 0.7)
        }
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "\(name)-tree"; tree.lifetime = .keepAlways; add(tree)
        Self.log("PROBE \(name) before=\(before)")
        for (i, key) in [XCUIKeyboardKey.tab, .tab, .downArrow].enumerated() {
            let start = Date()
            app.typeKey(key.rawValue, modifierFlags: [])
            let elapsed = Date().timeIntervalSince(start)
            let after = focused.allElementsBoundByIndex.map { "\($0.elementType.rawValue):\($0.identifier):\($0.label):\($0.frame)" }
            Self.log("PROBE \(name) key\(i) typeKey=\(Int(elapsed))s after=\(after)")
        }
        app.terminate()
    }

    static func log(_ line: String) {
        print(line)
        let url = URL(fileURLWithPath: "/tmp/fst-665/fka.log")
        let data = Data("\(Date().timeIntervalSince1970) \(line)\n".utf8)
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { try? data.write(to: url) }
    }

    @MainActor func testD_SongsNoNav() { probe("songs", env: ["FST_DEBUG_TAB": "songs"], ax5: false) }
    @MainActor func testA_BoardAX5() { probe("boardAX5", env: ["FST_DEBUG_ROUTE": "playerBands:fixture-player-1"], ax5: true) }
    @MainActor func testB_Settings() { probe("settings", env: ["FST_DEBUG_TAB": "settings"], ax5: false) }
    @MainActor func testC_BoardDefault() { probe("boardDefault", env: ["FST_DEBUG_ROUTE": "playerBands:fixture-player-1"], ax5: false) }
}
