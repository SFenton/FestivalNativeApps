import SwiftUI

// MARK: - Fade in on load

extension View {
    /// Fade content in once its data has loaded, like the web's load-in transition.
    ///
    /// Hidden (opacity 0, not hit-testable, hidden from accessibility) until
    /// `isLoaded`, then eased in. With Reduce Motion (system or the app's
    /// `fst.accessibility.reduceMotion`) it simply appears.
    ///
    /// - Parameter isLoaded: True once the content has its data.
    /// - Returns: The view with a load-in fade.
    func festivalFadeIn(isLoaded: Bool) -> some View {
        modifier(FestivalFadeInModifier(isLoaded: isLoaded))
    }
}

/// Opacity transition behind ``SwiftUI/View/festivalFadeIn(isLoaded:)``.
private struct FestivalFadeInModifier: ViewModifier {
    let isLoaded: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false

    func body(content: Content) -> some View {
        content
            .opacity(isLoaded ? 1 : 0)
            .allowsHitTesting(isLoaded)
            .accessibilityHidden(!isLoaded)
            .animation(systemReduceMotion || appReduceMotion ? nil : .easeOut(duration: 0.35), value: isLoaded)
    }
}

// MARK: - Fade in when shown

extension View {
    /// ``SwiftUI/View/festivalFadeIn(isLoaded:)`` for content that is only built once
    /// its data exists (a `switch` over a load phase): it fades in on first appearance.
    ///
    /// - Returns: The view, fading in when it first appears.
    func festivalFadeInOnAppear() -> some View {
        modifier(FestivalFadeInOnAppearModifier())
    }
}

/// Flips ``SwiftUI/View/festivalFadeIn(isLoaded:)`` on after the first frame.
private struct FestivalFadeInOnAppearModifier: ViewModifier {
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .festivalFadeIn(isLoaded: appeared)
            .onAppear { appeared = true }
    }
}
