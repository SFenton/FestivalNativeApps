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
///
/// The countdowns run on a `ManualTestClock`: hosted snapshot tests share the one
/// main actor, and a busy suite once delayed the real one-second tick past this
/// test's old eight-second wall-clock deadline. Now the test waits for events
/// (both countdowns asleep, both retries fired) with no wall-clock deadline;
/// `.timeLimit` is a hang guard, not a pacing bound.
@MainActor
@Test(.timeLimit(.minutes(10)))
func scrapeFreezeRetriesAutomaticallyWhileOtherIssuesWait() async throws {
    let size = CGSize(width: 390, height: 600)
    let clock = ManualTestClock()
    let (retries, retried) = AsyncStream.makeStream(of: String.self)
    let frozen = RetryCounter()
    let scope = "tests.freeze.\(UUID().uuidString)"
    let freezeHost = nativeHostedView(
        ServiceStatusView(.scrapeInProgress(retryAfter: 1), title: "Rankings unavailable", scope: scope) {
            frozen.count += 1
            retried.yield("freeze")
        }
        .environment(\.serviceRetryClock, clock),
        size: size
    )
    let freezeWindow = nativeHostedWindow(freezeHost, size: size)

    let waiting = RetryCounter()
    let otherHost = nativeHostedView(
        ServiceStatusView(.unavailable(retryAfter: 1), title: "Rankings unavailable") {
            waiting.count += 1
        }
        .environment(\.serviceRetryClock, clock),
        size: size
    )
    let otherWindow = nativeHostedWindow(otherHost, size: size)

    let inlineCounter = RetryCounter()
    let inlineHost = nativeHostedView(
        ServiceStatusInline(.scrapeInProgress(retryAfter: 1), scope: scope + ".inline") {
            inlineCounter.count += 1
            retried.yield("inline")
        }
        .environment(\.serviceRetryClock, clock),
        size: CGSize(width: 390, height: 80)
    )
    let inlineWindow = nativeHostedWindow(inlineHost, size: CGSize(width: 390, height: 80))

    // Both freezes wait out exactly one one-second tick; nothing retries early.
    let one = ManualTestClock.Instant(offset: .seconds(1))
    #expect(await clock.sleepers(atLeast: 2) == [one, one])
    #expect(frozen.count == 0)
    #expect(inlineCounter.count == 0)

    clock.advance(by: .seconds(1))
    var pending: Set = ["freeze", "inline"]
    for await source in retries {
        pending.remove(source)
        if pending.isEmpty { break }
    }
    #expect(frozen.count == 1)
    #expect(inlineCounter.count == 1)
    #expect(waiting.count == 0)
    #expect(clock.pendingDeadlines.isEmpty)
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
