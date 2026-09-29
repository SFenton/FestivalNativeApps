import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - PlayerHistorySortSheet

/// Native port of the web's `PlayerScoreSortModal`
/// (`FortniteFestivalWeb/src/pages/leaderboard/player/modals/PlayerScoreSortModal.tsx`):
/// sort mode (date/score/accuracy/season) and ascending/descending direction.
struct PlayerHistorySortSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mode: PlayerScoreSortMode
    @State private var ascending: Bool
    let onApply: (PlayerScoreSortMode, Bool) -> Void

    /// Start from the currently applied sort; every change applies immediately.
    ///
    /// - Parameters:
    ///   - mode: Applied sort key.
    ///   - ascending: Applied direction.
    ///   - onApply: Called with both fields on every change (live apply, operator
    ///     2026-09-28: no Cancel/Apply for this sheet).
    init(
        mode: PlayerScoreSortMode, ascending: Bool,
        onApply: @escaping (PlayerScoreSortMode, Bool) -> Void
    ) {
        self.onApply = onApply
        _mode = State(initialValue: mode)
        _ascending = State(initialValue: ascending)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(PlayerScoreSortMode.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    .pickerStyle(.inline)
                    .accessibilityIdentifier("fst.history.sort.mode")
                } header: {
                    Text("Mode")
                } footer: {
                    Text("Choose which property to sort your score history by.")
                }
                Section {
                    Picker("Direction", selection: $ascending) {
                        Text("Ascending").tag(true)
                        Text("Descending").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("fst.history.sort.direction")
                } header: {
                    Text("Sort Direction")
                } footer: {
                    Text(ascending
                        ? "Ascending (oldest first, low-high)"
                        : "Descending (newest first, high-low)")
                }
                Section {
                    Button("Reset Sort Settings") {
                        mode = .score
                        ascending = false
                    }
                    .font(.body)
                    .tint(FestivalText.primary)
                    .accessibilityIdentifier("fst.history.sort.reset")
                }
            }
            .navigationTitle("Sort Player Scores")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            // Live apply: changes take effect as they are made; one Done closes.
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("fst.history.sort.done")
                }
            }
            .onChange(of: mode) { _, newMode in onApply(newMode, ascending) }
            .onChange(of: ascending) { _, newAscending in onApply(mode, newAscending) }
        }
        // festivalSheet(.compact) is already applied by the presenting call site
        // (PlayerHistoryScreen.swift) — do not double-apply it here.
    }
}
