#if os(macOS)
import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
import FestivalAppSupport
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Fixtures

/// A session that never reaches the network.
@MainActor
private func offlineSession() -> FestivalSession {
    FestivalSession(factory: { throw FestivalAPIError.invalidResource })
}

private let splitBudget: Duration = .seconds(90)

// MARK: - Selected row

/// A row whose route is the current selection gets the selected treatment; others do not.
@MainActor
@Test func listDetailSelectableHighlightsOnlyTheSelectedRow() async throws {
    let size = CGSize(width: 320, height: 120)
    let selected = AppRoute.player(accountId: "a", displayName: "A")
    func render(selection: AppRoute?) async throws -> CGImage {
        let host = nativeHostedView(
            VStack(spacing: 0) {
                Text("Row A").frame(maxWidth: .infinity, minHeight: 60).listDetailSelectable(selected)
                Text("Row B").frame(maxWidth: .infinity, minHeight: 60)
                    .listDetailSelectable(.player(accountId: "b", displayName: "B"))
            }
            .background(Color.black)
            .environment(\.listDetailSelection, selection)
            .frame(width: size.width, height: size.height),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        return try await nativeHostedSettle(host, untilText: ["Row A", "Row B"])
    }
    let plain = try await render(selection: nil)
    let highlighted = try await render(selection: selected)
    #expect(nativeHostedSignature(plain) != nativeHostedSignature(highlighted))
    // Selecting a route no row shows leaves every row plain.
    let other = try await render(selection: .player(accountId: "z", displayName: nil))
    #expect(nativeHostedSignature(plain) == nativeHostedSignature(other))
}

// MARK: - One background per split

/// Owns whether the trailing probe page is shown, so it appears after the leading one.
private struct TwoPaneBackgroundHost: View {
    let session: FestivalSession
    @State private var showsTrailing = false

    var body: some View {
        HStack(spacing: 0) {
            VStack {
                Text("Leading Probe")
                BackdropProbe()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .festivalBackground(.carousel, session: session)
            .splitPaneContext(SplitPaneContext(role: .leading))
            if showsTrailing {
                VStack {
                    Text("Trailing Probe")
                    BackdropProbe()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .festivalBackground(.song("trailing-art.png"), session: session)
                .splitPaneContext(SplitPaneContext(role: .trailing))
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            showsTrailing = true
        }
    }
}

/// One background per split (operator 2026-10-05): pages in both panes draw no backdrop
/// of their own (the split container draws one), and a trailing page that appears after
/// its parent, asking for a different artwork, never takes the shared background over.
@MainActor
@Test func splitPanesShareTheParentsBackground() async throws {
    let size = CGSize(width: 800, height: 400)
    let session = offlineSession()
    let host = nativeHostedView(
        TwoPaneBackgroundHost(session: session)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    try await nativeHostedSettle(
        host, untilText: ["Leading Probe", "Trailing Probe", "Backdrop Shared"],
        excluding: ["Backdrop Own"], timeout: splitBudget
    )
    let coordinator = session.backgroundCoordinator
    #expect(coordinator.topToken != nil, "The parent page registers")
    #expect(coordinator.resolvedMode == .carousel, "The trailing page's artwork never wins")
}

/// Shows whether the page draws its own backdrop or the split container draws one.
private struct BackdropProbe: View {
    @Environment(\.splitSharesBackdrop) private var shared
    var body: some View { Text(shared ? "Backdrop Shared" : "Backdrop Own") }
}

#endif
