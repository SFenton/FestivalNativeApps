import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Supported orientations

/// Interface orientations, platform-neutral so the policy compiles and tests on macOS.
public struct SupportedOrientations: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    /// Create a set from raw bits.
    ///
    /// - Parameter rawValue: Bit set of orientations.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let portrait = SupportedOrientations(rawValue: 1 << 0)
    public static let portraitUpsideDown = SupportedOrientations(rawValue: 1 << 1)
    public static let landscapeLeft = SupportedOrientations(rawValue: 1 << 2)
    public static let landscapeRight = SupportedOrientations(rawValue: 1 << 3)
    public static let all: SupportedOrientations = [
        .portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight,
    ]

    /// Parse an Info.plist `UISupportedInterfaceOrientations` array.
    ///
    /// - Parameter infoPlistValues: `UIInterfaceOrientation…` names; unknown names are ignored.
    public init(infoPlistValues: [String]) {
        var result: SupportedOrientations = []
        for value in infoPlistValues {
            switch value {
            case "UIInterfaceOrientationPortrait": result.insert(.portrait)
            case "UIInterfaceOrientationPortraitUpsideDown": result.insert(.portraitUpsideDown)
            case "UIInterfaceOrientationLandscapeLeft": result.insert(.landscapeLeft)
            case "UIInterfaceOrientationLandscapeRight": result.insert(.landscapeRight)
            default: break
            }
        }
        self = result
    }
}

// MARK: - Policy

/// Which orientations the app supports (operator decision O1 (b), 2026-10-02).
///
/// The Info.plist declarations stay the source of truth: iPhone is portrait-only and
/// iPad allows all four. A device that reports a hinge (iPhone Duo, detected through
/// `onHingeChange`, never by product name) additionally rotates on its outer display;
/// its inner display ignores supported orientations anyway (Apple tech talk T461).
enum OrientationPolicy {
    /// Resolve the supported orientations.
    ///
    /// - Parameters:
    ///   - declared: The Info.plist declaration for this idiom; empty when missing.
    ///   - hasHinge: A hinge has been observed on this device.
    /// - Returns: Every orientation on a hinged device, otherwise the declaration
    ///   (portrait when nothing is declared).
    static func supported(declared: SupportedOrientations, hasHinge: Bool) -> SupportedOrientations {
        if hasHinge { return .all }
        return declared.isEmpty ? .portrait : declared
    }

    /// The Info.plist key UIKit reads for an idiom, most specific first.
    ///
    /// - Parameter isPad: True for the iPad idiom.
    /// - Returns: Candidate keys, device-specific before the plain key.
    static func infoPlistKeys(isPad: Bool) -> [String] {
        let base = "UISupportedInterfaceOrientations"
        return [base + (isPad ? "~ipad" : "~iphone"), base]
    }

    /// Read the declaration for an idiom from an Info dictionary.
    ///
    /// - Parameters:
    ///   - info: The bundle's Info dictionary.
    ///   - isPad: True for the iPad idiom.
    /// - Returns: The first declared set found, or empty.
    static func declared(in info: [String: Any], isPad: Bool) -> SupportedOrientations {
        for key in infoPlistKeys(isPad: isPad) {
            if let values = info[key] as? [String] {
                return SupportedOrientations(infoPlistValues: values)
            }
        }
        return []
    }
}

// MARK: - Hinge presence

/// Remembers, for the life of the process, that this device has a hinge.
///
/// `DeviceLayoutPublisher` records each `onHingeChange` value and the system vertical-bar
/// edge; the first hinge (or, like `DeviceLayout`'s pose fallback when the hinge is
/// unreported, the first vertical bar, which only iPhone Duo has) marks the device
/// hinged and asks UIKit to re-query supported orientations, so the outer display can
/// rotate. Later nil values (the probe left the hierarchy) never clear it.
@MainActor
public final class HingePresence {
    /// Process-wide instance read by the app delegate.
    public static let shared = HingePresence()

    /// A hinge has been observed on this device.
    public private(set) var hasHinge = false

    /// Called after the device first reports a hinge (re-queries orientations on iOS).
    var onFirstHinge: @MainActor () -> Void

    /// Create a store.
    ///
    /// - Parameter onFirstHinge: Called once, after the first non-nil hinge.
    init(onFirstHinge: @escaping @MainActor () -> Void = HingePresence.requestOrientationUpdate) {
        self.onFirstHinge = onFirstHinge
    }

    /// Record the latest hinge observations.
    ///
    /// - Parameters:
    ///   - hinge: The latest `onHingeChange` value; nil on devices without a hinge.
    ///   - verticalBarEdge: The system vertical-bar edge; nil where none is ever used.
    func record(hinge: HingeState?, verticalBarEdge: HorizontalEdge? = nil) {
        guard hinge != nil || verticalBarEdge != nil, !hasHinge else { return }
        hasHinge = true
        onFirstHinge()
    }

    /// Ask every window's root view controller to re-read supported orientations.
    static func requestOrientationUpdate() {
        #if os(iOS)
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
        #endif
    }
}

#if os(iOS)
// MARK: - UIKit bridge

/// Supported orientations for the app delegate's `supportedInterfaceOrientationsFor`.
public enum FestivalOrientationSupport {
    /// Resolve the mask for a window.
    ///
    /// - Parameter window: The window UIKit asks about, if any.
    /// - Returns: Every orientation once a hinge has been observed, else the Info.plist
    ///   declaration for the window's idiom.
    @MainActor
    public static func mask(for window: UIWindow?) -> UIInterfaceOrientationMask {
        let idiom = window?.traitCollection.userInterfaceIdiom ?? UIDevice.current.userInterfaceIdiom
        let declared = OrientationPolicy.declared(
            in: Bundle.main.infoDictionary ?? [:], isPad: idiom == .pad
        )
        return OrientationPolicy.supported(
            declared: declared, hasHinge: HingePresence.shared.hasHinge
        ).interfaceOrientationMask
    }
}

extension SupportedOrientations {
    /// The UIKit mask for this set.
    var interfaceOrientationMask: UIInterfaceOrientationMask {
        var mask: UIInterfaceOrientationMask = []
        if contains(.portrait) { mask.insert(.portrait) }
        if contains(.portraitUpsideDown) { mask.insert(.portraitUpsideDown) }
        if contains(.landscapeLeft) { mask.insert(.landscapeLeft) }
        if contains(.landscapeRight) { mask.insert(.landscapeRight) }
        return mask
    }
}
#endif
