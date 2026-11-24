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
    ///   - monospaced: The monospaced system design (`.monospaced()`).
    /// - Returns: The font, scaled for the current content size category.
    static func font(
        _ style: UIFont.TextStyle, weight: UIFont.Weight? = nil, monospacedDigit: Bool = false, italic: Bool = false,
        monospaced: Bool = false
    ) -> UIFont {
        // A system font scaled by `UIFontMetrics`, landing on the style's own size at the current
        // content size category (what SwiftUI's `.font(style)` draws). Two traps:
        // - fonts not created through `UIFontMetrics` (or `preferredFont`) make the XCUITest
        //   accessibility snapshot drop the subtree they sit in (the open drawer's rows);
        // - the metrics alone run about 20% under the style's own size at AX5, so the base size
        //   is corrected by that ratio for the current category.
        let large = UIFont.preferredFont(
            forTextStyle: style, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        )
        let metrics = UIFontMetrics(forTextStyle: style)
        let target = UIFont.preferredFont(forTextStyle: style).pointSize
        let scaled = metrics.scaledValue(for: large.pointSize)
        let baseSize = scaled > 0 ? large.pointSize * target / scaled : large.pointSize
        let traits = large.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
        let styleWeight = (traits?[.weight] as? CGFloat).map { UIFont.Weight($0) } ?? .regular
        let system = monospaced
            ? UIFont.monospacedSystemFont(ofSize: baseSize, weight: weight ?? styleWeight)
            : UIFont.systemFont(ofSize: baseSize, weight: weight ?? styleWeight)
        var descriptor = system.fontDescriptor
        if monospacedDigit {
            descriptor = descriptor.addingAttributes([
                .featureSettings: [[
                    UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                    UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
                ]],
            ])
        }
        if italic, let slanted = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.traitItalic)) {
            descriptor = slanted
        }
        return metrics.scaledFont(for: UIFont(descriptor: descriptor, size: baseSize))
    }

    /// The preferred text style with SwiftUI's optical spacing, optionally emphasized.
    ///
    /// - Parameters:
    ///   - style: The Dynamic Type text style to preserve.
    ///   - bold: Whether to add the descriptor's bold trait.
    /// - Returns: The preferred font at the current content size category.
    static func preferredFont(_ style: UIFont.TextStyle, bold: Bool = false) -> UIFont {
        let preferred = UIFont.preferredFont(forTextStyle: style)
        guard bold else { return preferred }
        guard let descriptor = preferred.fontDescriptor.withSymbolicTraits(.traitBold) else {
            assertionFailure("The preferred \(style.rawValue) font has no bold descriptor")
            return font(style, weight: .bold)
        }
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

    /// Word-wrapped text with the extra leading SwiftUI gives its lines.
    ///
    /// - Parameters:
    ///   - style: The text style whose Dynamic Type metrics scale the leading.
    ///   - traits: The current content size traits.
    /// - Returns: The paragraph style without additional spacing between paragraphs.
    static func swiftUILeading(_ style: UIFont.TextStyle, traits: UITraitCollection? = nil) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = scaled(2, relativeTo: style, traits: traits)
        return paragraph
    }
}

// MARK: - Label

/// A label in the app's text rules: Dynamic Type, white by default (`FestivalText`),
/// wrapping unless told otherwise.
final class UKLabel: UILabel {
    private let wrapsToLayoutWidth: Bool

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
    ///   - usesSwiftUILeading: Match SwiftUI's extra space between wrapped lines.
    ///   - wrapsToLayoutWidth: Recalculate multiline height after the parent assigns its width.
    init(
        _ text: String? = nil, style: UIFont.TextStyle = .body, weight: UIFont.Weight? = nil,
        monospacedDigit: Bool = false, color: UIColor = BrandUIColors.textPrimary,
        lines: Int = 0, alignment: NSTextAlignment = .natural, usesSwiftUILeading: Bool = false,
        wrapsToLayoutWidth: Bool = false
    ) {
        self.wrapsToLayoutWidth = wrapsToLayoutWidth
        super.init(frame: .zero)
        self.text = text
        font = UKFont.font(style, weight: weight, monospacedDigit: monospacedDigit)
        adjustsFontForContentSizeCategory = true
        textColor = color
        numberOfLines = lines
        textAlignment = alignment
        lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        translatesAutoresizingMaskIntoConstraints = false
        if wrapsToLayoutWidth { setContentCompressionResistancePriority(.required, for: .vertical) }
        if usesSwiftUILeading, let text {
            func updateLeading(_ label: UKLabel) {
                let paragraph = UKFont.swiftUILeading(style, traits: label.traitCollection)
                label.attributedText = NSAttributedString(string: text, attributes: [.paragraphStyle: paragraph])
            }
            updateLeading(self)
            registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (label: UKLabel, _) in
                updateLeading(label)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if wrapsToLayoutWidth { updateWrappedHeight() }
    }

    /// Marks the label as a heading for VoiceOver (`.accessibilityAddTraits(.isHeader)`).
    ///
    /// - Returns: The label, for chaining.
    @discardableResult
    func asHeader() -> Self {
        accessibilityTraits.insert(.header)
        return self
    }
}

extension UILabel {
    /// Invalidates the text height when a multiline label receives a new layout width.
    func updateWrappedHeight() {
        let width = bounds.width
        guard numberOfLines != 1, width > 0, abs(preferredMaxLayoutWidth - width) > 0.5 else { return }
        preferredMaxLayoutWidth = width
        invalidateIntrinsicContentSize()
    }
}
#endif
