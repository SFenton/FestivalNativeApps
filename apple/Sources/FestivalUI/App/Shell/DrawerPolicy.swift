import SwiftUI
import FestivalAppSupport
import FestivalCore

// MARK: - Drawer destinations

/// Everything the drawer can ask the shell to do. The root owns tab selection,
/// paths and sheets, so the drawer only emits intents.
enum DrawerIntent: Equatable {
    /// Push a route onto the currently selected tab's stack.
    case push(AppRoute)
    /// Switch to a root section (popping it to its root).
    case select(FestivalSection)
    /// Present profile search/switching.
    case chooseProfile
    /// Deselect the current profile (already confirmed by the user).
    case deselectProfile
    /// Show global search (the iPad flyout's Search row).
    case openSearch
}

/// One drawer navigation row.
struct DrawerItem: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let intent: DrawerIntent
}

/// Pure drawer contents, ported from the web `Sidebar` (`components/shell/desktop/Sidebar.tsx`).
enum DrawerMenu {
    /// The navigation list, in web `Sidebar` order: Songs, Suggestions*, Statistics*,
    /// Rivals*, Leaderboards, Item Shop (*with a selected player). Bands and Licenses
    /// are not listed (operator, 2026-09-28): Bands open from search and leaderboard
    /// links, Licenses from Settings.
    ///
    /// A destination that is a visible tab switches to it; otherwise it is pushed on the
    /// current stack. Item Shop honours Settings › Hide Item Shop; it is pushed, except in
    /// the iPad flyout, where it is a destination of its own.
    ///
    /// - Parameters:
    ///   - profile: Selected profile kind.
    ///   - visibleSections: Sections currently shown as tabs.
    ///   - hideShop: Persisted `fst.settings.hideShop` preference.
    /// - Returns: Ordered drawer rows.
    static func browse(
        profile: FestivalProfileKind, visibleSections: [FestivalSection], hideShop: Bool
    ) -> [DrawerItem] {
        func destination(_ section: FestivalSection, route: AppRoute?) -> DrawerItem {
            let intent: DrawerIntent = if let route, !visibleSections.contains(section) {
                .push(route)
            } else {
                .select(section)
            }
            return DrawerItem(
                id: section.rawValue, title: section.title, symbol: section.symbol, intent: intent
            )
        }
        var items = [destination(.songs, route: nil)]
        if profile != .none {
            items.append(destination(.suggestions, route: .suggestions))
            items.append(destination(.statistics, route: .statistics))
        }
        if profile == .player {
            items.append(destination(.rivals, route: .rivals))
        }
        items.append(destination(.leaderboards, route: .leaderboards))
        if !hideShop {
            items.append(DrawerItem(
                id: "shop", title: "Item Shop", symbol: "bag",
                intent: visibleSections.contains(.shop) ? .select(.shop) : .push(.shop)
            ))
        }
        return items
    }

    /// The iPad flyout's Search row, above the destinations (it replaces the persistent
    /// sidebar's Search row; HIG Search fields: "keep search available across sections").
    static let search = DrawerItem(id: "search", title: "Search", symbol: "magnifyingglass", intent: .openSearch)

    /// Rows pinned at the bottom of the drawer after the profile row (web sidebar footer).
    static let more: [DrawerItem] = [
        DrawerItem(id: "settings", title: "Settings", symbol: "gearshape", intent: .select(.settings)),
    ]

    /// VoiceOver label for the footer's selected-player row.
    ///
    /// The row shows only the name (like every other drawer row), so the "Selected
    /// Player" role is spoken rather than drawn.
    ///
    /// - Parameter displayName: Selected player's display name.
    /// - Returns: The name followed by the row's role.
    static func selectedPlayerAccessibilityLabel(_ displayName: String) -> String {
        "\(displayName), Selected Player"
    }

    /// Whether a row names the page on screen, for the current-destination highlight.
    ///
    /// - Parameters:
    ///   - item: Drawer row.
    ///   - selected: Selected root section.
    ///   - topRoute: Route on top of the selected section's stack, if any.
    /// - Returns: True for the section root being shown, or the pushed page it opens.
    static func isCurrent(_ item: DrawerItem, selected: FestivalSection, topRoute: AppRoute?) -> Bool {
        switch item.intent {
        case let .select(section): section == selected && topRoute == nil
        case let .push(route): route == topRoute
        case .chooseProfile, .deselectProfile, .openSearch: false
        }
    }
}

// MARK: - Drawer placement

/// Pure geometry of the floating drawer panel for one window.
///
/// An ordinary phone (``DeviceLayout/Pose/standard``) keeps the original iPhone
/// placement exactly: an 8 pt margin all round, and content padded below the status bar
/// and above the home indicator. iPhone Duo uses the same rule for the top and bottom
/// edges (the panel runs the window's height; its rows clear the status bar and home
/// indicator), and additionally starts the panel after a leading vertical bar and clear
/// of the camera occlusion (``DeviceLayout/cutoutInsets``), so it never covers either in
/// any rotation (`.agents/design/apple/duo.md`, B5). The scrim always covers the whole
/// window, the vertical bar included (#339).
struct DrawerPlacement: Equatable {
    /// Gap between the floating panel and the window (or reserved-region) edges.
    static let margin: CGFloat = 8
    /// Widest panel, in points.
    static let maximumWidth: CGFloat = 340
    /// Share of the available width the panel may take.
    static let widthFraction: CGFloat = 0.84

