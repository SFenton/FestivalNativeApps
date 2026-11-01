#if os(iOS)
import FestivalDesign
import UIKit

// MARK: - Fonts

/// The SwiftUI text styles as Dynamic Type fonts: `.font(.body.weight(.semibold))` is
/// `UKFont.font(.body, weight: .semibold)`. Every font scales with the content size
/// category up to AX5 (`UIFontMetrics`), so a label that sets
/// `adjustsFontForContentSizeCategory` follows the setting live.
enum UKFont {
    /// A scaled system font.
    ///
    /// - Parameters:
    ///   - style: The text style (`.headline`, `.body`, `.caption` …).
    ///   - weight: A weight override (`.bold()` is `.bold`); nil keeps the style's weight.
    ///   - monospacedDigit: Fixed-width digits (`.monospacedDigit()`).
    ///   - italic: Italic (`.italic()`).
    /// - Returns: The font, scaled for the current content size category.
    static func font(
        _ style: UIFont.TextStyle, weight: UIFont.Weight? = nil, monospacedDigit: Bool = false, italic: Bool = false
    ) -> UIFont {
        // The style's own font at the current content size category, with its text-style
        // attribute kept through the weight, digit and italic changes: a font the Dynamic Type
        // audit and `adjustsFontForContentSizeCategory` both recognise, at exactly the size
        // SwiftUI's `.font(style)` draws (rescaling a `.large` base through `UIFontMetrics`
        // came out about 20% smaller at AX5).
        let base = UIFont.preferredFont(forTextStyle: style)
        var descriptor = base.fontDescriptor
        if let weight {
            descriptor = descriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        }
        if monospacedDigit {
            descriptor = descriptor.addingAttributes([
                .featureSettings: [[
                    UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                    UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
                ]],
            ])
        }
        if italic, let slanted = descriptor.withSymbolicTraits(.traitItalic) { descriptor = slanted }
        return UIFont(descriptor: descriptor, size: 0)
    }

    /// Whether the content size category is an accessibility size (`isAccessibilitySize`).
    ///
    /// - Parameter traits: The view's trait collection.
    static func isAccessibilitySize(_ traits: UITraitCollection) -> Bool {
        traits.preferredContentSizeCategory.isAccessibilityCategory
    }

    /// A point value that scales with Dynamic Type (`@ScaledMetric(relativeTo:)`).
    ///
    /// - Parameters:
    ///   - value: The size at the default category.
    ///   - style: The text style it scales relative to.
    ///   - traits: The view's trait collection.
    static func scaled(_ value: CGFloat, relativeTo style: UIFont.TextStyle, traits: UITraitCollection? = nil) -> CGFloat {
        UIFontMetrics(forTextStyle: style).scaledValue(for: value, compatibleWith: traits)
    }
}

// MARK: - Label

/// A label in the app's text rules: Dynamic Type, white by default (`FestivalText`),
/// wrapping unless told otherwise.
final class UKLabel: UILabel {
    /// Creates a label.
    ///
    /// - Parameters:
    ///   - text: The string.
    ///   - style: The text style.
    ///   - weight: A weight override.
    ///   - monospacedDigit: Fixed-width digits.
    ///   - color: Defaults to ``BrandUIColors/textPrimary`` (the white-text rule).
    ///   - lines: Line limit; 0 wraps (the SwiftUI default is unlimited with `fixedSize`).
    ///   - alignment: Text alignment.
    init(
        _ text: String? = nil, style: UIFont.TextStyle = .body, weight: UIFont.Weight? = nil,
        monospacedDigit: Bool = false, color: UIColor = BrandUIColors.textPrimary,
        lines: Int = 0, alignment: NSTextAlignment = .natural
    ) {
        super.init(frame: .zero)
        self.text = text
        font = UKFont.font(style, weight: weight, monospacedDigit: monospacedDigit)
        adjustsFontForContentSizeCategory = true
        textColor = color
        numberOfLines = lines
        textAlignment = alignment
        lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Marks the label as a heading for VoiceOver (`.accessibilityAddTraits(.isHeader)`).
    ///
    /// - Returns: The label, for chaining.
    @discardableResult
    func asHeader() -> Self {
        accessibilityTraits.insert(.header)
        return self
    }
}
#endif
