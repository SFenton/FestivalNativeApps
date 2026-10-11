#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Settings › Experimental Ranks accessibility (issue #541)
//
// The switch was hard-disabled ("Not yet available") while every page offered the
// experimental metrics. These tests pin what VoiceOver, Full Keyboard Access and Switch
// Control get from the now-enabled row: one enabled switch named with the web's label,
// off by default, a hint naming what it adds, read after Filter Invalid Scores (web App
// Settings order) and pressable, writing the shared `ExperimentalRanks.storageKey` the
// ranking pages read. The Rank By gating itself is covered by `ExperimentalRanksTests`
// and the View › Rank By options in `MacKeyboardNavigationTests`.

/// Host the full Settings page over a private store.
@MainActor
private func experimentalRanksHost(_ storage: UserDefaults) -> (NSHostingView<some View>, NSWindow) {
    let size = CGSize(width: 402, height: 2600)
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let host = nativeHostedView(
        NavigationStack { SettingsScreen(session: session) }
            .frame(width: size.width, height: size.height)
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: size
    )
    return (host, nativeHostedWindow(host, size: size))
}

private let experimentalRanksID = "fst.settings.experimental-ranks"

@MainActor
@Test func experimentalRanksSwitchIsEnabledNamedOffByDefaultAndInWebOrder() async throws {
    let storage = try #require(UserDefaults(suiteName: "fst.tests.experimental-ranks.\(UUID().uuidString)"))
    storage.set(true, forKey: "fst.accessibility.reduceMotion")
    let (host, window) = experimentalRanksHost(storage)
    defer { window.orderOut(nil) }
    _ = try await nativeHostedSettle(host) {
        nativeHostedAccessibilityElement(experimentalRanksID, in: host) != nil
    }
    let nodes = macAccessibilityTree(host, navigationOrder: true)
    macAccessibilityDump(nodes, name: "settings-experimental-ranks")
    let row = try #require(nodes.first { $0.identifier == experimentalRanksID })
    #expect(row.isElement)
    #expect(row.role == "AXCheckBox", "a switch, not a static row: \(row)")
    #expect(row.spokenName.contains("Enable Experimental Leaderboard Ranks"))
    #expect(row.value == "0", "off by default")
    #expect(!row.help.contains("not yet available"))
    #expect(!nodes.contains { $0.spokenName.contains("Not yet available") })

    let element = try #require(nativeHostedAccessibilityElement(experimentalRanksID, in: host))
    #expect((element.value(forKey: "isAccessibilityEnabled") as? Bool) == true, "the switch is no longer disabled")
    let frame = try #require(element.value(forKey: "accessibilityFrame") as? NSRect)
    #expect(frame.height >= 20 && frame.width >= 20, "a usable pointer target: \(frame)")

    // Reading order: after Filter Invalid Scores, as in the web's App Settings.
    let ids = nodes.filter(\.isElement).map(\.identifier)
    let filter = try #require(ids.firstIndex(of: "fst.settings.filter-invalid-scores"))
    let experimental = try #require(ids.firstIndex(of: experimentalRanksID))
    #expect(filter < experimental)
    #expect(macAccessibilityFindings(nodes).isEmpty)
}

@MainActor
@Test func pressingExperimentalRanksSwitchSavesTheSharedSetting() async throws {
    let storage = try #require(UserDefaults(suiteName: "fst.tests.experimental-ranks.\(UUID().uuidString)"))
    storage.set(true, forKey: "fst.accessibility.reduceMotion")
    let (host, window) = experimentalRanksHost(storage)
    defer { window.orderOut(nil) }
    _ = try await nativeHostedSettle(host) {
        nativeHostedAccessibilityElement(experimentalRanksID, in: host) != nil
    }
    #expect(storage.object(forKey: ExperimentalRanks.storageKey) == nil)
    let element = try #require(nativeHostedAccessibilityElement(experimentalRanksID, in: host))
    _ = element.perform(NSSelectorFromString("accessibilityPerformPress"))
    _ = try await nativeHostedSettle(host) { storage.bool(forKey: ExperimentalRanks.storageKey) }
    #expect(storage.bool(forKey: ExperimentalRanks.storageKey))
    _ = try await nativeHostedSettle(host) {
        macAccessibilityTree(host).first { $0.identifier == experimentalRanksID }?.value == "1"
    }
    #expect(macAccessibilityTree(host).first { $0.identifier == experimentalRanksID }?.value == "1")
}
#endif
