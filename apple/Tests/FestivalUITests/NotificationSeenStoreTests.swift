import Foundation
import Testing
@testable import FestivalUI

// MARK: - NotificationSeenStore

@Test func unmarkedGuidsAreUnread() throws {
    let suite = "fst.tests.notifications.\(UUID().uuidString)"
    let store = try #require(UserDefaults(suiteName: suite))
    defer { store.removePersistentDomain(forName: suite) }

    let unread = NotificationSeenStore.unreadIds(
        current: ["a", "b", "c"], accountId: "acc-1", defaults: store
    )
    #expect(unread == ["a", "b", "c"])
}

@Test func markSeenRemovesFromUnreadForThatAccountOnly() throws {
    let suite = "fst.tests.notifications.\(UUID().uuidString)"
    let store = try #require(UserDefaults(suiteName: suite))
    defer { store.removePersistentDomain(forName: suite) }

    NotificationSeenStore.markSeen(["a"], accountId: "acc-1", defaults: store)
    let unreadForAcc1 = NotificationSeenStore.unreadIds(
        current: ["a", "b"], accountId: "acc-1", defaults: store
    )
    #expect(unreadForAcc1 == ["b"])

    // A different account's seen state is independent.
    let unreadForAcc2 = NotificationSeenStore.unreadIds(
        current: ["a", "b"], accountId: "acc-2", defaults: store
    )
    #expect(unreadForAcc2 == ["a", "b"])
}

@Test func resetMakesEveryAccountsRowsUnreadAgain() throws {
    let suite = "fst.tests.notifications.\(UUID().uuidString)"
    let store = try #require(UserDefaults(suiteName: suite))
    defer { store.removePersistentDomain(forName: suite) }

    NotificationSeenStore.markSeen(["a", "b"], accountId: "acc-1", defaults: store)
    NotificationSeenStore.markSeen(["c"], accountId: "acc-2", defaults: store)
    NotificationSeenStore.reset(defaults: store)

    #expect(NotificationSeenStore.seenIds(accountId: "acc-1", defaults: store).isEmpty)
    #expect(NotificationSeenStore.unreadIds(
        current: ["c"], accountId: "acc-2", defaults: store
    ) == ["c"])
}

@Test func markSeenIsIdempotentAndCumulative() throws {
    let suite = "fst.tests.notifications.\(UUID().uuidString)"
    let store = try #require(UserDefaults(suiteName: suite))
    defer { store.removePersistentDomain(forName: suite) }

    NotificationSeenStore.markSeen(["a"], accountId: "acc-1", defaults: store)
    NotificationSeenStore.markSeen(["a", "b"], accountId: "acc-1", defaults: store)
    let unread = NotificationSeenStore.unreadIds(
        current: ["a", "b", "c"], accountId: "acc-1", defaults: store
    )
    #expect(unread == ["c"])
}
