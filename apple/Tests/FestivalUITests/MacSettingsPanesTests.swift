#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Pane model

/// Every pane has a short toolbar label (HIG Toolbars: under 15 characters), a symbol
/// and a unique identifier, and a missing or unknown stored pane restores General.
@Test func settingsPanesHaveShortTitlesAndRestoreGeneral() {
    #expect(SettingsPane.allCases.map(\.title) == ["General", "Songs", "Paths", "Guides", "Service", "About"])
    for pane in SettingsPane.allCases {
        #expect(pane.title.count < 15)
        #expect(!pane.symbol.isEmpty)
    }
    #expect(Set(SettingsPane.allCases.map(\.accessibilityIdentifier)).count == SettingsPane.allCases.count)
    #expect(SettingsPane.restored(from: nil) == .general)
    #expect(SettingsPane.restored(from: "nowhere") == .general)
    #expect(SettingsPane.restored(from: "paths") == .paths)
}

// MARK: - Pane content

/// Settings identifiers each pane must show; every registered setting appears in
/// exactly one pane.
private let paneIdentifiers: [SettingsPane: [String]] = [
    .general: [
        "fst.settings.reduce-motion", "fst.settings.more-contrast", "fst.settings.hide-shop",
        "fst.settings.shop-highlights", "fst.settings.reset",
    ],
    .songs: [
        "fst.settings.show-instrument-icons", "fst.settings.enable-visual-order",
        "fst.settings.instrument.Solo_Guitar", "fst.settings.metadata.score",
    ],
    .paths: [
        "fst.settings.path-default-view", "fst.settings.path-column-order",
        "fst.settings.filter-invalid-scores",
    ],
    .about: ["fst.settings.whats-new", "fst.settings.licenses"],
]

@MainActor
private func paneHost(_ pane: SettingsPane) -> (NSHostingView<some View>, NSWindow) {
    let storage = UserDefaults(suiteName: "fst.tests.mac-settings.\(UUID().uuidString)")!
    storage.set(true, forKey: "fst.accessibility.reduceMotion")
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let size = MacSettingsView.size
    let host = nativeHostedView(
        NavigationStack { SettingsScreen(session: session, pane: pane) }
            .frame(width: size.width, height: 2600)
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: size.width, height: 2600)
    )
    return (host, nativeHostedWindow(host, size: CGSize(width: size.width, height: 2600)))
}

/// Each Mac Settings pane shows its own settings (same identifiers as the iPhone page)
/// and none of another pane's.
@MainActor
@Test(arguments: [SettingsPane.general, .songs, .paths, .about])
func macSettingsPaneShowsOnlyItsSettings(_ pane: SettingsPane) async throws {
    let (host, window) = paneHost(pane)
    defer { window.orderOut(nil) }
    let expected = paneIdentifiers[pane] ?? []
    let image = try await nativeHostedSettle(host) {
        let ids = nativeHostedAccessibility(host).identifiers
        return expected.allSatisfy(ids.contains)
    }
    _ = try nativeHostedPNG(image, filename: "mac-settings-\(pane.rawValue).png", environment: "FST_SETTINGS_RENDER_OUT")
    assertRendersContent(host, image: image)
    let ids = nativeHostedAccessibility(host).identifiers
    for (other, otherIds) in paneIdentifiers where other != pane {
        for id in otherIds {
            #expect(!ids.contains(id), "\(pane) pane shows \(other)'s \(id)")
        }
    }
}

/// The Guides and Service panes show their sections and no other pane's settings.
@MainActor
@Test func macSettingsGuidesAndServicePanesShowTheirSections() async throws {
    for (pane, title) in [(SettingsPane.guides, "First Run Guides"), (.service, ServiceInfoText.title)] {
        let (host, window) = paneHost(pane)
        defer { window.orderOut(nil) }
        let image = try await nativeHostedSettle(host, untilText: [title])
        // Before its first read the Service pane shows only the state row (web parity, #22),
        // so its glyph ink on the tall canvas sits under the default floor.
        assertRendersContent(
            host, image: image, minimumInkFraction: pane == .service ? 0.001 : 0.002,
            containing: [title], notContaining: ["Show Instruments"]
        )
    }
}

/// In the Mac Settings window a single-choice setting is a pop-up button showing the
/// current choice, not the inline accordion.
@MainActor
@Test func macSettingsChoiceRowIsAPopUpButton() async throws {
    let size = CGSize(width: 640, height: 120)
    var mode = PathDisplayMode.text
    let binding = Binding(get: { mode }, set: { mode = $0 })
    let host = nativeHostedView(
        SettingsChoiceRow(
            title: "CHOpt Path Default View", detail: "Choose a view.",
            options: PathDisplayMode.allCases, label: \.label, selection: binding,
            identifier: "fst.settings.path-default-view"
        )
        .environment(\.settingsChoicesUsePopUpButtons, true)
        .padding(16)
        .frame(width: size.width, height: size.height)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Text"])
    // The accordion speaks "Text, Collapsed"; the pop-up button only its choice.
    assertRendersContent(host, image: image, containing: ["Text"], notContaining: ["Collapsed", "Expanded"])
}
#endif
