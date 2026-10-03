import Foundation
import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - O1 (b): hinged devices rotate, iPhone stays portrait

/// A hinged device (iPhone Duo) supports every orientation; others keep their declaration.
@Test func hingedDevicesSupportEveryOrientation() {
    #expect(OrientationPolicy.supported(declared: .portrait, hasHinge: true) == .all)
    #expect(OrientationPolicy.supported(declared: [], hasHinge: true) == .all)
}

/// Regular iPhones stay portrait-locked; iPad keeps all four; nothing declared means portrait.
@Test func devicesWithoutAHingeKeepTheirDeclaration() {
    #expect(OrientationPolicy.supported(declared: .portrait, hasHinge: false) == .portrait)
    #expect(OrientationPolicy.supported(declared: .all, hasHinge: false) == .all)
    #expect(OrientationPolicy.supported(declared: [], hasHinge: false) == .portrait)
}

/// Info.plist names parse, unknown names are ignored, and the device-specific key wins.
@Test func orientationDeclarationsReadTheIdiomKey() {
    let info: [String: Any] = [
        "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
        "UISupportedInterfaceOrientations~ipad": [
            "UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
            "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight", "Bogus",
        ],
    ]
    #expect(OrientationPolicy.declared(in: info, isPad: false) == .portrait)
    #expect(OrientationPolicy.declared(in: info, isPad: true) == .all)
    #expect(OrientationPolicy.declared(in: [:], isPad: false).isEmpty)
}

/// Only a reported hinge or vertical bar marks the device hinged, once; nil never clears it.
@MainActor
@Test func hingePresenceIsStickyAndFiresOnce() {
    var updates = 0
    let presence = HingePresence { updates += 1 }
    presence.record(hinge: nil, verticalBarEdge: nil)
    #expect(!presence.hasHinge)
    #expect(updates == 0)
    presence.record(hinge: .closed)
    presence.record(hinge: .fullyOpen)
    presence.record(hinge: nil)
    #expect(presence.hasHinge)
    #expect(updates == 1)
}

/// With the hinge unreported, the vertical bar (iPhone Duo only) is the fallback signal,
/// as in `DeviceLayout`'s pose; a regular iPhone reports neither.
@MainActor
@Test func verticalBarMarksTheDeviceHingedWhenTheHingeIsUnreported() {
    let duo = HingePresence {}
    duo.record(hinge: nil, verticalBarEdge: .trailing)
    #expect(duo.hasHinge)
    let phone = HingePresence {}
    phone.record(hinge: nil, verticalBarEdge: nil)
    #expect(!phone.hasHinge)
}

/// Guard: the iPhone declaration in `project.yml` stays portrait-only (operator,
/// 2026-10-02), so a regular iPhone — which never reports a hinge — stays portrait.
@Test func iPhoneDeclarationStaysPortraitOnly() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let yaml = try String(contentsOf: root.appending(path: "project.yml"), encoding: .utf8)
    let lines = yaml.components(separatedBy: .newlines)
    let start = try #require(lines.firstIndex {
        $0.trimmingCharacters(in: .whitespaces) == "UISupportedInterfaceOrientations:"
    })
    let values = lines[(start + 1)...]
        .prefix { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }
        .map { $0.trimmingCharacters(in: .whitespaces).dropFirst(2).trimmingCharacters(in: .whitespaces) }
    let declared = SupportedOrientations(infoPlistValues: values)
    #expect(declared == .portrait)
    #expect(OrientationPolicy.supported(declared: declared, hasHinge: false) == .portrait)
}
