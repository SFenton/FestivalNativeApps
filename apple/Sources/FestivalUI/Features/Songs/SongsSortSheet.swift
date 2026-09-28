import Foundation
import SwiftUI
import FestivalCore
import FestivalDesign

/// Songs sort choices. Changes apply as they are made (operator, 2026-09-28: no
/// Cancel/Apply); Done closes the standard `festivalSheet` modal.
struct SongsSortSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draftMode: SongSortMode
    @State private var draftAscending: Bool
    let mode: SongSortMode
    let ascending: Bool
    let showShop: Bool
    let shopAvailable: Bool
    let onApply: (SongSortMode, Bool) -> Void

    /// Start every presentation from the currently applied sort preference.
    ///
    /// - Parameters:
    ///   - mode: Applied public catalogue or Shop sort mode.
    ///   - ascending: Applied direction.
    ///   - showShop: False when Settings hides the entire Shop feature.
    ///   - shopAvailable: True only after receiving a validated public feed.
    ///   - onApply: Commits the mode and direction; called on every change.
    init(
        mode: SongSortMode, ascending: Bool,
        showShop: Bool = false, shopAvailable: Bool = false,
        onApply: @escaping (SongSortMode, Bool) -> Void
    ) {
        self.mode = mode
        self.ascending = ascending
        self.showShop = showShop
        self.shopAvailable = shopAvailable
        self.onApply = onApply
        _draftMode = State(initialValue: mode)
        _draftAscending = State(initialValue: ascending)
    }

    /// A choice the list can actually use (Item Shop needs a visible, loaded feed).
    private var isApplicable: Bool {
        draftMode != .shop || (showShop && shopAvailable)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sort by") {
                    Picker("Sort by", selection: $draftMode) {
                        ForEach(SongSortMode.allCases.filter {
                            showShop || $0 != .shop
                        }) { choice in
                            Text(choice.label).tag(choice)
                                .disabled(choice == .shop && !shopAvailable)
                        }
                    }
                    .pickerStyle(.inline)
                    .accessibilityIdentifier("fst.songs.sort.mode")
                    if showShop && !shopAvailable {
                        Text("Item Shop sorting requires matching public Songs and Shop data.")
                            .font(.footnote)
                            .foregroundStyle(FestivalText.primary)
                    } else if !showShop && mode == .shop {
                        Text("Item Shop sort is saved but hidden. Reset to Title A-Z "
                            + "to choose another mode.")
                            .font(.footnote)
                            .foregroundStyle(FestivalText.primary)
                    }
                }
                Section("Direction") {
                    Picker("Direction", selection: $draftAscending) {
                        Text("Ascending").tag(true)
                        Text("Descending").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("fst.songs.sort.direction")
                }
                Section {
                    Button("Reset to Title A-Z") {
                        draftMode = .title
                        draftAscending = true
                    }
                    .font(.body)
                    .tint(FestivalText.primary)
                    .accessibilityIdentifier("fst.songs.sort.reset")
                }
            }
            .navigationTitle("Sort Songs")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // Dismiss-only modal: trailing Done (modal standard, operator 2026-09-28).
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("fst.songs.sort.done")
                }
            }
            .onChange(of: draftMode) { _, _ in commit() }
            .onChange(of: draftAscending) { _, _ in commit() }
        }
        // Simple, fixed-height picker: compact detent (medium, expandable to large).
        .festivalSheet(.compact)
    }

    /// Apply the current choice immediately when the list can use it.
    private func commit() {
        guard isApplicable else { return }
        onApply(draftMode, draftAscending)
    }
}

/// Compact, announced refresh error that does not remove the current song list.
