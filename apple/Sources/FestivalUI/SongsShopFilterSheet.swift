import SwiftUI
import FestivalCore
import FestivalDesign

/// Native draft for the two public Item Shop conditions in the source Songs Filter.
struct SongsShopFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var draftInShop: Bool
    @State private var draftLeavingTomorrow: Bool
    @State private var discardPending = false
    let applied: SongShopFilter
    let showShop: Bool
    let shopAvailable: Bool
    let profileAvailable: Bool
    let onApply: (SongShopFilter) -> Void

    /// Stage each toggle without changing Songs until Apply.
    ///
    /// - Parameters:
    ///   - applied: Saved native Shop filters.
    ///   - showShop: Whether Settings exposes the Shop feature.
    ///   - shopAvailable: Whether a validated Shop feed is retained.
    ///   - profileAvailable: Whether a selected player's scores are available.
    ///   - onApply: Commit both toggles together after explicit confirmation.
    init(
        applied: SongShopFilter, showShop: Bool, shopAvailable: Bool,
        profileAvailable: Bool, onApply: @escaping (SongShopFilter) -> Void
    ) {
        self.applied = applied
        self.showShop = showShop
        self.shopAvailable = shopAvailable
        self.profileAvailable = profileAvailable
        self.onApply = onApply
        _draftInShop = State(initialValue: applied.inShop)
        _draftLeavingTomorrow = State(initialValue: applied.leavingTomorrow)
    }

    private var draft: SongShopFilter {
        SongShopFilter(inShop: draftInShop, leavingTomorrow: draftLeavingTomorrow)
    }

    private var hasChanges: Bool { draft != applied }

    private var canEnable: Bool {
        showShop && shopAvailable && profileAvailable
    }

    private var actionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item Shop") {
                    Toggle("In Shop", isOn: $draftInShop)
                        .disabled(!canEnable)
                        .accessibilityHint("Show songs in the validated public Item Shop")
                        .accessibilityIdentifier("fst.songs.filter.in-shop")
                    Toggle("Leaving Tomorrow", isOn: $draftLeavingTomorrow)
                        .disabled(!canEnable)
                        .accessibilityHint("Show validated offers leaving tomorrow")
                        .accessibilityIdentifier("fst.songs.filter.leaving")
                    if !showShop {
                        Text("Item Shop is hidden in Settings. Saved filters can be reset.")
                            .foregroundStyle(BrandTokens.textSecondary)
                    } else if !profileAvailable {
                        Text("Select a player with available scores to edit song filters.")
                            .foregroundStyle(BrandTokens.textSecondary)
                    } else if !shopAvailable {
                        Text("Item Shop filters need matching public Songs and Shop data.")
                            .foregroundStyle(BrandTokens.textSecondary)
                    }
                }
                Section {
                    Button("Reset Shop filters") {
                        draftInShop = false
                        draftLeavingTomorrow = false
                    }
                    .tint(BrandTokens.textPrimary)
                    .accessibilityIdentifier("fst.songs.filter.reset")
                }
            }
            .navigationTitle("Filter Songs")
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
                    .accessibilityIdentifier("fst.songs.filter.cancel")
                    Button {
                        onApply(draft)
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
                    .disabled(!hasChanges || (draft.isActive && !canEnable))
                    .accessibilityIdentifier("fst.songs.filter.apply")
                }
                .padding(12)
                .background(BrandTokens.cardBackground)
            }
        }
        .alert("Discard filter changes?", isPresented: $discardPending) {
            Button("Continue Editing", role: .cancel) {}
            Button("Discard Changes", role: .destructive) { dismiss() }
        } message: {
            Text("The song list will keep its current filters.")
        }
        .interactiveDismissDisabled()
    }
}
