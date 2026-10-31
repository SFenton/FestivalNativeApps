#if os(iOS)
import FestivalDesign
import UIKit

// MARK: - Accessibility settings

/// The system and in-app accessibility settings the SwiftUI design code reads through
/// `@Environment` and `@AppStorage`, read for UIKit (`GlassSurface`, `RowCardSurface`,
/// `ScrollEdgeFadeModifiers`, the reduce-motion rule).
@MainActor
enum UKAccessibility {
    /// The in-app Reduce Transparency toggle (`fst.accessibility.lessTransparency`).
    static var lessTransparency: Bool { UKSettings.bool("fst.accessibility.lessTransparency", default: false) }
    /// The in-app Increase Contrast toggle (`fst.accessibility.moreContrast`).
    static var moreContrast: Bool { UKSettings.bool("fst.accessibility.moreContrast", default: false) }
    /// The in-app Reduce Motion toggle (`fst.accessibility.reduceMotion`).
    static var appReduceMotion: Bool { UKSettings.bool("fst.accessibility.reduceMotion", default: false) }

    /// System or in-app Reduce Motion, the rule every SwiftUI animation site applies.
    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled || appReduceMotion }

    /// System Reduce Transparency.
    static var systemReduceTransparency: Bool { UIAccessibility.isReduceTransparencyEnabled }

    /// Whether system Increase Contrast is on for a view's traits (`colorSchemeContrast`).
    ///
    /// - Parameter traits: The view's trait collection.
    static func systemIncreasedContrast(_ traits: UITraitCollection) -> Bool {
        traits.accessibilityContrast == .high
    }

    /// The ``FestivalGlassSurface`` for the current settings (`FestivalGlassSettings.surface`).
    ///
    /// - Parameter traits: The view's trait collection.
    static func glassSurface(_ traits: UITraitCollection) -> FestivalGlassSurface {
        FestivalGlassSurface.resolve(
            reduceTransparency: systemReduceTransparency,
            increasedContrast: systemIncreasedContrast(traits),
            lessTransparency: lessTransparency, moreContrast: moreContrast,
            glassAvailable: FestivalGlassSurface.glassAvailable
        )
    }

    /// Whether material cards draw opaque (`FestivalCardModifier`: Reduce Transparency
    /// or the in-app toggles; system Increase Contrast only darkens the tint).
    static var cardIsOpaque: Bool { systemReduceTransparency || lessTransparency || moreContrast }

    /// Whether a scroll-edge fade draws a hard edge (`ScrollEdgeHardEdge`).
    ///
    /// - Parameter traits: The view's trait collection.
    static func hardEdge(_ traits: UITraitCollection) -> Bool {
        ScrollEdgeHardEdge.resolve(
            reduceTransparency: systemReduceTransparency || lessTransparency,
            increaseContrast: moreContrast || systemIncreasedContrast(traits)
        )
    }

    /// Notifications that can change any of the settings above; observe these with
    /// ``UKAccessibilityObserver``.
    static let changeNotifications: [Notification.Name] = [
        UIAccessibility.reduceTransparencyStatusDidChangeNotification,
        UIAccessibility.darkerSystemColorsStatusDidChangeNotification,
        UIAccessibility.reduceMotionStatusDidChangeNotification,
        UKSettings.didChange,
    ]
}

/// Calls a closure on the main queue whenever an accessibility setting or an app
/// setting changes. A view holds one for as long as it should follow the settings.
@MainActor
final class UKAccessibilityObserver {
    nonisolated(unsafe) private var tokens: [NSObjectProtocol] = []

    /// Starts observing.
    ///
    /// - Parameter onChange: Runs on the main actor after a settings change.
    init(_ onChange: @escaping @MainActor () -> Void) {
        tokens = UKAccessibility.changeNotifications.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { onChange() }
            }
        }
    }

    deinit { tokens.forEach { NotificationCenter.default.removeObserver($0) } }
}

// MARK: - Accent colours

/// Readable accent colours for dark surfaces (``AccentText``), as `UIColor`.
enum UKAccentText {
    /// Lighter accent blue for text values and ratings.
    static let blue = UIColor(
        red: AccentText.blueRGB.red, green: AccentText.blueRGB.green, blue: AccentText.blueRGB.blue, alpha: 1
    )
    /// Fill of a prominent button behind a white label.
    static let prominentFill = UIColor(
        red: AccentText.prominentFillRGB.red, green: AccentText.prominentFillRGB.green,
        blue: AccentText.prominentFillRGB.blue, alpha: 1
    )

    /// Fill and label of a prominent button (`FestivalProminentButtonColors`).
    ///
    /// - Parameter increasedContrast: System Increase Contrast or the in-app toggle.
    /// - Returns: The button's fill and its label colour.
    @MainActor
    static func prominentColors(increasedContrast: Bool) -> (fill: UIColor, label: UIColor) {
        increasedContrast
            ? (BrandUIColors.textPrimary, BrandUIColors.appBackground)
            : (prominentFill, BrandUIColors.textPrimary)
    }
}
#endif
