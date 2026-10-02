import SwiftUI
import FestivalDesign

// MARK: - Choice row

/// A single-choice setting shown as an inline accordion: the collapsed row shows the title, its
/// description and the current value; expanding it in place reveals one checkmark row per option.
///
/// Mirrors the web's inline radio rows (`SettingsPage.tsx` CHOpt Path Default View) and the
/// app's own Filter sheet accordions. Built on the system `DisclosureGroup`, which Apple's HIG
/// names as the iOS disclosure control, so choosing never navigates away from Settings.
struct SettingsChoiceRow<Value: Hashable & Identifiable>: View {
    let title: String
    let detail: String?
    let options: [Value]
    let label: (Value) -> String
    @Binding var selection: Value
    let identifier: String
    let animation: Animation?
    @State private var isExpanded: Bool
    @Environment(\.settingsChoicesUsePopUpButtons) private var usesPopUpButton

    /// Create an inline single-choice accordion.
    ///
    /// - Parameters:
    ///   - title: Title Case setting name; also the spoken label.
    ///   - detail: Optional sentence-case description under the title.
    ///   - options: Choices in display order.
    ///   - label: Visible and spoken name for a choice.
    ///   - selection: Persisted current choice; written immediately on tap.
    ///   - identifier: Accessibility identifier of the header; options append `.<id>`.
    ///   - animation: Expand/collapse animation, `nil` under Reduce Motion.
    ///   - initiallyExpanded: Starting disclosure state (tests and snapshots).
    init(
        title: String,
        detail: String? = nil,
        options: [Value],
        label: @escaping (Value) -> String,
        selection: Binding<Value>,
        identifier: String,
        animation: Animation? = .easeInOut(duration: 0.2),
        initiallyExpanded: Bool = false
    ) {
        self.title = title
        self.detail = detail
        self.options = options
        self.label = label
        self._selection = selection
        self.identifier = identifier
        self.animation = animation
        self._isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        if usesPopUpButton {
            popUpRow
        } else {
            disclosure
        }
    }

    /// The Mac Settings window's pop-up button (HIG Pop-up buttons: "a flat list of
    /// mutually exclusive options … the button can show the current selection").
    private var popUpRow: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingLabel(title, detail: detail)
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            Picker(title, selection: $selection) {
                ForEach(options) { option in
                    Text(label(option)).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityLabel(title)
            .accessibilityHint(detail ?? "")
            .accessibilityIdentifier(identifier)
        }
    }

    /// The inline accordion (iPhone, iPad).
    private var disclosure: some View {
        DisclosureGroup(isExpanded: $isExpanded.animation(animation)) {
            VStack(spacing: 0) {
                ForEach(options) { option in
                    optionRow(option)
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(alignment: .center, spacing: 8) {
                SettingLabel(title, detail: detail)
                Spacer(minLength: 8)
                Text(label(selection))
                    .foregroundStyle(FestivalText.primary)
            }
            // The disclosure button centers wrapped text by default.
            .multilineTextAlignment(.leading)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(
                SettingsChoiceAccessibility.value(
                    selected: label(selection), isExpanded: isExpanded
                )
            )
            .accessibilityHint(detail ?? "")
            // ID on the label, not the group: on iOS 26 a DisclosureGroup identifier
            // replaces every nested element's own (see SongsFilterSheet).
            .accessibilityIdentifier(identifier)
        }
        .tint(FestivalText.primary)
    }

    /// One option: name and a checkmark on the current choice; tapping selects it in place.
    private func optionRow(_ option: Value) -> some View {
        Button {
            selection = option
        } label: {
            HStack {
                Text(label(option))
                    .foregroundStyle(FestivalText.primary)
                Spacer(minLength: 8)
                if option == selection {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(BrandTokens.accentBlue)
                        .accessibilityHidden(true)
                }
            }
            .padding(.leading, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label(option))
        .accessibilityAddTraits(option == selection ? .isSelected : [])
        .accessibilityIdentifier("\(identifier).\(option.id)")
    }
}

// MARK: - Style

extension EnvironmentValues {
    /// Whether ``SettingsChoiceRow`` draws a pop-up button instead of the inline
    /// accordion (set by the Mac Settings window).
    @Entry var settingsChoicesUsePopUpButtons = false
}

// MARK: - Accessibility

/// Spoken value of a ``SettingsChoiceRow`` header.
enum SettingsChoiceAccessibility {
    /// The current choice followed by the disclosure state, e.g. "Image, Collapsed".
    ///
    /// SwiftUI has no public modifier for an element's expanded status, and `DisclosureGroup`
    /// leaves UIKit's `accessibilityExpandedStatus` unsupported (probed on iOS 26.5), so the
    /// state is spoken as part of the value.
    ///
    /// - Parameters:
    ///   - selected: Visible name of the current choice.
    ///   - isExpanded: Whether the options are shown.
    /// - Returns: The accessibility value.
    static func value(selected: String, isExpanded: Bool) -> String {
        "\(selected), \(isExpanded ? "Expanded" : "Collapsed")"
    }
}
