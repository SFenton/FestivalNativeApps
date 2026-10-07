import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - PlayerHistorySortSheet

/// Score History's sort choices, the native port of the web's `PlayerScoreSortModal`
/// (`FortniteFestivalWeb/src/pages/leaderboard/player/modals/PlayerScoreSortModal.tsx`):
/// mode (Date, Score, Accuracy, Season) and direction, default Score descending.
///
/// Built like ``SongsSortSheet`` (modal-shell): the shared ``FestivalModal`` with its
/// system Close, changes applied as they are made (operator, 2026-09-28: no
/// Cancel/Apply), the shared ``SortDirectionControl`` and a red Reset.
struct PlayerHistorySortSheet: View {
    @State private var draftMode: PlayerScoreSortMode
    @State private var draftAscending: Bool
    let onApply: (PlayerScoreSortMode, Bool) -> Void

    /// Start from the applied sort.
    ///
    /// - Parameters:
    ///   - mode: Applied sort key.
    ///   - ascending: Applied direction.
    ///   - onApply: Commits the mode and direction; called on every change.
    init(
        mode: PlayerScoreSortMode, ascending: Bool,
        onApply: @escaping (PlayerScoreSortMode, Bool) -> Void
    ) {
        self.onApply = onApply
        _draftMode = State(initialValue: mode)
        _draftAscending = State(initialValue: ascending)
    }

    var body: some View {
        FestivalModal("Sort Player Scores", closeIdentifier: "fst.history.sort.close") {
            Form {
                Section {
                    Picker("Mode", selection: $draftMode) {
                        ForEach(PlayerScoreSortMode.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    .pickerStyle(.inline)
                    // The section header already says "Mode": no extra label row.
                    .labelsHidden()
                    .accessibilityIdentifier("fst.history.sort.mode")
                } header: {
                    FestivalSectionHeader(
                        "Mode", subtitle: "Choose which property to sort your score history by."
                    )
                }
                Section {
                    SortDirectionControl(
                        ascending: $draftAscending, identifier: "fst.history.sort.direction",
                        ascendingDetail: "Oldest first, low to high",
                        descendingDetail: "Newest first, high to low"
                    )
                } header: {
                    FestivalSectionHeader("Sort Direction")
                }
                Section {
                    // Reset is red in every filter and sort sheet (operator batch 7).
                    Button("Reset Sort Settings", role: .destructive) {
                        draftMode = PlayerScoreHistorySort.defaultMode
                        draftAscending = PlayerScoreHistorySort.defaultAscending
                    }
                    .font(.body)
                    .foregroundStyle(FestivalSheetActionColor.destructive)
                    .accessibilityIdentifier("fst.history.sort.reset")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: draftMode) { _, mode in onApply(mode, draftAscending) }
            .onChange(of: draftAscending) { _, ascending in onApply(draftMode, ascending) }
        }
        .festivalSheet(.compact)
    }
}
