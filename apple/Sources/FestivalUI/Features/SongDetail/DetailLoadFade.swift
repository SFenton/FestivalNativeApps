import SwiftUI

// MARK: - Load-in fade for Song Detail and Shop

extension View {
    /// The shared ``SwiftUI/View/festivalFadeInOnAppear()`` load-in fade, skipped under
    /// `FST_DEBUG_STILL_BACKGROUND` so UI-test accessibility audits never sample a
    /// half-faded frame (a mid-fade Shop row failed the contrast audit).
    ///
    /// - Returns: The view, fading in on first appearance unless animations are frozen.
    @ViewBuilder
    func detailFadeInOnAppear() -> some View {
        if DebugAnimationOverride.stillBackground {
            self
        } else {
            festivalFadeInOnAppear()
        }
    }
}
