import SwiftUI

// MARK: - Page tools hand-off

/// How a page's tools move between the iPhone floating dock and the navigation bar while
/// the page scrolls (issue #13; iOS 17–26.0 only since issue #42 moved them into the
/// tab-bar accessory on 26.1+).
///
/// The dock buttons leave and the matching toolbar items arrive in one animation, so the
/// tools read as moving into the bar's button row rather than vanishing and popping in.
/// Under Reduce Motion the hand-off is a plain cross-fade: HIG Accessibility asks to
/// "reduce automatic and repetitive animation, including zooming, scaling, and peripheral
/// motion", "replacing axis transitions with fades".
///
/// Design rules: `.agents/design/apple/nav-accessories.md`.
enum PageToolsHandOff {
    /// The animation family for one hand-off.
    enum Style: Equatable {
        /// Dock buttons shrink toward their corner as they fade; bar items morph in.
        case motion
        /// Opacity only (Reduce Motion).
        case crossFade
    }

    /// Choose the hand-off style.
    ///
    /// - Parameters:
    ///   - systemReduceMotion: The system Reduce Motion setting.
    ///   - appReduceMotion: The app's own Reduce Motion setting (`fst.accessibility.reduceMotion`).
    /// - Returns: ``Style/crossFade`` when either setting is on.
    static func style(systemReduceMotion: Bool, appReduceMotion: Bool) -> Style {
        systemReduceMotion || appReduceMotion ? .crossFade : .motion
    }

    /// Whether the page's tools belong in the navigation bar.
    ///
    /// Only the floating dock (iOS 17–26.0 iPhone) hands tools off. In the iOS 26.1+
    /// tab-bar accessory they stay at the bottom and move inline beside the minimized
    /// tab bar instead (issue #42); elsewhere (Duo rail, iPad, Mac) they are always
    /// toolbar items. Every viewer gets the hand-off: anonymous Songs has Sort (and
    /// Quick Links on grouped sorts) to anchor as much as a selected profile does.
    ///
    /// - Parameters:
    ///   - scrolled: The page's list has scrolled away from its top (``ScrollAwayGate``).
    ///   - presentation: Where the page's tools sit above the tab bar; nil for toolbar items.
    /// - Returns: True when the tools should sit in the navigation bar.
    static func toolsInBar(scrolled: Bool, presentation: PageToolsPresentation?) -> Bool {
        scrolled && presentation == .floating
    }

    /// The shared timing for the dock and toolbar halves of one hand-off.
    ///
    /// - Parameter style: The hand-off style.
    /// - Returns: A snappy 0.3 s spring, or a 0.2 s ease-in-out cross-fade.
    static func animation(_ style: Style) -> Animation {
        switch style {
        case .motion: .snappy(duration: 0.3)
        case .crossFade: .easeInOut(duration: 0.2)
        }
    }

    /// How one floating dock button enters or leaves.
    ///
    /// - Parameter style: The hand-off style.
    /// - Returns: Scale-and-fade toward the trailing edge, or a fade alone.
    static func dockTransition(_ style: Style) -> AnyTransition {
        switch style {
        case .motion: .scale(scale: 0.6, anchor: .trailing).combined(with: .opacity)
        case .crossFade: .opacity
        }
    }
}