    /// Panel width.
    let width: CGFloat
    /// Padding from the window edges to the panel's glass shape (leading/top/bottom used).
    let panelPadding: EdgeInsets
    /// Content padding above the first row, inside the panel.
    let contentTop: CGFloat
    /// Content padding below the last row, inside the panel.
    let contentBottom: CGFloat

    /// Resolve the placement.
    ///
    /// - Parameters:
    ///   - size: The drawer `GeometryReader`'s size, i.e. the window inside its safe area.
    ///   - safeArea: Window safe-area insets.
    ///   - layout: Published device layout.
    /// - Returns: Panel and scrim geometry.
    static func resolve(size: CGSize, safeArea: EdgeInsets, layout: DeviceLayout) -> DrawerPlacement {
        guard layout.pose != .standard else {
            return DrawerPlacement(
                width: min(maximumWidth, size.width * widthFraction),
                panelPadding: EdgeInsets(top: margin, leading: margin, bottom: margin, trailing: margin),
                contentTop: max(16, safeArea.top - margin + 4),
                contentBottom: max(16, safeArea.bottom)
            )
        }
        // Never less than the drawer's own safe area, whatever the probe reported.
        let overlay = layout.overlayInsets
        let reserved = EdgeInsets(
            top: max(overlay.top, safeArea.top), leading: max(overlay.leading, safeArea.leading),
            bottom: max(overlay.bottom, safeArea.bottom), trailing: max(overlay.trailing, safeArea.trailing)
        )
        // Top and bottom: like iPhone, the status bar and home indicator only pad the rows;
        // a camera occlusion beyond them still moves the panel (#339).
        let top = margin + max(0, reserved.top - safeArea.top)
        let bottom = margin + max(0, reserved.bottom - safeArea.bottom)
        let windowWidth = size.width + safeArea.leading + safeArea.trailing
        let available = max(0, windowWidth - reserved.leading - reserved.trailing)
        return DrawerPlacement(
            width: min(maximumWidth, available * widthFraction),
            panelPadding: EdgeInsets(
                top: top, leading: margin + reserved.leading, bottom: bottom, trailing: margin
            ),
            contentTop: max(16, safeArea.top - top + 4),
            contentBottom: max(16, safeArea.bottom - (bottom - margin))
        )
    }

    /// The panel's frame in window coordinates (leading-edge x), before any drag.
    ///
    /// - Parameter size: Full window size.
    /// - Returns: Where the glass panel is drawn.
    func panelFrame(in size: CGSize) -> CGRect {
        CGRect(
            x: panelPadding.leading, y: panelPadding.top, width: width,
            height: max(0, size.height - panelPadding.top - panelPadding.bottom)
        )
    }

    /// Padding that places the scrim's cut-out over the panel, in the scrim's (the full
    /// window's) coordinates.
    ///
    /// The cut-out is laid out at the panel's real window position (rather than offset
    /// there), which keeps any position-dependent (concentric) corners identical to the
    /// panel's.
    var cutoutPadding: EdgeInsets {
        EdgeInsets(
            top: panelPadding.top,
            leading: panelPadding.leading,
            bottom: panelPadding.bottom,
            // The cut-out is leading-aligned at a fixed width, so its trailing edge is free.
            trailing: 0
        )
    }
}

// MARK: - Drawer motion

/// Open and close choreography of the drawer and flyout (#362, owner-approved variant of
/// `page-tools-and-nav-chrome` R16).
///
/// One presence value runs from 0 (closed) to 1 (open). Its first share fades the
/// whole-window scrim in place; the rest slides the panel in. Closing runs the same
/// value back, so the panel slides out first and the scrim then fades. With Reduce
/// Motion the panel fades in place instead of sliding (HIG Accessibility: "replacing
/// axis transitions with fades").
struct DrawerMotion: Equatable {
    /// Scrim fade, in seconds.
    static let scrimDuration: Double = 0.15
    /// Panel slide, in seconds (web `Sidebar` `SIDEBAR_DURATION`, 250 ms).
    static let panelDuration: Double = 0.25
    /// Whole open or close sequence, in seconds.
    static var totalDuration: Double { scrimDuration + panelDuration }
    /// Share of the presence the scrim fade takes.
    static var scrimShare: Double { scrimDuration / totalDuration }
    /// Scrim opacity when the drawer is fully open.
    static let scrimOpacity: Double = 0.45
    /// Extra travel past the panel's trailing edge so its shadow leaves the window too.
    static let shadowClearance: CGFloat = 24

    /// Drives ``presence`` for an open or close; linear because ``scrim`` and ``panel``
    /// carry each stage's own easing.
    static var animation: Animation { .linear(duration: totalDuration * timeScale) }

