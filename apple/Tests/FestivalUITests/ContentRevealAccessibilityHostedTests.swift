#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalUI

// Issue #386 (accessibility tests for #327): a reload gate inside a page's scroll view
// (the band board's, below its retained song header) tells the page's fade scope while
// its animated reveal grows the scroll content, and the selected-row scroll waits for it
// (load-transition R5). With Reduce Motion, from the system or the app's own setting,
// the gate swaps instantly (R6), so it must never hold that scroll; and whatever the
// motion setting, the revealed page reads header-then-rows with the spinner gone.
// `SelectedRowRevealHostedTests` covers the whole board journey under the system
// setting; this host isolates the gate so the in-app setting, read through per-host app
// storage, is covered without touching the shared standard defaults.

// MARK: - Harness

/// The motion setting a hosted reveal runs with.
enum ContentRevealMotion: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case standard, systemReduceMotion, appReduceMotion

    var testDescription: String { rawValue }

    /// Whether the gate's reveal animates, and so holds the selected-row scroll.
    var animates: Bool { self == .standard }
}

/// What the hosted gate is told and what it reported back.
@MainActor @Observable
private final class ContentRevealFixture {
    /// Whether the board's rows are still loading.
    var loading = true
    /// Reveals so far; the page's scope re-arms on each, as the band board's does.
    var reveals = 0
    /// Whether the scope counted a running content reveal at each reveal.
    var heldAtReveal: [Bool] = []
}

/// Test IDs for the hosted page.
private enum ContentRevealID {
    static let header = "fst.test.content-reveal.header"
    static let spinner = "fst.test.content-reveal.loading"
    static let rowCount = 3
    static func row(_ index: Int) -> String { "fst.test.content-reveal.row.\(index)" }
}

/// The band board's structure: a retained header and a reload gate inside one scroll
/// view, with the page's fade scope on the scroll view.
private struct ContentRevealHarness: View {
    let fixture: ContentRevealFixture
    let scope: FestivalFadeInScope

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("Song header")
                    .accessibilityIdentifier(ContentRevealID.header)
                FestivalReloadGate(
                    key: 0, isLoading: fixture.loading, spinnerLabel: "Loading band scores",
                    spinnerIdentifier: ContentRevealID.spinner,
                    onReveal: {
                        // Called inside the reveal's update, after the gate told the scope.
                        fixture.heldAtReveal.append(scope.isRevealingContent)
                        fixture.reveals += 1
                    }
                ) {
                    VStack(spacing: 12) {
                        ForEach(0..<ContentRevealID.rowCount, id: \.self) { index in
                            Text("Band \(index + 1)")
                                .frame(maxWidth: .infinity, minHeight: 64)
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier(ContentRevealID.row(index))
                        }
                    }
                }
                .frame(minHeight: 400)
            }
            .padding(.horizontal, 16)
        }
        .festivalScrollFadeInScope(scope, resetKey: fixture.reveals)
    }
}

// MARK: - Tests

/// Reduce Motion (system or in-app) reveals the band board's rows without an animated
/// content reveal, so the selected-row scroll is never held for one; with standard motion
/// the reveal is counted while it grows the content and released when it ends (issue
/// #327, load-transition R5–R6; HIG Accessibility: "When Reduce Motion is on, reduce
/// automatic and repetitive animation"). Either way VoiceOver hears the spinner by its
/// label while loading, then the header and rows in order with the spinner gone.
@MainActor
@Test(arguments: ContentRevealMotion.allCases)
func contentRevealHoldsTheSelectedRowScrollOnlyWhenItAnimates(motion: ContentRevealMotion) async throws {
    let suiteName = "fst-content-reveal-\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suiteName))
    defer { storage.removePersistentDomain(forName: suiteName) }
    storage.set(motion == .appReduceMotion, forKey: "fst.accessibility.reduceMotion")
    let fixture = ContentRevealFixture()
    let scope = FestivalFadeInScope()
    let size = CGSize(width: 402, height: 700)
    let host = nativeHostedView(
        ContentRevealHarness(fixture: fixture, scope: scope)
            // Fades on (the hosted root turns them off for still captures).
            .environment(\.festivalFadeInEnabled, true)
            .environment(\._accessibilityReduceMotion, motion == .systemReduceMotion)
            .defaultAppStorage(storage)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }

    // Loading: the spinner is one element with its spoken label.
    var budget = NativeHostedPollBudget(.seconds(15))
    var spinner: NSObject?
    while spinner == nil {
        host.layoutSubtreeIfNeeded()
        spinner = nativeHostedAccessibilityElement(ContentRevealID.spinner, in: host)
        if spinner != nil { break }
        try #require(!budget.isExhausted, "the spinner is exposed while loading")
        try await budget.sleep(for: .milliseconds(20))
    }
    #expect(spinner?.value(forKey: "accessibilityLabel") as? String == "Loading band scores")
    #expect(nativeHostedAccessibilityElement(ContentRevealID.row(0), in: host) == nil, "no rows while loading")

    fixture.loading = false
    while fixture.reveals == 0 {
        try #require(!budget.isExhausted, "the gate revealed its rows")
        try await budget.sleep(for: .milliseconds(20))
    }
    #expect(
        fixture.heldAtReveal == [motion.animates],
        "\(motion): the selected-row scroll is held at the reveal only when it animates (\(fixture.heldAtReveal))"
    )

    // The reveal ends: a held scroll goes ahead, and the revealed page is readable.
    while scope.isRevealingContent {
        try #require(!budget.isExhausted, "the animated reveal ended and released the scroll")
        try await budget.sleep(for: .milliseconds(20))
    }
    await scope.contentRevealed()
    var ids: [String] = []
    while true {
        host.layoutSubtreeIfNeeded()
        ids = nativeHostedAccessibility(host).identifiers.filter { $0.hasPrefix("fst.test.content-reveal.") }
        if !ids.contains(ContentRevealID.spinner), ids.contains(ContentRevealID.row(ContentRevealID.rowCount - 1)) {
            break
        }
        try #require(!budget.isExhausted, "the spinner left and the rows were exposed (\(ids))")
        try await budget.sleep(for: .milliseconds(20))
    }
    let expected = [ContentRevealID.header] + (0..<ContentRevealID.rowCount).map(ContentRevealID.row)
    #expect(ids == expected, "reading order: header, then rows by rank (\(ids))")
    let labels = (0..<ContentRevealID.rowCount).map { index -> String? in
        guard let row = nativeHostedAccessibilityElement(ContentRevealID.row(index), in: host) else { return nil }
        // AppKit speaks a text element's value; a labelled element's label.
        return ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"].lazy
            .compactMap { row.responds(to: NSSelectorFromString($0)) ? row.value(forKey: $0) as? String : nil }
            .first { !$0.isEmpty }
    }
    #expect(labels == ["Band 1", "Band 2", "Band 3"], "each row is one element with its label (\(labels))")
    let frames = (0..<ContentRevealID.rowCount).compactMap { nativeHostedAccessibilityFrame(ContentRevealID.row($0), in: host) }
    #expect(frames.count == ContentRevealID.rowCount)
    #expect(zip(frames, frames.dropFirst()).allSatisfy { $0.maxY <= $1.minY + 0.5 }, "rows read top to bottom (\(frames))")
}
#endif
