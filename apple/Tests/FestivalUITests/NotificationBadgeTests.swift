import Testing
@testable import FestivalUI

// MARK: - NotificationBadge

@Test func noUnreadShowsNoBadge() {
    #expect(NotificationBadge.text(unreadCount: 0) == nil)
    #expect(NotificationBadge.text(unreadCount: -1) == nil)
}

@Test(arguments: 1...9)
func smallCountsShowVerbatim(count: Int) {
    #expect(NotificationBadge.text(unreadCount: count) == String(count))
}

@Test(arguments: [10, 42, 200])
func countsAboveNineCapLikeWeb(count: Int) {
    #expect(NotificationBadge.text(unreadCount: count) == "9+")
}

@Test func accessibilityLabelCarriesExactCount() {
    #expect(NotificationBadge.accessibilityLabel(unreadCount: 0) == "Notifications")
    #expect(NotificationBadge.accessibilityLabel(unreadCount: 2) == "Notifications, 2 unread")
    #expect(NotificationBadge.accessibilityLabel(unreadCount: 14) == "Notifications, 14 unread")
}
