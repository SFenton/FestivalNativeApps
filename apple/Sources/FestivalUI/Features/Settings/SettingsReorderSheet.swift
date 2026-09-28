import SwiftUI
import FestivalDesign

// MARK: - SettingsReorderSheet

/// A native drag-to-reorder list presented from a Settings row, the app's form of the
/// web's `ReorderList` (`SettingsPage.tsx:538-551,573-582`).
///
/// Always shows drag handles (forced `.active` edit mode) so a reorder needs no
/// separate "Edit" step; there is nothing to delete, only reorder.
struct SettingsReorderSheet<Item: Identifiable & Hashable>: View {
    let title: String
    let subtitle: String
    @Binding var items: [Item]
    let label: (Item) -> String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items) { item in
                        Text(label(item))
                            .foregroundStyle(BrandTokens.textPrimary)
                            .listRowBackground(Color.white.opacity(0.06))
                    }
                    .onMove { indices, destination in
                        items.move(fromOffsets: indices, toOffset: destination)
                    }
                } footer: {
                    Text(subtitle)
                }
            }
            #if os(iOS)
            .environment(\.editMode, .constant(.active))
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .scrollContentBackground(.hidden)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .festivalSheet(.large)
    }
}
