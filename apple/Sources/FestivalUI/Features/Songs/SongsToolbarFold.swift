import CoreGraphics
import SwiftUI

// MARK: - Sort and Filter overflow

/// When Songs folds Sort and Filter into one menu in the persistent top bar (issue #92).
///
/// The bar's trailing edge holds Sort, Filter, Quick Links, then Notifications and
/// Profile, beside the drawer button and the inline title. On a narrow iPhone (375 pt
/// and under), or at accessibility text sizes (the inline title and the
/// Large Content Viewer need the room), the five items no longer fit, so Sort and Filter
/// become one "Sort and Filter" menu. Quick Links, Notifications and Profile always stay
/// visible (HIG Toolbars, iOS: "Put only essential actions in the main area; use More for
/// the rest").
///
/// Only the horizontal tab-bar chrome folds by hand: the iPhone Duo vertical bar and the
/// iPad sidebar shell's navigation bars overflow into the system "…" menu themselves
/// (HIG Designing for iPhone Duo: "Set visibility priority by group"; issue #92 guidance:
/// "on iPadOS avoid hand-rolled overflow where the system provides it").
enum SongsToolbarFold {
    /// Narrowest page width that keeps all five trailing items: wide enough for the
    /// standard 6.3" iPhones (393–402 pt), narrower than which (the 375 pt iPhones) the
    /// inline title and drawer button no longer fit beside them.
    static let minimumUnfoldedWidth: CGFloat = 390

    /// Whether Sort and Filter fold into one menu.
    ///
    /// - Parameters:
    ///   - width: The page's width in points; zero (not yet measured) never folds.
    ///   - dynamicTypeSize: Current text size; accessibility sizes always fold.
    ///   - chrome: Current section chrome; only ``DeviceLayout/SectionChrome/tabBar`` folds.
    /// - Returns: True to show one "Sort and Filter" menu instead of two buttons.
    static func folds(
        width: CGFloat, dynamicTypeSize: DynamicTypeSize, chrome: DeviceLayout.SectionChrome
    ) -> Bool {
        guard chrome == .tabBar else { return false }
        if dynamicTypeSize.isAccessibilitySize { return true }
        return width > 0 && width < minimumUnfoldedWidth
    }
}
