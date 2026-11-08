#if os(iOS)
import UIKit

// MARK: - Row switch

/// A system switch that is its row's one accessibility stop: it keeps the switch role and the
/// `1` / `0` value XCUITest and VoiceOver read, while its accessibility frame is the whole row
/// (the row is the touch target), optionally padded where the row is shorter than 44 pt.
/// Settings, Songs and Suggestions switch rows all use it.
@MainActor
final class UKRowSwitch: UISwitch, UIGestureRecognizerDelegate {
    private weak var rowTap: UITapGestureRecognizer?
    /// The row whose bounds are the switch's accessibility frame.
    weak var row: UIView?
    /// Outsets added to the row's bounds (negative insets grow the frame).
    var framePadding: UIEdgeInsets = .zero

    override var accessibilityFrame: CGRect {
        get {
            guard let row else { return super.accessibilityFrame }
            return UIAccessibility.convertToScreenCoordinates(row.bounds.inset(by: framePadding), in: row)
        }
        set { super.accessibilityFrame = newValue }
    }

    /// Flips the switch as a tap on the row does, and reports the change.
    @objc func flip() {
        guard isEnabled else { return }
        setOn(!isOn, animated: !UKAccessibility.reduceMotion)
        sendActions(for: .valueChanged)
    }

    /// Gives the surrounding row one tap action while native switch touches keep their own.
    func installRowTap(on row: UIView) {
        if let rowTap { rowTap.view?.removeGestureRecognizer(rowTap) }
        self.row = row
        let tap = UITapGestureRecognizer(target: self, action: #selector(flip))
        tap.delegate = self
        row.addGestureRecognizer(tap)
        rowTap = tap
    }

    /// Excludes the switch and all its descendants, preventing a native tap from flipping twice.
    func handlesRowTap(from touchedView: UIView?) -> Bool {
        var view = touchedView
        while let current = view {
            if current === self { return false }
            view = current.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        handlesRowTap(from: touch.view)
    }
}
#endif
