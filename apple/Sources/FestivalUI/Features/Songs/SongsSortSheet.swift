import Foundation
import SwiftUI
import FestivalCore
import FestivalDesign

/// Songs sort choices. Changes apply as they are made (operator, 2026-09-28: no
/// Cancel/Apply); the shared ``FestivalModal``'s system Close dismisses it.
struct SongsSortSheet: View {
    @State private var draftMode: SongSortMode
    @State private var draftAscending: Bool
    let mode: SongSortMode
    let ascending: Bool
    let showShop: Bool
    let shopAvailable: Bool
    /// Selected-player sorts offered for the one Songs instrument (empty hides them).
    let playerModes: [SongSortMode]
    let onApply: (SongSortMode, Bool) -> Void

    /// Start every presentation from the currently applied sort preference.
    ///
    /// - Parameters:
    ///   - mode: Applied public catalogue or Shop sort mode.
    ///   - ascending: Applied direction.
    ///   - showShop: False when Settings hides the entire Shop feature.
    ///   - shopAvailable: True only after receiving a validated public feed.
    ///   - playerModes: Score/Percentile/Stars sorts offered with a selected player and
    ///     one Songs instrument (web "Filtered Instrument Sort Mode"); empty hides them.
    ///   - onApply: Commits the mode and direction; called on every change.
    init(
        mode: SongSortMode, ascending: Bool,
        showShop: Bool = false, shopAvailable: Bool = false,
        playerModes: [SongSortMode] = [],
        onApply: @escaping (SongSortMode, Bool) -> Void
    ) {
        self.mode = mode
        self.ascending = ascending
        self.showShop = showShop
        self.shopAvailable = shopAvailable
        self.playerModes = playerModes
        self.onApply = onApply
        _draftMode = State(initialValue: mode)
        _draftAscending = State(initialValue: ascending)
    }

    /// A choice the list can actually use (Item Shop needs a visible, loaded feed).
    private var isApplicable: Bool {
        if draftMode.isPlayerChartMode { return playerModes.contains(draftMode) }
        return draftMode != .shop || (showShop && shopAvailable)
    }

    /// One of two pickers sharing the draft mode: each shows a checkmark only for its
    /// own group's modes.
    ///
    /// - Parameter player: True for the selected-player group.
    /// - Returns: A binding that is nil while the other group's mode is chosen.
    private func modeBinding(player: Bool) -> Binding<SongSortMode?> {
        Binding(
            get: { draftMode.isPlayerChartMode == player ? draftMode : nil },
            set: { if let choice = $0 { draftMode = choice } }
        )
    }

    var body: some View {
        FestivalModal("Sort By", closeIdentifier: "fst.songs.sort.done") {
            Form {
                Section {
                    Picker("Sort By", selection: modeBinding(player: false)) {
                        ForEach(SongSortMode.catalogueModes.filter {
                            showShop || $0 != .shop
                        }) { choice in
                            Text(choice.label).tag(SongSortMode?.some(choice))
                                .disabled(choice == .shop && !shopAvailable)
                        }
                    }
                    .pickerStyle(.inline)
                    // The section header already says "Sort Mode": no extra label row.
                    .labelsHidden()
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
                } header: {
                    FestivalSectionHeader("Sort Mode")
                }
                if !playerModes.isEmpty {
                    Section {
                        Picker("Instrument Sort", selection: modeBinding(player: true)) {
                            ForEach(playerModes) { choice in
                                Text(choice.label).tag(SongSortMode?.some(choice))
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                        .accessibilityIdentifier("fst.songs.sort.player-mode")
                    } header: {
                        FestivalSectionHeader(
                            "Filtered Instrument Sort Mode",
                            subtitle: "Filtering to a single instrument enables more sort options."
                        )
                    }
                }
                Section {
                    SortDirectionControl(ascending: $draftAscending)
                } header: {
                    FestivalSectionHeader("Sort Direction")
                }
                Section {
                    // Reset is red in every filter and sort sheet (operator batch 7).
                    Button("Reset to Title A–Z", role: .destructive) {
                        draftMode = .title
                        draftAscending = true
                    }
                    .font(.body)
                    .foregroundStyle(FestivalSheetActionColor.destructive)
                    .accessibilityIdentifier("fst.songs.sort.reset")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: draftMode) { _, _ in commit() }
            .onChange(of: draftAscending) { _, _ in commit() }
        }
        .festivalSheet(.compact)
    }

    /// Apply the current choice immediately when the list can use it.
    private func commit() {
        guard isApplicable else { return }
        onApply(draftMode, draftAscending)
    }
}

/// Web-style direction control: the current direction described on the left, inline
/// ↑ / ↓ buttons on the right with a purple background behind the selected one
/// (`SortModal.tsx` direction row).
struct SortDirectionControl: View {
    @Binding var ascending: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Titled row with the description as a subtitle (operator batch 7).
            VStack(alignment: .leading, spacing: 2) {
                Text(ascending ? "Ascending" : "Descending")
                    .foregroundStyle(FestivalText.primary)
                Text(ascending ? "A–Z, low to high" : "Z–A, high to low")
                    .font(.footnote)
                    .foregroundStyle(FestivalText.primary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                button(up: true)
                button(up: false)
            }
            .padding(3)
            .background(BrandTokens.surfaceMuted, in: Capsule())
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.songs.sort.direction")
    }

    private func button(up: Bool) -> some View {
        let selected = ascending == up
        return Button {
            ascending = up
        } label: {
            Image(systemName: up ? "arrow.up" : "arrow.down")
                .font(.body.weight(.semibold))
                .foregroundStyle(selected ? FestivalText.primary : FestivalText.deemphasized)
                .frame(width: 44, height: 36)
                .background(selected ? BrandTokens.accentPurple : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(up ? "Ascending" : "Descending")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("fst.songs.sort.direction.\(up ? "ascending" : "descending")")
    }
}

/// Compact, announced refresh error that does not remove the current song list.
