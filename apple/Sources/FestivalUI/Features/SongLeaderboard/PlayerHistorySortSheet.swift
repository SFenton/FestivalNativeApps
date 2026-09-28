import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - PlayerHistorySortSheet

/// Native port of the web's `PlayerScoreSortModal`
/// (`FortniteFestivalWeb/src/pages/leaderboard/player/modals/PlayerScoreSortModal.tsx`):
/// sort mode (date/score/accuracy/season) and ascending/descending direction.
struct PlayerHistorySortSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draftMode: PlayerScoreSortMode
    @State private var draftAscending: Bool
    @State private var discardPending = false
    let mode: PlayerScoreSortMode
    let ascending: Bool
    let onApply: (PlayerScoreSortMode, Bool) -> Void

    /// Start from the currently applied sort.
    ///
    /// - Parameters:
    ///   - mode: Applied sort key.
    ///   - ascending: Applied direction.
    ///   - onApply: Commit both draft fields together after explicit confirmation.
    init(
        mode: PlayerScoreSortMode, ascending: Bool,
        onApply: @escaping (PlayerScoreSortMode, Bool) -> Void
    ) {
        self.mode = mode
        self.ascending = ascending
        self.onApply = onApply
        _draftMode = State(initialValue: mode)
        _draftAscending = State(initialValue: ascending)
    }

    private var hasChanges: Bool { draftMode != mode || draftAscending != ascending }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Mode", selection: $draftMode) {
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
                    Picker("Direction", selection: $draftAscending) {
                        Text("Ascending").tag(true)
                        Text("Descending").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("fst.history.sort.direction")
                } header: {
                    Text("Sort Direction")
                } footer: {
                    Text(draftAscending
                        ? "Ascending (oldest first, low-high)"
                        : "Descending (newest first, high-low)")
                }
                Section {
                    Button("Reset Sort Settings") {
                        draftMode = .score
                        draftAscending = false
                    }
                    .font(.body)
                    .tint(BrandTokens.textPrimary)
                    .accessibilityIdentifier("fst.history.sort.reset")
                }
            }
            .navigationTitle("Sort Player Scores")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            // Paired Cancel/Apply modal: `.cancellationAction` leading,
            // `.confirmationAction` trailing (app modal standard, operator
            // 2026-09-28) — replaces a custom `safeAreaInset` footer.
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { discardPending = true } else { dismiss() }
                    }
                    .accessibilityIdentifier("fst.history.sort.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(draftMode, draftAscending)
                        dismiss()
                    }
                    .disabled(!hasChanges)
                    .accessibilityIdentifier("fst.history.sort.apply")
                }
            }
        }
        // festivalSheet(.compact) is already applied by the presenting call site
        // (PlayerHistoryScreen.swift) — do not double-apply it here.
        .alert("Discard Sort Changes", isPresented: $discardPending) {
            Button("Continue Editing", role: .cancel) {}
            Button("Discard Changes", role: .destructive) { dismiss() }
        } message: {
            Text("Are you sure you want to discard your sort changes?")
        }
        .interactiveDismissDisabled()
    }
}
