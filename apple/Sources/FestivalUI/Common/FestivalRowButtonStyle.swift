import SwiftUI
import FestivalDesign

// MARK: - Row button style

/// The button style of a whole-row (card) button: a plain button everywhere, plus on
/// the Mac a hover highlight and a visible keyboard focus ring.
///
/// HIG Pointing devices: use a hover effect "for large ones (customize scale, tint and
/// shadow as needed)" and "reserve scaling for elements that can grow without crowding
/// neighbors (not table rows); with little surrounding space, consider tint without
/// scale and shadow" → a translucent white tint, no scale. HIG Focus and selection:
/// "Rely on system focus effects", "highlight items in lists and collections" → the
/// row draws the system keyboard-focus colour as a ring in its own rounded shape while
/// Full Keyboard Access focuses it (the system ring of an invisible or plain button is
/// not visible on these glass cards).
struct FestivalRowButtonStyle: ButtonStyle {
    /// Corner radius of the row's card.
    var cornerRadius: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        #if os(macOS)
        MacRowButtonBody(configuration: configuration, cornerRadius: cornerRadius)
        #else
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
        #endif
    }
}

#if os(macOS)
/// ``FestivalRowButtonStyle`` plus Return: a row focused with the keyboard opens with
/// Return as well as Space (HIG Keyboards: "Support Full Keyboard Access … keyboard-only
/// navigation and activation"; Space is the system's own activation key).
struct FestivalRowPrimitiveButtonStyle: PrimitiveButtonStyle {
    var cornerRadius: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .buttonStyle(FestivalRowButtonStyle(cornerRadius: cornerRadius))
            .onKeyPress(.return) {
                configuration.trigger()
                return .handled
            }
    }
}

/// The Mac body of ``FestivalRowButtonStyle``.
private struct MacRowButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let cornerRadius: CGFloat

    var body: some View {
        configuration.label
            .modifier(MacRowInteractionEffect(cornerRadius: cornerRadius, isPressed: configuration.isPressed))
    }
}

/// Hover tint and keyboard focus ring for a row's card; apply it to a button's label
/// (the nearest focusable ancestor is then the button, so `isFocused` is its focus).
struct MacRowInteractionEffect: ViewModifier {
    let cornerRadius: CGFloat
    var isPressed = false
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .overlay {
                shape
                    .fill(Color.white.opacity(MacRowInteraction.tint(hovered: isHovered, pressed: isPressed)))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay {
                if isFocused {
                    shape
                        .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onHover { isHovered = isEnabled && $0 }
    }
}
#endif

// MARK: - Hover tint

/// Pure hover/press tint rules for Mac rows and cards.
enum MacRowInteraction {
    /// White overlay opacity: none at rest, a light tint under the pointer, a stronger
    /// one while pressed.
    ///
    /// - Parameters:
    ///   - hovered: The pointer is over the row.
    ///   - pressed: The row is being clicked.
    /// - Returns: The overlay opacity.
    static func tint(hovered: Bool, pressed: Bool) -> Double {
        pressed ? 0.14 : hovered ? 0.07 : 0
    }
}

extension View {
    /// Style a whole-row or card button: ``FestivalRowPrimitiveButtonStyle`` on the Mac
    /// (hover tint, keyboard focus ring, Return opens), the plain style elsewhere (iPhone and iPad
    /// unchanged).
    ///
    /// - Parameter cornerRadius: Corner radius of the row's card.
    /// - Returns: The styled button.
    @ViewBuilder func festivalRowButtonStyle(cornerRadius: CGFloat = 12) -> some View {
        #if os(macOS)
        buttonStyle(FestivalRowPrimitiveButtonStyle(cornerRadius: cornerRadius))
        #else
        buttonStyle(.plain)
        #endif
    }
}
