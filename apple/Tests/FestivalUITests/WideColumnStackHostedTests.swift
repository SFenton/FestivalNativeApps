#if os(macOS)
import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Fixtures (issue #355, pattern `wide-columns` R7)

private let tolerance: CGFloat = 1.5

/// Sections of unequal heights in a `WideColumnStack`, identified for frame reads.
private struct StackFixture: View {
    let columns: Int
    let layout: DeviceLayout
    let size: CGSize
    nonisolated static let heights: [CGFloat] = [500, 120, 120, 120, 120]

    var body: some View {
        WideColumnStack(columns: columns, spacing: 28) {
            ForEach(Array(Self.heights.enumerated()), id: \.offset) { index, height in
                Color.blue.frame(height: height)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement()
                    .accessibilityLabel("Section \(index)")
                    .accessibilityIdentifier("fixture.section.\(index)")
            }
        }
        .padding(.horizontal, 16)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .environment(\.deviceLayout, layout)
        .preferredColorScheme(.dark)
    }
}

/// Frames of `ids` once they are all present and measurement has settled.
@MainActor
private func settledFrames(_ host: NSView, _ ids: [String]) async throws -> [String: CGRect] {
    var result: [String: CGRect] = [:]
    var previous: [String: CGRect] = [:]
    for _ in 0..<60 {
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        result = ids.reduce(into: [:]) { $0[$1] = nativeHostedAccessibilityFrame($1, in: host) }
        if result.count == ids.count, result == previous { break }
        previous = result
    }
    return result
}

private let sectionIds = (0..<5).map { "fixture.section.\($0)" }

// MARK: - Stack

/// Two columns flow column-major: the tall first section stands alone on the left, the
/// rest stack top-down on the right, and on a flat Duo inner display the gutter is the
/// hinge (R3, R7).
@MainActor @Test func wideColumnStackSplitsColumnMajorAtTheHinge() async throws {
    let size = CGSize(width: 951, height: 669)
    let layout = DeviceLayout.resolve(LayoutSignals(size: size, widthClass: .regular, hinge: .fullyOpen))
    let host = nativeHostedView(StackFixture(columns: 2, layout: layout, size: size), size: size)
    let window = nativeHostedWindow(host, size: size)
    defer { withExtendedLifetime(window) {} }

    let frames = try await settledFrames(host, sectionIds)
    let first = try #require(frames["fixture.section.0"])
    let rest = try sectionIds.dropFirst().map { try #require(frames[$0]) }
    #expect(first.minX < 20)
    #expect(abs(first.maxX + WideColumns.spacing / 2 - size.width / 2) < tolerance)
    for frame in rest {
        #expect(abs(frame.minX - (first.maxX + WideColumns.spacing)) < tolerance)
    }
    // Reading order is top-down within the right column, 28 pt apart.
    for (upper, lower) in zip(rest, rest.dropFirst()) {
        #expect(abs(lower.minY - upper.maxY - 28) < tolerance)
    }
    #expect(abs(rest[0].minY - first.minY) < tolerance)
}

/// One column stacks every section full width like a leading `VStack`.
@MainActor @Test func wideColumnStackOneColumnStacksFullWidth() async throws {
    let size = CGSize(width: 669, height: 1400)
    let layout = DeviceLayout.resolve(LayoutSignals(size: size, widthClass: .regular, hinge: .fullyOpen))
    let host = nativeHostedView(StackFixture(columns: 1, layout: layout, size: size), size: size)
    let window = nativeHostedWindow(host, size: size)
    defer { withExtendedLifetime(window) {} }

    let frames = try await settledFrames(host, sectionIds).sorted { $0.key < $1.key }.map(\.value)
    #expect(frames.count == StackFixture.heights.count)
    for frame in frames {
        #expect(abs(frame.minX - 16) < tolerance)
        #expect(abs(frame.width - (size.width - 32)) < tolerance)
    }
    for (upper, lower) in zip(frames, frames.dropFirst()) {
        #expect(abs(lower.minY - upper.maxY - 28) < tolerance)
    }
}

// MARK: - Settings

@MainActor
private func settingsHost(pane: SettingsPane?, size: CGSize) -> (NSHostingView<some View>, NSWindow) {
    let storage = UserDefaults(suiteName: "fst.tests.settings-columns.\(UUID().uuidString)")!
    storage.set(true, forKey: "fst.accessibility.reduceMotion")
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let host = nativeHostedView(
        NavigationStack { SettingsScreen(session: session, pane: pane) }
            .frame(width: size.width, height: size.height)
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: size
    )
    return (host, nativeHostedWindow(host, size: size))
}

/// The Mac Settings window's General pane puts its sections in two columns, in order:
/// Accessibility starts the left column, Reset ends the right.
@MainActor @Test func macSettingsGeneralPaneShowsTwoColumns() async throws {
    let (host, window) = settingsHost(pane: .general, size: MacSettingsView.size)
    defer { window.orderOut(nil) }
    let ids = ["fst.settings.reduce-motion", "fst.settings.hide-shop", "fst.settings.reset"]
    let image = try await nativeHostedSettle(host) {
        let present = nativeHostedAccessibility(host).identifiers
        return ids.allSatisfy(present.contains)
    }
    _ = try nativeHostedPNG(image, filename: "mac-settings-general-columns.png", environment: "FST_SETTINGS_RENDER_OUT")
    let frames = try await settledFrames(host, ids)
    let motion = try #require(frames["fst.settings.reduce-motion"])
    let reset = try #require(frames["fst.settings.reset"])
    let mid = MacSettingsView.size.width / 2
    #expect(motion.maxX < mid)
    #expect(reset.minX > mid)
}

/// A portrait Settings surface keeps one column: every section shares the leading edge.
@MainActor @Test func settingsPortraitSurfaceKeepsOneColumn() async throws {
    let size = CGSize(width: 860, height: 2600)
    let (host, window) = settingsHost(pane: .general, size: size)
    defer { window.orderOut(nil) }
    let ids = ["fst.settings.reduce-motion", "fst.settings.reset"]
    _ = try await nativeHostedSettle(host) {
        let present = nativeHostedAccessibility(host).identifiers
        return ids.allSatisfy(present.contains)
    }
    let frames = try await settledFrames(host, ids)
    let motion = try #require(frames["fst.settings.reduce-motion"])
    let reset = try #require(frames["fst.settings.reset"])
    #expect(abs(motion.minX - reset.minX) < 40)
    #expect(reset.minY > motion.maxY)
}
#endif
