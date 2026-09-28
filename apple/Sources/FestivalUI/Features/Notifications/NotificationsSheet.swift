import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - NotificationsSheet

/// Native port of the web's `MobileNotificationsModal`
/// (`FortniteFestivalWeb/src/components/notifications/MobileNotificationsModal.tsx`).
///
/// Owns a small internal `NavigationStack` so rows can push straight to Song Detail
/// or Full Rankings without the sheet needing access to the presenting tab's own
/// navigation path. Band grouping, multi-event coalescing and the media-cycle
/// animation are not ported natively this wave — see
/// `.agents/controls/notifications/spec.md`.
struct NotificationsSheet: View {
    let session: FestivalSession
    @State private var path: [AppRoute] = []
    @Environment(\.dismiss) private var dismiss
    private var center: NotificationsCenter { session.notificationsCenter }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationDestination(for: AppRoute.self) { route in
                    AppRouteDestination(
                        route: route, session: session,
                        visibleInstruments: Set(Instrument.allCases), path: $path, isVisible: true
                    )
                }
                .navigationTitle("Notifications")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    // Dismiss-only modal: Done belongs on the trailing side (HIG), not
                    // leading like a Cancel action (operator, 2026-09-28).
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .task { await center.refresh(session: session) }
        .onDisappear {
            center.markSeen(center.notifications.map(\.id))
        }
    }

    @ViewBuilder private var content: some View {
        switch (session.selectedPlayer, center.state) {
        case (nil, _):
            ContentUnavailableView(
                "Choose a Profile", systemImage: "person.crop.circle",
                description: Text("Select a profile to see your notifications.")
            )
        case (_, .loading), (_, .idle):
            FestivalLoadingView(accessibilityLabel: "Loading Notifications")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let (_, .failed(issue)):
            ServiceStatusView(issue, title: "Notifications unavailable") {
                Task { await center.refresh(session: session) }
            }
        case (_, .loaded):
            if center.notifications.isEmpty {
                NotificationsEmptyState(isGenerated: center.isGenerated)
            } else {
                list
            }
        }
    }

    private var list: some View {
        List {
            let unread = center.notifications.filter { center.unreadIds.contains($0.id) }
            let older = center.notifications.filter { !center.unreadIds.contains($0.id) }
            if !unread.isEmpty {
                Section("New") { rows(unread) }
            }
            if !older.isEmpty || unread.isEmpty {
                Section(unread.isEmpty ? "" : "Older") { rows(older) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func rows(_ notifications: [AppNotification]) -> some View {
        ForEach(notifications) { notification in
            Button {
                Task { await open(notification) }
            } label: {
                NotificationRow(
                    notification: notification, isUnread: center.unreadIds.contains(notification.id)
                )
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .accessibilityIdentifier("fst.notifications.row.\(notification.id)")
        }
    }

    /// Resolve the tapped row's destination and push it inside the sheet's own stack.
    ///
    /// - Parameter notification: Row that was tapped.
    private func open(_ notification: AppNotification) async {
        center.markSeen([notification.id])
        guard let destination = notification.destination else { return }
        switch destination {
        case let .song(songId, _):
            guard let song = try? await session.song(songId: songId) else { return }
            path.append(.songDetail(song))
        case let .rankings(instrument, metric):
            if let instrument {
                path.append(.fullRankings(instrument: instrument, rankBy: metric.rawValue))
            } else {
                path.append(.leaderboards)
            }
        }
    }
}

// MARK: - Empty state

/// Matches `notifications.empty.*` copy from the web's `en.json`.
struct NotificationsEmptyState: View {
    let isGenerated: Bool

    var body: some View {
        ContentUnavailableView(
            "No notifications available", systemImage: "bell.slash",
            description: Text(isGenerated
                ? "Notifications will appear here when new high scores are set or "
                    + "global ranks improve. Set new high scores and compete with friends to see them!"
                : "Notifications may appear here after the next leaderboard update. Set new "
                    + "high scores and compete with friends to see them!")
        )
        .accessibilityIdentifier("fst.notifications.empty")
    }
}

// MARK: - Row

/// One notification row: badge flag, title, summary text and unread dot.
struct NotificationRow: View {
    let notification: AppNotification
    let isUnread: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let instrument = notification.instrument {
                InstrumentIcon(instrument, size: 32)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "bell.badge")
                    .font(.title3)
                    .foregroundStyle(BrandTokens.accentBlue)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(notification.title)
                    .font(.headline)
                    .foregroundStyle(BrandTokens.textPrimary)
                    .lineLimit(1)
                Text(notification.summary)
                    .font(.subheadline)
                    .foregroundStyle(BrandTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let badge = notification.badge {
                    Text(badge.uppercased())
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(BrandTokens.accentPurple, in: Capsule())
                        .foregroundStyle(BrandTokens.textPrimary)
                }
            }
            Spacer(minLength: 0)
            if isUnread {
                Circle()
                    .fill(BrandTokens.gold)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
            if notification.destination != nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(BrandTokens.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(notification.destination != nil ? .isButton : [])
    }
}
