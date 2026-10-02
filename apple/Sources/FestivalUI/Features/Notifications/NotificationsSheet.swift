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
    /// The first reveal's stagger has finished; rows rebuilt later (List recycling while
    /// scrolling back up) appear without fading again (operator batch 7).
    @State private var fadeSettled = false
    private var center: NotificationsCenter { session.notificationsCenter }

    var body: some View {
        FestivalModal("Notifications", closeIdentifier: "fst.notifications.close", path: $path) {
            content
                .navigationDestination(for: AppRoute.self) { route in
                    AppRouteDestination(
                        route: route, session: session,
                        visibleInstruments: Set(Instrument.allCases), path: $path, isVisible: true
                    )
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
                Section { rows(unread) } header: { sectionHeader("New") }
            }
            if !older.isEmpty || unread.isEmpty {
                Section { rows(older, offset: unread.count) } header: {
                    if !unread.isEmpty { sectionHeader("Older") }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .task(id: center.notifications.count) {
            await FadeStagger.settle(afterRevealing: min(center.notifications.count, 12)) {
                fadeSettled = true
            }
        }
    }

    /// White section title ("New" / "Older", operator batch 7).
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(FestivalText.primary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func rows(_ notifications: [AppNotification], offset: Int = 0) -> some View {
        ForEach(Array(notifications.enumerated()), id: \.element.id) { index, notification in
            Button {
                Task { await open(notification) }
            } label: {
                NotificationRow(
                    notification: notification, isUnread: center.unreadIds.contains(notification.id)
                )
            }
            .buttonStyle(.plain)
            .festivalFadeIn(isLoaded: true, index: FadeStagger.index(offset + index, settled: fadeSettled))
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
    /// Web `UNREAD_DOT_COLOR` (#FACC15).
    static let unreadDot = Color(.sRGB, red: 250 / 255, green: 204 / 255, blue: 21 / 255)

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
                MarqueeText(notification.title)
                    .font(.headline)
                    .foregroundStyle(BrandTokens.textPrimary)
                    .lineLimit(1)
                Text(notification.summary)
                    .font(.subheadline)
                    .foregroundStyle(FestivalText.primary)
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
            // Web trailing column: 20pt wide, the chevron centred vertically and the
            // unread dot centred 24pt above it (`trailingAction` / `unreadDot`).
            if isUnread || notification.destination != nil {
                ZStack {
                    if notification.destination != nil {
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(FestivalText.primary.opacity(0.72))
                    }
                    if isUnread {
                        Circle()
                            .fill(Self.unreadDot)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(BrandTokens.surfaceSubtle, lineWidth: 2))
                            .offset(y: -24)
                    }
                }
                .frame(width: 20)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(notification.destination != nil ? .isButton : [])
    }
}
