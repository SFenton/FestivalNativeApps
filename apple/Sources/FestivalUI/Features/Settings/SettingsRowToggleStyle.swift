import SwiftUI

// MARK: - Row toggle

/// A Settings switch whose whole card row is its touch target, like the web `ToggleRow`
/// (the row is the button): the title and description flip the switch too, and the
/// element is at least 44 pt tall (HIG Accessibility › Mobility: "iOS, iPadOS 44×44pt"
/// default; issue #496). It stays the system switch, so VoiceOver reads one switch with
/// the row's label, value and hint.
///
/// Applied on iOS and iPadOS only: Mac Settings rows keep the 28 pt control size.
/// Pattern `settings-toggle-row` (`.agents/patterns/settings-toggle-row.md`).
struct SettingsRowToggleStyle: ToggleStyle {
    /// The row's minimum touch height, the iOS default target size.
    static let minimumHeight: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        SettingsRowToggle(configuration: configuration)
    }
}

/// The body of ``SettingsRowToggleStyle``: the system switch with a tappable label.
private struct SettingsRowToggle: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Toggle(isOn: configuration.$isOn) {
            // Only the label takes this tap; the switch keeps its own, so a tap never
            // flips it twice.
            configuration.label
                .frame(maxWidth: .infinity, minHeight: SettingsRowToggleStyle.minimumHeight, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard isEnabled else { return }
                    configuration.isOn.toggle()
                }
        }
        .toggleStyle(.switch)
    }
}

extension View {
    /// Make each Settings switch's whole row its touch target on touch platforms
    /// (``SettingsRowToggleStyle``); no change on the Mac.
    @ViewBuilder func settingsRowToggles() -> some View {
        #if os(macOS)
        self
        #else
        toggleStyle(SettingsRowToggleStyle())
        #endif
    }
}
