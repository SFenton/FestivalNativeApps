import Foundation
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Settings persistence

/// A value different from the registered default, to prove a real write.
private func changed(_ value: SettingDefault) -> SettingDefault {
    switch value {
    case let .bool(flag): .bool(!flag)
    case .double: .double(3.5)
    case .string: .string(PathDisplayMode.text.rawValue)
    case .data: .data(Data([1, 2, 3]))
    }
}

/// Every registered setting survives a new `UserDefaults` instance (cold-start read path).
@Test func everySettingRoundTripsAcrossStoreInstances() throws {
    let suite = "fst.tests.settings.\(UUID().uuidString)"
    let writer = try #require(UserDefaults(suiteName: suite))
    defer { writer.removePersistentDomain(forName: suite) }
    for (key, value) in SettingsRegistry.defaults {
        SettingsRegistry.write(changed(value), for: key, in: writer)
    }
    let reader = try #require(UserDefaults(suiteName: suite))
    for (key, value) in SettingsRegistry.defaults {
        #expect(SettingsRegistry.value(for: key, in: reader) == changed(value), "\(key)")
    }
}

/// Absent keys read as their registered defaults, matching `@AppStorage` initial values.
@Test func missingSettingsReadDefaults() throws {
    let suite = "fst.tests.settings.\(UUID().uuidString)"
    let store = try #require(UserDefaults(suiteName: suite))
    defer { store.removePersistentDomain(forName: suite) }
    for (key, value) in SettingsRegistry.defaults {
        #expect(SettingsRegistry.value(for: key, in: store) == value, "\(key)")
    }
}

/// Reset restores **every** registered setting, so a new toggle cannot be forgotten.
@MainActor
@Test func resetRestoresEveryRegisteredSetting() {
    let defaults = UserDefaults.standard
    let originals = SettingsRegistry.defaults.map { ($0.key, defaults.object(forKey: $0.key)) }
    defer {
        for (key, original) in originals {
            if let original { defaults.set(original, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }
    for (key, value) in SettingsRegistry.defaults {
        SettingsRegistry.write(changed(value), for: key, in: defaults)
    }
    SettingsScreen(session: FestivalSession(factory: { throw FestivalAPIError.invalidResource }))
        .resetAppSettings()
    for (key, value) in SettingsRegistry.defaults {
        #expect(SettingsRegistry.value(for: key, in: defaults) == value, "\(key)")
    }
}

/// Every `fst.settings.*` / `fst.accessibility.*` `@AppStorage` key in the UI is registered.
@Test func everyAppStorageSettingIsRegistered() throws {
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/FestivalUI")
    let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
    let pattern = try Regex(#"@AppStorage\("(fst\.(?:settings|accessibility)\.[A-Za-z]+)"\)"#)
    var found = Set<String>()
    for case let url as URL in files where url.pathExtension == "swift" {
        let text = try String(contentsOf: url, encoding: .utf8)
        for match in text.matches(of: pattern) {
            if let key = match.output[1].substring { found.insert(String(key)) }
        }
    }
    let registered = Set(SettingsRegistry.defaults.map(\.key))
    #expect(!found.isEmpty)
    #expect(found.subtracting(registered).isEmpty, "Unregistered: \(found.subtracting(registered).sorted())")
}

/// The Tap Diagnostics / Tap Telemetry settings were removed (owner #374): neither key is
/// registered, stored by Settings or offered as a Quick Link in any build.
@Test func tapDiagnosticsSettingsStayRemoved() throws {
    let retired = ["fst.settings.tapDiagnostics", "fst.settings.tapTelemetry"]
    #expect(Set(SettingsRegistry.defaults.map(\.key)).isDisjoint(with: retired))
    let settings = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/FestivalUI/Features/Settings")
    let files = try #require(FileManager.default.enumerator(at: settings, includingPropertiesForKeys: nil))
    for case let url as URL in files where url.pathExtension == "swift" {
        let text = try String(contentsOf: url, encoding: .utf8)
        for needle in retired + ["fst.settings.tap-diagnostics", "fst.settings.tap-telemetry", "id: \"diagnostics\""] {
            #expect(!text.contains(needle), "\(url.lastPathComponent) still mentions \(needle)")
        }
    }
}
