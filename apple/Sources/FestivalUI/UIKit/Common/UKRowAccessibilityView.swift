#if os(iOS)
import UIKit

// MARK: - Accessibility proxy

/// An invisible, touch-transparent view that carries one accessibility stop (the combined row
/// button, a field, a card): real views are what UIKit and XCUITest reliably expose from a
/// collection-view cell. Songs and Item Shop rows and the search result rows
/// use it: a list cell reads as `Cell`, not `Button`, even with the button trait.
final class UKRowAccessibilityView: UIView {
    var onActivate: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func accessibilityActivate() -> Bool {
        onActivate?()
        return onActivate != nil
    }

    /// Configures the stop.
    func set(identifier: String, label: String, traits: UIAccessibilityTraits, frame: CGRect, exposed: Bool = true) {
        self.frame = frame
        isAccessibilityElement = exposed
        accessibilityIdentifier = identifier
        accessibilityLabel = label
        accessibilityTraits = traits
    }
}
#endif
