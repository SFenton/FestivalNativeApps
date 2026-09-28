#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
import FestivalCore
@testable import FestivalUI

// MARK: - Presentation helpers

@Test func serviceStatusSymbolsAreDistinctPerIssueFamily() {
    let issues: [ServiceIssue] = [
        .scrapeInProgress(retryAfter: 30), .unavailable(retryAfter: nil), .syncing,
        .notFound, .offline, .other(message: "x"),
    ]
    let symbols = issues.map(ServiceStatusView.symbolName(for:))
    #expect(Set(symbols).count == issues.count)
}

@Test func serviceStatusCountdownClockFormatsMinutesAndSeconds() {
    #expect(ServiceStatusView.clock(27) == "0:27")
    #expect(ServiceStatusView.clock(120) == "2:00")
    #expect(ServiceStatusView.clock(-4) == "0:00")
}

// MARK: - Hosted behavior

@MainActor
private final class RetryCounter {
    var count = 0
}

/// A scrape freeze counts down from `Retry-After` and retries on its own; a
/// generic outage renders differently and never retries without the person.
@MainActor
@Test func scrapeFreezeRetriesAutomaticallyWhileOtherIssuesWait() async throws {
    let size = CGSize(width: 390, height: 600)
    let frozen = RetryCounter()
    let scope = "tests.freeze.\(UUID().uuidString)"
    let freezeHost = nativeHostedView(
        ServiceStatusView(.scrapeInProgress(retryAfter: 1), title: "Rankings unavailable", scope: scope) {
            frozen.count += 1
        },
        size: size
    )
    let freezeWindow = nativeHostedWindow(freezeHost, size: size)

    let waiting = RetryCounter()
    let otherHost = nativeHostedView(
        ServiceStatusView(.unavailable(retryAfter: 1), title: "Rankings unavailable") {
            waiting.count += 1
        },
        size: size
    )
    let otherWindow = nativeHostedWindow(otherHost, size: size)

    let inlineCounter = RetryCounter()
    let inlineHost = nativeHostedView(
        ServiceStatusInline(.scrapeInProgress(retryAfter: 1), scope: scope + ".inline") {
            inlineCounter.count += 1
        },
        size: CGSize(width: 390, height: 80)
    )
    let inlineWindow = nativeHostedWindow(inlineHost, size: CGSize(width: 390, height: 80))

    let deadline = Date().addingTimeInterval(8)
    while (frozen.count == 0 || inlineCounter.count == 0), Date() < deadline {
        try await Task.sleep(for: .milliseconds(100))
    }
    #expect(frozen.count >= 1)
    #expect(inlineCounter.count >= 1)
    #expect(waiting.count == 0)
    #expect(try nativeHostedImage(freezeHost) != nativeHostedImage(otherHost))
    _ = (freezeWindow, otherWindow, inlineWindow)
}

@MainActor
@Test func serviceStatusOverlayOnlyCoversContentWhileFailing() throws {
    let size = CGSize(width: 390, height: 400)
    let clear = nativeHostedView(
        Text("Loaded").serviceStatusOverlay(nil, title: "Unavailable") {}, size: size
    )
    let failing = nativeHostedView(
        Text("Loaded").serviceStatusOverlay(.offline, title: "Unavailable") {}, size: size
    )
    let legacy = nativeHostedView(
        ServiceUnavailableView(title: "Unavailable", message: "Check your connection and try again.") {},
        size: size
    )
    let clearWindow = nativeHostedWindow(clear, size: size)
    let failingWindow = nativeHostedWindow(failing, size: size)
    let legacyWindow = nativeHostedWindow(legacy, size: size)
    #expect(try nativeHostedImage(clear) != nativeHostedImage(failing))
    #expect(try nativeHostedImage(legacy) != nativeHostedImage(clear))
    _ = (clearWindow, failingWindow, legacyWindow)
}
#endif
