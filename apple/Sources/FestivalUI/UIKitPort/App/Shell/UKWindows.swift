#if os(iOS)
import FestivalCore
import UIKit

// MARK: - Windows

/// iPad "Open in New Window": the UIKit counterpart of ``FestivalWindowRoute``'s
/// `openWindow(value:)`. The route travels in an `NSUserActivity`, so it survives window
/// restoration; every window shares the process's one ``FestivalSession``
/// (``FestivalLaunch``) and keeps its own navigation.
@MainActor
enum UKWindows {
    /// The activity type of a content window.
    static let activityType = "com.festival.window-route"

    /// Whether this device can open another window (iPad).
    static var canOpenWindows: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && UIApplication.shared.supportsMultipleScenes
    }

    /// The activity that opens a window on a route.
    ///
    /// - Parameter route: The content to show.
    /// - Returns: The activity.
    static func activity(for route: FestivalWindowRoute) -> NSUserActivity {
        let activity = NSUserActivity(activityType: activityType)
        if let data = try? JSONEncoder().encode(route) { activity.userInfo = ["route": data] }
        activity.title = "Festival Score Tracker"
        return activity
    }

    /// The route an activity carries.
    ///
    /// - Parameter activity: The activity a scene connected with.
    /// - Returns: The route, or nil for a plain window.
    static func route(from activity: NSUserActivity?) -> FestivalWindowRoute? {
        guard let activity, activity.activityType == activityType,
              let data = activity.userInfo?["route"] as? Data else { return nil }
        return try? JSONDecoder().decode(FestivalWindowRoute.self, from: data)
    }

    /// Asks the system for a new window showing a route.
    ///
    /// - Parameter route: The content to show.
    static func open(_ route: FestivalWindowRoute) {
        UIApplication.shared.requestSceneSessionActivation(nil, userActivity: activity(for: route), options: nil)
    }

    /// The context-menu action for a row (iPad only; nil on iPhone so rows keep their plain
    /// tap behaviour): "Open in New Window", or "Open “Title” in New Window" for a row that
    /// shows several items.
    ///
    /// - Parameters:
    ///   - route: The content the new window shows.
    ///   - title: The item's title for a multi-item row.
    /// - Returns: The action, or nil where windows are unavailable.
    static func menuAction(for route: FestivalWindowRoute, title: String? = nil) -> UIAction? {
        guard canOpenWindows else { return nil }
        return UIAction(
            title: title.map { "Open “\($0)” in New Window" } ?? "Open in New Window",
            image: UIImage(systemName: "macwindow.badge.plus")
        ) { _ in open(route) }
    }
}
#endif
