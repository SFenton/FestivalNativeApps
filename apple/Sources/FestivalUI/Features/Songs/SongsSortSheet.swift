import Foundation
import SwiftUI
import FestivalCore
import FestivalDesign

struct SongsSortSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var draftMode: SongSortMode
    @State private var draftAscending: Bool
    @State private var discardPending = false
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
    ///   - onApply: Commit both draft fields together after explicit confirmation.
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

    private var hasChanges: Bool {
        draftMode != mode || draftAscending != ascending
    }

    private var actionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
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
                            .foregroundStyle(BrandTokens.textSecondary)
                    } else if !showShop && mode == .shop {
                        Text("Item Shop sort is saved but hidden. Reset to Title A-Z "
                            + "to choose another mode.")
                            .font(.footnote)
                            .foregroundStyle(BrandTokens.textSecondary)
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
                    .tint(BrandTokens.textPrimary)
                    .accessibilityIdentifier("fst.songs.sort.reset")
                }
            }
            .navigationTitle("Sort Songs")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionLayout {
                    Button {
                        if hasChanges { discardPending = true }
                        else { dismiss() }
                    } label: {
                        Text("Cancel")
                            .font(.body)
                            .foregroundStyle(BrandTokens.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                BrandTokens.cardBackground,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                    }
                    .buttonStyle(HighContrastPagerStyle())
                    .accessibilityIdentifier("fst.songs.sort.cancel")
                    Button {
                        onApply(draftMode, draftAscending)
                        dismiss()
                    } label: {
                        Text("Apply")
                            .font(.body.bold())
                            .foregroundStyle(
                                hasChanges
                                    ? BrandTokens.textPrimary : BrandTokens.textSecondary
                            )
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                BrandTokens.cardBackground,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                    }
                    .buttonStyle(HighContrastPagerStyle())
                    .disabled(!hasChanges
                        || (draftMode == .shop && (!showShop || !shopAvailable)))
                    .accessibilityIdentifier("fst.songs.sort.apply")
                }
                .padding(12)
                .background(BrandTokens.cardBackground)
            }
        }
        .alert("Discard sort changes?", isPresented: $discardPending) {
            Button("Continue Editing", role: .cancel) {}
            Button("Discard Changes", role: .destructive) { dismiss() }
        } message: {
            Text("The song list will keep its current order.")
        }
        .interactiveDismissDisabled()
    }
}

/// Compact, announced refresh error that does not remove the current song list.