    /// Slow-motion factor for the whole sequence: 1 in Release.
    ///
    /// Debug builds read `FST_DEBUG_DRAWER_SLOWMO=<factor>` (at least 1) so the rendered
    /// UI journey `DrawerMotionJourneyTests` can sample each stage in screenshots.
    static let timeScale: Double = {
        #if DEBUG
        let raw = ProcessInfo.processInfo.environment["FST_DEBUG_DRAWER_SLOWMO"]
        return debugTimeScale(raw)
        #else
        return 1
        #endif
    }()

    /// Parse a slow-motion factor.
    ///
    /// - Parameter raw: The `FST_DEBUG_DRAWER_SLOWMO` value, if any.
    /// - Returns: The factor clamped to 1…60; 1 when missing or not a number.
    static func debugTimeScale(_ raw: String?) -> Double {
        guard let value = raw.flatMap(Double.init), value.isFinite else { return 1 }
        return max(1, min(60, value))
    }

    /// 0 when closed, 1 when open.
    var presence: Double = 1
    /// Whether the panel slides in (false: it fades in place for Reduce Motion).
    var slides = true

    /// Scrim stage, 0…1 (ease in-out), complete before the panel starts moving.
    var scrim: Double {
        let t = Self.clamp(presence / Self.scrimShare)
        return t * t * (3 - 2 * t)
    }

    /// Panel stage, 0…1 (ease-out cubic on opening, so ease-in on closing).
    var panel: Double {
        let t = Self.clamp((presence - Self.scrimShare) / (1 - Self.scrimShare))
        return 1 - pow(1 - t, 3)
    }

    /// Horizontal panel offset before any drag.
    ///
    /// - Parameter hiddenDistance: How far left the panel must travel to leave the window.
    /// - Returns: 0 when open, `-hiddenDistance` when closed; always 0 with Reduce Motion.
    func panelOffset(hiddenDistance: CGFloat) -> CGFloat {
        slides ? -CGFloat(1 - panel) * hiddenDistance : 0
    }

    /// Panel opacity: 1 while sliding, the panel stage when fading.
    var panelOpacity: Double { slides ? 1 : panel }

    /// Clamp to 0…1.
    ///
    /// - Parameter value: Any fraction.
    /// - Returns: The fraction limited to 0…1.
    private static func clamp(_ value: Double) -> Double { max(0, min(1, value)) }
}

// MARK: - Drawer corners

/// Corner geometry of the floating drawer panel.
///
/// iOS/macOS 26+ resolve every panel corner with `ConcentricRectangle` against the
/// window's container shape, which the system derives from the display's own corners:
/// each iPhone model, each iPhone Duo display, and the Duo's hinge-side versus outer
/// corners as it rotates. A corner nested in a display corner gets that radius minus its
/// inset; a corner that is not (beside the Duo's vertical bar or below its status bar),
/// or whose display corner is too tight, gets ``minimumRadius``. Only public API is used;
/// the display corner radius itself is never read (`_displayCornerRadius` is private).
enum DrawerCorners {
    /// Horizontal padding between the panel edge and its rows.
    static let contentInset: CGFloat = 12
    /// Corner radius of a row's current-page and pressed highlight.
    static let rowRadius: CGFloat = 14
    /// Smallest panel radius: concentric with the rows inside it (row radius plus the
    /// inset), so the panel still nests its own content where no display corner applies.
    static let minimumRadius: CGFloat = rowRadius + contentInset
    /// Fixed radius before iOS 26, which has no public container-concentric shape. It
    /// approximates an iPhone display corner at the 8 pt margin.
    static let legacyRadius: CGFloat = 44

}

// MARK: - Edge swipe

/// Opens the iPad / iPhone Duo flyout with a swipe in from the leading edge, like the
/// iPhone drawer it matches (`.agents/design/apple/split-view.md`). Enabled only at a
/// section root, where the system's own edge swipe (Back) has nothing to pop.
enum FlyoutEdgeSwipe {
    /// How far from the leading edge a swipe must start.
    static let edgeWidth: CGFloat = 24
    /// How far it must travel towards the trailing edge.
    static let minimumTravel: CGFloat = 60

    /// Whether a drag is a leading-edge swipe that opens the flyout.
    ///
    /// - Parameters:
    ///   - start: The drag's start x from the leading edge.
    ///   - translation: Its translation (positive = towards the trailing edge).
    /// - Returns: True when it started at the edge and travelled mostly sideways.
    static func opens(startFromLeading start: CGFloat, translation: CGSize) -> Bool {
        start <= edgeWidth && translation.width >= minimumTravel
            && abs(translation.height) < translation.width
    }
}

/// Drawer row icon geometry, scaled with body text by UIKit.
enum DrawerRowMetrics {
    /// Width of the leading symbol column at the default text size.
    static let iconWidth: CGFloat = 26
    /// Gap between the leading symbol column and the title.
    static let iconSpacing: CGFloat = 14
}
