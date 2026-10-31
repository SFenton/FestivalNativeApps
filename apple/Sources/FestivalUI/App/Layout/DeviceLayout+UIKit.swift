#if os(iOS)
import CoreGraphics
import SwiftUI
import UIKit

// MARK: - UIKit-facing layout values

/// UIKit-facing views of the shared layout model, so the UIKit port (which never imports
/// SwiftUI) reads ``DeviceLayout``, ``LayoutSignals`` and ``DrawerPlacement`` without
/// touching `EdgeInsets`.
extension LayoutSignals {
    /// Signals assembled from UIKit observations.
    ///
    /// - Parameters:
    ///   - size: Window size in points.
    ///   - widthClass: Horizontal size class.
    ///   - heightClass: Vertical size class.
    ///   - safeArea: Window safe-area insets (physical left/right).
    ///   - verticalBarIsLeading: The system vertical bar's edge (nil: no vertical bar).
    ///   - hinge: Hinge status, nil without a hinge.
    ///   - occlusions: Active occlusion frames.
    ///   - divisions: Active division frames.
    ///   - hinges: Every division frame, active or not.
    ///   - usesSidebarShell: True for the iPad flyout shell.
    init(
        uikitSize size: CGSize, widthClass: WidthClass, heightClass: WidthClass, safeArea: UIEdgeInsets,
        verticalBarIsLeading: Bool?, hinge: HingeState?, occlusions: [CGRect], divisions: [CGRect],
        hinges: [CGRect], usesSidebarShell: Bool
    ) {
        self.init(
            size: size, widthClass: widthClass, heightClass: heightClass,
            safeAreaInsets: EdgeInsets(
                top: safeArea.top, leading: safeArea.left, bottom: safeArea.bottom, trailing: safeArea.right
            ),
            verticalBarEdge: verticalBarIsLeading.map { $0 ? .leading : .trailing }, hinge: hinge,
            occlusions: occlusions, divisions: divisions, hinges: hinges, usesSidebarShell: usesSidebarShell
        )
    }

    /// The signals with the Debug launch overrides applied (`FST_DEBUG_DUO_POSE`,
    /// `FST_DEBUG_DUO_WINDOW[_REMOTE]`), exactly as `DeviceLayoutPublisher` does.
    ///
    /// - Returns: The signals, unchanged in Release.
    @MainActor
    func applyingDebugOverrides() -> LayoutSignals {
        #if DEBUG
        let posed = DebugDuoPose.launch?.apply(to: self) ?? self
        return DebugDuoWindowRemote.shared.window?.apply(to: posed) ?? posed
        #else
        return self
        #endif
    }
}

extension DeviceLayout {
    /// The window's safe-area insets as UIKit insets.
    var uikitSafeArea: UIEdgeInsets {
        UIEdgeInsets(
            top: safeAreaInsets.top, left: safeAreaInsets.leading,
            bottom: safeAreaInsets.bottom, right: safeAreaInsets.trailing
        )
    }

    /// Cutout-safe overlay insets (``overlayInsets``) as UIKit insets.
    var uikitOverlayInsets: UIEdgeInsets {
        UIEdgeInsets(
            top: overlayInsets.top, left: overlayInsets.leading,
            bottom: overlayInsets.bottom, right: overlayInsets.trailing
        )
    }

    /// Hardware cutout insets (``cutoutInsets``) as UIKit insets.
    var uikitCutoutInsets: UIEdgeInsets {
        UIEdgeInsets(
            top: cutoutInsets.top, left: cutoutInsets.leading,
            bottom: cutoutInsets.bottom, right: cutoutInsets.trailing
        )
    }
}

extension DrawerPlacement {
    /// The placement for a window, from UIKit insets.
    ///
    /// - Parameters:
    ///   - size: The window inside its safe area.
    ///   - safeArea: Window safe-area insets.
    ///   - layout: Published device layout.
    /// - Returns: Panel geometry.
    static func resolve(size: CGSize, uikitSafeArea safeArea: UIEdgeInsets, layout: DeviceLayout) -> DrawerPlacement {
        resolve(
            size: size,
            safeArea: EdgeInsets(
                top: safeArea.top, leading: safeArea.left, bottom: safeArea.bottom, trailing: safeArea.right
            ),
            layout: layout
        )
    }

    /// The panel's padding from the window edges as UIKit insets.
    var uikitPanelPadding: UIEdgeInsets {
        UIEdgeInsets(
            top: panelPadding.top, left: panelPadding.leading,
            bottom: panelPadding.bottom, right: panelPadding.trailing
        )
    }
}
#endif

#if os(iOS)
extension OnDemandSplitPolicy {
    /// The context an iOS split reads from the window layout, for a UIKit container.
    ///
    /// - Parameters:
    ///   - layout: The window layout.
    ///   - container: The split container's frame in window coordinates.
    ///   - rightToLeft: Whether the container lays out right to left.
    /// - Returns: The split context.
    static func uikitContext(layout: DeviceLayout, container: CGRect, rightToLeft: Bool) -> Context {
        context(layout: layout, container: container, layoutDirection: rightToLeft ? .rightToLeft : .leftToRight)
    }
}

extension DeviceLayout {
    /// ``freeSpan(layoutDirection:)`` for a UIKit layout direction.
    ///
    /// - Parameter rightToLeft: Whether the layout is right to left.
    /// - Returns: The free horizontal span, or nil before the first geometry pass.
    func uikitFreeSpan(rightToLeft: Bool) -> ClosedRange<CGFloat>? {
        freeSpan(layoutDirection: rightToLeft ? .rightToLeft : .leftToRight)
    }
}
#endif
