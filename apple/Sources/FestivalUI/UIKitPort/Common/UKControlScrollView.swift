#if os(iOS)
import UIKit

/// A scroll view whose drags always scroll, even one that starts on a `UIControl` row or
/// button and is held past the content-touch delay. UIKit's default refuses to cancel a
/// control's touches, so such a drag would not scroll; SwiftUI's scroll views scroll from
/// any button, and a held-then-dragged finger (assistive touch, XCUITest's slow drags) must
/// too. Use it for any page whose rows are `UIControl`s.
final class UKControlScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool { true }
}
#endif
