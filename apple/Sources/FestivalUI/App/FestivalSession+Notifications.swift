import Foundation
import FestivalCore
import Observation

// MARK: - Notifications center

/// Load state for the notifications sheet, mirroring the web's `NotificationFeedStatus`.
enum NotificationsLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(ServiceIssue)
}

/// Per-session notification feed: fetch, seen-state and unread count.
///
/// Stored outside `FestivalSession` (see `backgroundCoordinator` in
/// `FestivalSession+Artwork.swift` for the same pattern) so this lane owns it
/// without editing the session's main file.
@MainActor
@Observable
final class NotificationsCenter {
    private(set) var notifications: [AppNotification] = []
    private(set) var isGenerated = true
    private(set) var state: NotificationsLoadState = .idle
    private(set) var unreadIds: Set<String> = []
    private var accountId: String?

    /// Unread rows, newest first, for the badge count and "New" section.
    var unreadCount: Int { unreadIds.count }

    /// Reload the feed for the given account, replacing any previous account's rows.
    ///
    /// Rows already loaded for the same account stay visible while the feed
    /// revalidates (the bell refreshes on selection and the sheet again on open), so
    /// reopening the sheet, or a cancelled revalidation, never regresses to a spinner.
    /// A different account clears the previous rows before loading.
    ///
    /// - Parameter session: Shared app session (provides the client and player).
    func refresh(session: FestivalSession) async {
        guard let identity = session.selectedPlayer else {
            accountId = nil
            notifications = []
            unreadIds = []
            state = .idle
            return
        }
        let revalidating = accountId == identity.accountId && state == .loaded
        accountId = identity.accountId
        if !revalidating {
            notifications = []
            unreadIds = []
            state = .loading
        }
        do {
            let payload = try await session.client().playerNotifications(
                accountId: identity.accountId
            )
            try await session.observe(publicationId: payload.observedPublicationId)
            let catalogSongs = (try? await session.catalog())?.catalog.songs ?? []
            let songTitles = Dictionary(
                catalogSongs.map { ($0.songId, $0.title) }, uniquingKeysWith: { a, _ in a }
            )
            notifications = payload.envelope.items.map {
                NotificationText.format($0, songTitle: $0.songId.flatMap { songTitles[$0] })
            }
            isGenerated = payload.envelope.isGenerated
            unreadIds = NotificationSeenStore.unreadIds(
                current: notifications.map(\.id), accountId: identity.accountId
            )
            state = .loaded
        } catch is CancellationError {
        } catch {
            state = .failed(ServiceIssue(error))
        }
    }

    /// Persist rows as seen and drop them from the unread badge.
    ///
    /// - Parameter ids: Notification GUIDs the sheet reported as visible/read.
    func markSeen(_ ids: some Sequence<String>) {
        guard let accountId else { return }
        NotificationSeenStore.markSeen(ids, accountId: accountId)
        unreadIds.subtract(ids)
    }
}

extension FestivalSession {
    /// Weakly keyed store so each session owns exactly one notifications center.
    @MainActor
    private enum NotificationsRegistry {
        struct Entry {
            weak var session: FestivalSession?
            let center: NotificationsCenter
        }

        static var entries: [ObjectIdentifier: Entry] = [:]
    }

    /// The single notifications center shared by every page of this session.
    var notificationsCenter: NotificationsCenter {
        let key = ObjectIdentifier(self)
        if let entry = NotificationsRegistry.entries[key], entry.session === self {
            return entry.center
        }
        NotificationsRegistry.entries = NotificationsRegistry.entries.filter {
            $0.value.session != nil
        }
        let created = NotificationsCenter()
        NotificationsRegistry.entries[key] = .init(session: self, center: created)
        return created
    }

    /// Resolve a catalog `Song` for a notification's `songId`, for navigation.
    ///
    /// - Parameter songId: Identifier from a tapped notification.
    /// - Returns: The matching song, or nil if it is no longer in the catalogue.
    /// - Throws: Client configuration, transport, decoding or publication failures.
    func song(songId: String) async throws -> Song? {
        let payload = try await catalog()
        return payload.catalog.songs.first { $0.songId == songId }
    }
}

// MARK: - Seen-state persistence

/// Per-account "seen" notification GUIDs, ported from `notificationSeenState.ts`
/// (simplified: no cross-feed staleness pruning, since this app only ever tracks
/// one profile's own feed at a time).
enum NotificationSeenStore {
    private static let storageKey = "fst.notifications.seen"
    private static let maxStoredIds = 200

    /// Read seen GUIDs for one account.
    ///
    /// - Parameters:
    ///   - accountId: Selected player.
    ///   - defaults: Backing store; a test-isolated suite in unit tests.
    /// - Returns: Persisted seen GUIDs, or empty when never recorded.
    static func seenIds(accountId: String, defaults: UserDefaults = .standard) -> Set<String> {
        guard let store = defaults.dictionary(forKey: storageKey) as? [String: [String]],
              let ids = store[accountId] else {
            return []
        }
        return Set(ids)
    }

    /// Notification GUIDs not yet marked seen for this account.
    ///
    /// - Parameters:
    ///   - current: GUIDs currently in the loaded feed.
    ///   - accountId: Selected player.
    ///   - defaults: Backing store; a test-isolated suite in unit tests.
    /// - Returns: The subset of `current` absent from the seen store.
    static func unreadIds(
        current: [String], accountId: String, defaults: UserDefaults = .standard
    ) -> Set<String> {
        let seen = seenIds(accountId: accountId, defaults: defaults)
        return Set(current.filter { !seen.contains($0) })
    }

    /// Merge newly seen GUIDs into the persisted, size-bounded store.
    ///
    /// - Parameters:
    ///   - ids: GUIDs to mark seen.
    ///   - accountId: Selected player.
    ///   - defaults: Backing store; a test-isolated suite in unit tests.
    static func markSeen(
        _ ids: some Sequence<String>, accountId: String, defaults: UserDefaults = .standard
    ) {
        var store = (defaults.dictionary(forKey: storageKey) as? [String: [String]]) ?? [:]
        var current = Set(store[accountId] ?? [])
        current.formUnion(ids)
        store[accountId] = Array(current.suffix(maxStoredIds))
        defaults.set(store, forKey: storageKey)
    }
}
