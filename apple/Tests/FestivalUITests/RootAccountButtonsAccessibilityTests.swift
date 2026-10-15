#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Notifications bell and Profile accessibility (issue #394, for #14)
//
// #14 split the notifications bell and the profile avatar into two independent buttons
// (since #632 the iPhone shows them in one shared glass pill in the navigation bar, bell
// then Profile trailing-most; #300's tab-bar accessory bell is gone). These component
// tests pin what VoiceOver gets from each button: its own label, hint and state; the badge
// digit and the monogram initial are never read on their own; and the bell's hit region is
// at least 44 pt. They host the buttons side by side in the bar order
// (``RootChromeTrailingGroups``: bell, then Profile), with the iPhone pill's smaller
// monogram or the full-circle avatar of the Duo, iPad and iOS < 26 bars; the production
// order on iPhone is measured by `NavButtonHitRegionJourneyTests` (page-tools-and-nav-chrome
// R17). HIG VoiceOver:
// "Provide alternative labels for all key interface elements ... keep labels current as
// interface and content change"; HIG Buttons: "the hit region is at least 44x44 pt".

/// A notifications feed whose rows are new to the seen store, so they count as unread.
///
/// - Parameter count: Number of rows.
/// - Returns: The `/api/player/fixture-1/notifications` envelope.
private func unreadFeed(count: Int) -> Data {
    let items = (0..<count).map { index in
        """
        {"eventId":\(index + 1),"notificationGuid":"a11y-\(UUID().uuidString)","accountId":"fixture-1",
         "eventKind":"player_fc_achieved","songId":"fixture-song","instrument":"Solo_Bass",
         "detectedAt":"2024-01-04T00:00:00Z","expiresAt":"2024-02-04T00:00:00Z"}
        """
    }
    return Data("""
    {"generatedAt":"2024-01-05T00:00:00Z","expiresAfterHours":72,"sourceRunId":1,
     "sourceCompletedAt":"2024-01-05T00:00:00Z","notificationsGenerated":true,
     "items":[\(items.joined(separator: ","))]}
    """.utf8)
}

/// A session over the keyless fixture transport, with `fixture-1` selected or nobody.
///
/// - Parameters:
///   - unread: Notification rows to serve (all unread); ignored when anonymous.
///   - player: Whether `fixture-1` ("Fixture Player") is selected.
/// - Returns: The session, its notification feed already loaded when a player is selected.
@MainActor
private func accountSession(unread: Int, player: Bool = true) async throws -> FestivalSession {
    let transport = HostedHistoryTransport()
    await transport.setNotificationsBody(unreadFeed(count: unread))
    let client = try FestivalAPI(baseURL: URL(string: "http://localhost")!, transport: transport)
    let defaults = UserDefaults(suiteName: "fst.tests.account-buttons.\(UUID().uuidString)")!
    if player {
        defaults.set(
            Data(#"{"accountId":"fixture-1","displayName":"Fixture Player"}"#.utf8),
            forKey: SelectedPlayerIdentity.storageKey
        )
    }
    let session = FestivalSession(factory: { client }, selectionStorage: defaults)
    if player {
        await session.notificationsCenter.refresh(session: session)
        #expect(session.notificationsCenter.state == .loaded)
        #expect(session.notificationsCenter.unreadCount == unread)
    }
    return session
}

/// The account group as the navigation bar lists it, leading to trailing, from the
/// canonical ``RootChromeTrailingGroups`` order: the bell (a profile is selected), then
/// Profile. A component harness for the bar's items (see `NavButtonHitRegionJourneyTests`
/// for the iPhone bar itself).
private struct AccountGroup: View {
    let session: FestivalSession
    /// Draw Profile as in the iPhone account pill shared with the bell (issue #632).
    let pill: Bool

    var body: some View {
        let items = RootChromeTrailingGroups.resolve(
            pageActions: 0, showsQuickLinks: false, showsBell: session.selectedPlayer != nil,
            chrome: .tabBar
        ).last ?? []
        HStack(spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                switch item {
                case .bell:
                    NotificationsButton(session: session, open: {})
                case .profile:
                    RootProfileButton(session: session, inAccountPill: pill, action: {})
                case .pageAction, .quickLinks:
                    EmptyView()
                }
            }
        }
        .padding(16)
    }
}

