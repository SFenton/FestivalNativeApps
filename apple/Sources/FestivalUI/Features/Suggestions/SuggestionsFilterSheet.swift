import SwiftUI
import FestivalCore
import FestivalDesign

/// Live Suggestions filter (web `SuggestionsFilterModal`): per-instrument visibility, a
/// global toggle per `SuggestionCategoryType`, and a per-instrument override section.
///
/// Every toggle applies immediately (operator, 2026-09-28: no Cancel/Apply), so the list
/// behind the sheet updates as you go; the standard `festivalSheet()` look carries one
/// trailing Done (`.confirmationAction`) and Reset sits at the end of the Form.
struct SuggestionsFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SuggestionFilterSettings
    @State private var selectedInstrument: Instrument?
    let visibleInstruments: [Instrument]
    let onChange: (SuggestionFilterSettings) -> Void

    /// Edit the saved filter live.
    ///
    /// - Parameters:
    ///   - applied: Currently saved filter.
    ///   - visibleInstruments: Settings-visible charts, in source order.
    ///   - onChange: Saves each change as it happens.
    init(
        applied: SuggestionFilterSettings, visibleInstruments: [Instrument],
        onChange: @escaping (SuggestionFilterSettings) -> Void
    ) {
        self.visibleInstruments = visibleInstruments
        self.onChange = onChange
        _draft = State(initialValue: applied)
        _selectedInstrument = State(initialValue: visibleInstruments.first)
    }

    private var effectiveSelectedInstrument: Instrument? {
        if let selectedInstrument, visibleInstruments.contains(selectedInstrument) {
            return selectedInstrument
        }
        return visibleInstruments.first
    }

    var body: some View {
        NavigationStack {
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
                                    .foregroundStyle(FestivalText.primary)
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
            .navigationTitle("Filter Suggestions")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("fst.suggestions.filter.done")
                }
            }
        }
        .festivalSheet(.large)
        .onChange(of: draft) { _, updated in onChange(updated) }
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
