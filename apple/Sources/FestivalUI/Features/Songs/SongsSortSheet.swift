import Foundation
import SwiftUI
import FestivalCore
import FestivalDesign

/// The catalogue Sort sheet (pattern `catalogue-sort` R1): Songs and the Item Shop
/// (issue #379) each pass their own modes and identifier. Changes apply as they are made
/// (operator, 2026-09-28: no Cancel/Apply); the shared ``FestivalModal``'s system Close
/// dismisses it.
struct SongsSortSheet: View {
    @State private var draftMode: SongSortMode
    @State private var draftAscending: Bool
    let mode: SongSortMode
    let ascending: Bool
    let showShop: Bool
    let shopAvailable: Bool
    /// Selected-player sorts offered for the one Songs instrument (empty hides them).
    let playerModes: [SongSortMode]
    /// Catalogue modes in sheet order (Songs: ``SongSortMode/catalogueModes``; Item Shop:
    /// ``ShopSortChoice/modes``).
    let modes: [SongSortMode]
    /// Identifier prefix of the sheet's controls (`fst.songs.sort`, `fst.shop.sort`).
    let identifier: String
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
    ///   - modes: Catalogue modes the page offers, in order.
    ///   - identifier: Prefix of the sheet's accessibility identifiers.
    ///   - onApply: Commits the mode and direction; called on every change.
    init(
        mode: SongSortMode, ascending: Bool,
        showShop: Bool = false, shopAvailable: Bool = false,
        playerModes: [SongSortMode] = [],
        modes: [SongSortMode] = SongSortMode.catalogueModes,
        identifier: String = "fst.songs.sort",
        onApply: @escaping (SongSortMode, Bool) -> Void
    ) {
        self.mode = mode
        self.ascending = ascending
        self.showShop = showShop
        self.shopAvailable = shopAvailable
        self.playerModes = playerModes
        self.modes = modes
        self.identifier = identifier
        self.onApply = onApply
        _draftMode = State(initialValue: mode)
        _draftAscending = State(initialValue: ascending)
    }

    /// A choice the list can actually use (Item Shop needs a visible, loaded feed).
    private var isApplicable: Bool {
        if draftMode.isPlayerChartMode { return playerModes.contains(draftMode) }
        guard modes.contains(draftMode) else { return false }
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
        FestivalModal("Sort By", closeIdentifier: "\(identifier).done") {
            Form {
                Section {
                    Picker("Sort By", selection: modeBinding(player: false)) {
                        ForEach(modes.filter {
                            showShop || $0 != .shop
                        }) { choice in
                            Text(choice.label).tag(SongSortMode?.some(choice))
                                .disabled(choice == .shop && !shopAvailable)
                        }
                    }
                    .pickerStyle(.inline)
                    // The section header already says "Sort Mode": no extra label row.
                    .labelsHidden()
                    .accessibilityIdentifier("\(identifier).mode")
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
                        .accessibilityIdentifier("\(identifier).player-mode")
                    } header: {
                        FestivalSectionHeader(
                            "Filtered Instrument Sort Mode",
                            subtitle: "Filtering to a single instrument enables more sort options."
                        )
                    }
                }
                Section {
                    SortDirectionControl(
                        ascending: $draftAscending, identifier: "\(identifier).direction"
                    )
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
                    .accessibilityIdentifier("\(identifier).reset")
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

extension View {
    /// Present a catalogue Sort sheet the Mac way: a popover from its toolbar button
    /// (HIG Popovers: "Limit a popover to a little information or functionality"), its
    /// own chrome, closing on an outside click. iPhone and iPad present the sheet with
    /// `.sheet` instead (HIG Popovers: "Avoid popovers in compact views"), so this is a
    /// no-op there.
    ///
    /// - Parameters:
    ///   - isPresented: The page's Sort presentation state.
    ///   - sheet: The page's ``SongsSortSheet``.
    /// - Returns: The button with the Mac popover attached.
    @ViewBuilder
    func catalogueSortPopover<Sheet: View>(
        isPresented: Binding<Bool>, @ViewBuilder sheet: @escaping () -> Sheet
    ) -> some View {
        #if os(macOS)
        popover(isPresented: isPresented, arrowEdge: .bottom) {
            // No modal stack, title bar or Close (which would otherwise join the
            // window toolbar).
            sheet()
                .environment(\.festivalModalPreview, true)
                .formStyle(.grouped)
                .frame(width: 340, height: 470)
        }
        #else
        self
        #endif
    }
}

/// Web-style direction control: the current direction described on the left, inline
/// ↑ / ↓ buttons on the right with a purple background behind the selected one
/// (`SortModal.tsx` direction row). Shared by every sort sheet (Songs, Score History).
struct SortDirectionControl: View {
    @Binding var ascending: Bool
    /// Identifier of the control; its buttons append `.ascending` / `.descending`.
    var identifier = "fst.songs.sort.direction"
    /// Subtitle for ascending (the sheet's own web copy).
    var ascendingDetail = "A–Z, low to high"
    /// Subtitle for descending.
    var descendingDetail = "Z–A, high to low"

    var body: some View {
        HStack(spacing: 12) {
            // Titled row with the description as a subtitle (operator batch 7).
            VStack(alignment: .leading, spacing: 2) {
                Text(ascending ? "Ascending" : "Descending")
                    .foregroundStyle(FestivalText.primary)
                Text(ascending ? ascendingDetail : descendingDetail)
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
        .accessibilityIdentifier(identifier)
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
        .accessibilityIdentifier("\(identifier).\(up ? "ascending" : "descending")")
    }
}

/// Compact, announced refresh error that does not remove the current song list.
