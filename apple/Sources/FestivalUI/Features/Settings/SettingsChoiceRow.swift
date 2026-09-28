import SwiftUI
import FestivalDesign

// MARK: - Choice row

/// A single-choice setting in the iOS Settings style: title, current value and a chevron that
/// pushes a checkmark list (the native form of the web's inline radio groups, e.g.
/// `SettingsPage.tsx` CHOpt Path Default View). Preferred over a dropdown `Menu` picker so the
/// choice reads like system Settings and leaves room for per-option descriptions.
struct SettingsChoiceRow<Value: Hashable & Identifiable>: View {
    let title: String
    let options: [Value]
    let label: (Value) -> String
    @Binding var selection: Value
    let identifier: String

    var body: some View {
        NavigationLink {
            SettingsChoiceList(
                title: title, options: options, label: label, selection: $selection,
                identifier: identifier
            )
        } label: {
            HStack(spacing: 8) {
                SettingLabel(title)
                Spacer(minLength: 8)
                Text(label(selection))
                    .foregroundStyle(FestivalText.primary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(FestivalText.deemphasized)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(label(selection))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Choice list

/// The pushed selection list: one row per option, a checkmark on the current one; choosing
/// applies immediately and pops back, like iOS Settings.
struct SettingsChoiceList<Value: Hashable & Identifiable>: View {
    let title: String
    let options: [Value]
    let label: (Value) -> String
    @Binding var selection: Value
    let identifier: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            FestivalGlassSection {
                ForEach(options) { option in
                    Button {
                        selection = option
                        dismiss()
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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(option == selection ? .isSelected : [])
                    .accessibilityIdentifier("\(identifier).\(option.id)")
                }
            }
            .padding(16)
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
