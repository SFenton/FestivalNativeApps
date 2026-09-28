import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - PlayerHistorySortSheet

/// Native port of the web's `PlayerScoreSortModal`
/// (`FortniteFestivalWeb/src/pages/leaderboard/player/modals/PlayerScoreSortModal.tsx`):
/// sort mode (date/score/accuracy/season) and ascending/descending direction.
struct PlayerHistorySortSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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

    private var actionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
    }

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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionLayout {
                    Button {
                        if hasChanges { discardPending = true } else { dismiss() }
                    } label: {
                        Text("Cancel")
                            .font(.body)
                            .foregroundStyle(BrandTokens.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                BrandTokens.cardBackground, in: RoundedRectangle(cornerRadius: 10)
                            )
                    }
                    .buttonStyle(HighContrastPagerStyle())
                    .accessibilityIdentifier("fst.history.sort.cancel")
                    Button {
                        onApply(draftMode, draftAscending)
                        dismiss()
                    } label: {
                        Text("Apply Sort Changes")
                            .font(.body.bold())
                            .foregroundStyle(
                                hasChanges ? BrandTokens.textPrimary : BrandTokens.textSecondary
                            )
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                BrandTokens.cardBackground, in: RoundedRectangle(cornerRadius: 10)
                            )
                    }
                    .buttonStyle(HighContrastPagerStyle())
                    .disabled(!hasChanges)
                    .accessibilityIdentifier("fst.history.sort.apply")
                }
                .padding(12)
                .background(BrandTokens.cardBackground)
            }
        }
        .alert("Discard Sort Changes", isPresented: $discardPending) {
            Button("Continue Editing", role: .cancel) {}
            Button("Discard Changes", role: .destructive) { dismiss() }
        } message: {
            Text("Are you sure you want to discard your sort changes?")
        }
        .interactiveDismissDisabled()
    }
}
