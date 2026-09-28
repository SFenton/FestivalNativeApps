import SwiftUI
import FestivalCore
import FestivalDesign

/// Native staged draft for the Suggestions filter (web `SuggestionsFilterModal`):
/// per-instrument visibility, a global toggle per `SuggestionCategoryType`, and a
/// per-instrument override section. Applies atomically on "Apply"; "Cancel" with
/// unsaved changes confirms before discarding. Cancel/Apply are semantic
/// `.cancellationAction`/`.confirmationAction` toolbar items (app modal standard),
/// not a custom footer.
struct SuggestionsFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SuggestionFilterSettings
    @State private var selectedInstrument: Instrument?
    @State private var discardPending = false
    let applied: SuggestionFilterSettings
    let visibleInstruments: [Instrument]
    let onApply: (SuggestionFilterSettings) -> Void

    /// Stage a copy of the saved filter until Apply.
    ///
    /// - Parameters:
    ///   - applied: Currently saved filter draft.
    ///   - visibleInstruments: Settings-visible charts, in source order.
    ///   - onApply: Commit the staged draft; the sheet dismisses itself after.
    init(
        applied: SuggestionFilterSettings, visibleInstruments: [Instrument],
        onApply: @escaping (SuggestionFilterSettings) -> Void
    ) {
        self.applied = applied
        self.visibleInstruments = visibleInstruments
        self.onApply = onApply
        _draft = State(initialValue: applied)
        _selectedInstrument = State(initialValue: visibleInstruments.first)
    }

    private var hasChanges: Bool { draft != applied }

    private var effectiveSelectedInstrument: Instrument? {
        if let selectedInstrument, visibleInstruments.contains(selectedInstrument) {
            return selectedInstrument
        }
        return visibleInstruments.first
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Filter Suggestions")
                    .font(.title2.bold())
                    .foregroundStyle(BrandTokens.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.vertical, 8)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("fst.suggestions.filter.title")
                Form {
                    if !visibleInstruments.isEmpty {
                        Section {
                            ForEach(visibleInstruments) { instrument in
                                Toggle(instrument.label, isOn: instrumentBinding(instrument))
                                    .accessibilityIdentifier(
                                        "fst.suggestions.filter.instrument.\(instrument.rawValue)"
                                    )
                            }
                        } header: {
                            FestivalSectionHeader(
                                "Instruments", subtitle: "Hide suggestions for specific charts."
                            )
                        }
                        .listRowBackground(Color.white.opacity(0.06))
                    }

                    Section {
                        ForEach(SuggestionCategoryType.allCases) { type in
                            Toggle(isOn: globalBinding(type)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(type.label)
                                    Text(type.filterDescription)
                                        .font(.caption)
                                        .foregroundStyle(BrandTokens.textSecondary)
                                }
                            }
                            .accessibilityIdentifier("fst.suggestions.filter.type.\(type.rawValue)")
                        }
                    } header: {
                        FestivalSectionHeader("General", subtitle: "Turn whole suggestion categories on or off.")
                    }
                    .listRowBackground(Color.white.opacity(0.06))

                    if let instrument = effectiveSelectedInstrument {
                        Section {
                            Picker("Instrument", selection: instrumentPickerBinding) {
                                ForEach(visibleInstruments) { choice in
                                    Text(choice.label).tag(Instrument?.some(choice))
                                }
                            }
                            .pickerStyle(.menu)
                            .accessibilityIdentifier("fst.suggestions.filter.instrument-picker")
                            ForEach(SuggestionCategoryType.allCases) { type in
                                Toggle(type.label, isOn: perInstrumentBinding(type, instrument))
                                    .accessibilityIdentifier(
                                        "fst.suggestions.filter.type.\(instrument.rawValue).\(type.rawValue)"
                                    )
                            }
                        } header: {
                            FestivalSectionHeader(
                                "Instrument-Specific", subtitle: "Fine-tune one chart at a time."
                            )
                        }
                        .listRowBackground(Color.white.opacity(0.06))
                    }

                    Section {
                        Button("Reset Filters") { draft.reset() }
                            .tint(BrandTokens.textPrimary)
                            .accessibilityIdentifier("fst.suggestions.filter.reset")
                    }
                }
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("fst.suggestions.filter.form")
            }
            // Paired Cancel/Apply modal: `.cancellationAction` leading,
            // `.confirmationAction` trailing (app modal standard, operator
            // 2026-09-28) — replaces a custom `safeAreaInset` footer, matching
            // `PlayerHistorySortSheet`. The in-content title `Text` above stays
            // (it carries `fst.suggestions.filter.title`, asserted by
            // `SuggestionsJourneyTests`), so the navigation bar itself shows
            // only these two actions with no title.
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { discardPending = true } else { dismiss() }
                    }
                    .accessibilityIdentifier("fst.suggestions.filter.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(draft)
                        dismiss()
                    }
                    .disabled(!hasChanges)
                    .accessibilityIdentifier("fst.suggestions.filter.apply")
                }
            }
        }
        .festivalSheet(.large)
        .alert("Discard filter changes?", isPresented: $discardPending) {
            Button("Continue Editing", role: .cancel) {}
            Button("Discard Changes", role: .destructive) { dismiss() }
        } message: {
            Text("Suggestions will keep their current filters.")
        }
        .interactiveDismissDisabled()
    }

    private var instrumentPickerBinding: Binding<Instrument?> {
        Binding(get: { effectiveSelectedInstrument }, set: { selectedInstrument = $0 })
    }

    private func instrumentBinding(_ instrument: Instrument) -> Binding<Bool> {
        Binding(
            get: { draft.isInstrumentEnabled(instrument) },
            set: { draft.setInstrumentEnabled(instrument, enabled: $0) }
        )
    }

    private func globalBinding(_ type: SuggestionCategoryType) -> Binding<Bool> {
        Binding(
            get: { draft.isGlobalEnabled(type) },
            set: { draft.setGlobalType(type, enabled: $0, instruments: visibleInstruments) }
        )
    }

    private func perInstrumentBinding(_ type: SuggestionCategoryType, _ instrument: Instrument) -> Binding<Bool> {
        Binding(
            get: { draft.isTypeEnabled(type, instrument: instrument) },
            set: { draft.setPerInstrumentType(type, instrument: instrument, enabled: $0, allInstruments: visibleInstruments) }
        )
    }
}