/// Host the account group and return its settled accessibility tree and host.
@MainActor
private func accountTree(
    _ session: FestivalSession, pill: Bool, until texts: [String], name: String
) async throws -> (nodes: [MacAXNode], host: NSView, window: NSWindow) {
    let size = CGSize(width: 360, height: 120)
    let host = nativeHostedView(
        AccountGroup(session: session, pill: pill)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    try await nativeHostedSettle(host, untilText: texts)
    let nodes = macAccessibilityTree(host)
    macAccessibilityDump(nodes, name: name)
    return (nodes, host, window)
}

// MARK: - Labels, roles, state and reading order

/// With unread notifications the bell and the avatar are two buttons (bell → profile in the
/// bar order), the bell's label carrying the exact count and the avatar naming the
/// player, both in the iPhone account pill (issue #632) and as separate bar items.
@MainActor
@Test(arguments: [false, true])
func bellAndProfileReadAsTwoLabelledButtonsInOrder(pill: Bool) async throws {
    let session = try await accountSession(unread: 2)
    let (nodes, _, window) = try await accountTree(
        session, pill: pill,
        until: ["Notifications, 2 unread", "Profile: Fixture Player"],
        name: "account-unread-\(pill ? "pill" : "bar")"
    )
    defer { window.orderOut(nil) }
    let ids = ["fst.shell.notifications", "fst.shell.profile"]
    let buttons = nodes.filter { $0.isElement && ids.contains($0.identifier) }
    // One element each (never one shared capsule element), bell before profile.
    #expect(buttons.map(\.identifier) == ids, "\(nodes)")
    #expect(buttons.allSatisfy { $0.role == "AXButton" }, "\(buttons)")

    let bell = try #require(buttons.first)
    #expect(bell.label == "Notifications, 2 unread")
    // The label alone carries the count: no stale system-badge value.
    #expect(bell.value.isEmpty, "bell value '\(bell.value)'")

    let profile = try #require(buttons.last)
    #expect(profile.label == "Profile: Fixture Player")
    #expect(profile.help == RootProfileButton.accessibilityHint(hasPlayer: true))
    #expect(profile.help == "Opens your statistics")

    // The badge digit and the monogram initial are decoration, never read on their own.
    let spoken = nodes.filter(\.isElement).map(\.spokenName)
    #expect(!spoken.contains("2"), "badge digit read on its own: \(spoken)")
    #expect(!spoken.contains("F"), "monogram initial read on its own: \(spoken)")
    #expect(macAccessibilityFindings(nodes).isEmpty, "\(macAccessibilityFindings(nodes))")
}

/// With nothing unread the bell reads only "Notifications", no count or value.
@MainActor
@Test func bellWithoutUnreadReadsNotifications() async throws {
    let session = try await accountSession(unread: 0)
    let (nodes, _, window) = try await accountTree(
        session, pill: false, until: ["Notifications", "Profile: Fixture Player"],
        name: "account-read"
    )
    defer { window.orderOut(nil) }
    let bell = try #require(nodes.first { $0.isElement && $0.identifier == "fst.shell.notifications" })
    #expect(bell.role == "AXButton")
    #expect(bell.label == "Notifications")
    #expect(bell.value.isEmpty)
}

/// More unread rows than the badge shows ("9+") still read the exact count.
@MainActor
@Test func bellReadsExactCountAboveTheBadgeCap() async throws {
    let session = try await accountSession(unread: 12)
    let (nodes, _, window) = try await accountTree(
        session, pill: true, until: ["Notifications, 12 unread"], name: "account-capped"
    )
    defer { window.orderOut(nil) }
    let bell = try #require(nodes.first { $0.isElement && $0.identifier == "fst.shell.notifications" })
    #expect(bell.label == "Notifications, 12 unread")
    #expect(!nodes.filter(\.isElement).map(\.spokenName).contains("9+"))
}

/// Without a selected player there is no bell; the lone profile button reads
/// "Choose Profile" and says where it goes.
@MainActor
@Test func anonymousAccountGroupIsOnlyChooseProfile() async throws {
    let session = try await accountSession(unread: 0, player: false)
    let (nodes, _, window) = try await accountTree(
        session, pill: true, until: ["Choose Profile"], name: "account-anonymous"
    )
    defer { window.orderOut(nil) }
    #expect(!nodes.contains { $0.identifier == "fst.shell.notifications" })
    let profile = try #require(nodes.first { $0.isElement && $0.identifier == "fst.shell.profile" })
    #expect(profile.role == "AXButton")
    #expect(profile.label == "Choose Profile")
    #expect(profile.help == "Opens profile selection")
    #expect(macAccessibilityFindings(nodes).isEmpty, "\(macAccessibilityFindings(nodes))")
}

// MARK: - Target size

/// The bell in the account pill does not overlap the profile button trailing it, and the
/// pill's monogram is a bar glyph's size with no rim or overhang, so both sit inside one
/// glass pill as two separate targets (issue #632). The bar's 44 pt item regions on iPhone
/// are measured by `NavButtonHitRegionJourneyTests`.
@MainActor
@Test func pillBellAndProfileAreSeparateTargets() async throws {
    let session = try await accountSession(unread: 3)
    let (_, host, window) = try await accountTree(
        session, pill: true, until: ["Notifications, 3 unread", "Profile: Fixture Player"],
        name: "account-hit-region"
    )
    defer { window.orderOut(nil) }
    let bell = try #require(nativeHostedAccessibilityFrame("fst.shell.notifications", in: host))
    let profile = try #require(nativeHostedAccessibilityFrame("fst.shell.profile", in: host))
    #expect(RootProfileButton.MonogramMetrics.resolve(liquidGlassBar: true, inAccountPill: true).diameter
            == RootProfileButton.MonogramMetrics.pillDiameter)
    #expect(!RootProfileButton.MonogramMetrics.resolve(liquidGlassBar: true, inAccountPill: true).outlined)
    #expect(RootProfileButton.MonogramMetrics.resolve(liquidGlassBar: true, inAccountPill: true).overhang == 0)
    #expect(bell.maxX <= profile.minX, "bell \(bell) overlaps profile \(profile)")
}
#endif
