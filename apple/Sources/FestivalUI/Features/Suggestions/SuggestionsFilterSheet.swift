import SwiftUI
import FestivalCore
import FestivalDesign

/// Live Suggestions filter (web `SuggestionsFilterModal`): per-instrument visibility, a
/// global toggle per `SuggestionCategoryType`, and a per-instrument override section.
///
/// Every toggle applies immediately (operator, 2026-09-28: no Cancel/Apply), so the list
/// behind the sheet updates as you go. Nothing is pending, so it dismisses with the shared
/// ``FestivalModal``'s system Close (issue #23; it was a text Done) and Reset sits at the
/// end of the Form.
struct SuggestionsFilterSheet: View {
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
        // Web: the instrument-specific selector opens with nothing chosen.
        _selectedInstrument = State(initialValue: nil)
    }

    /// The chosen instrument, only while it is still enabled in Settings.
    private var effectiveSelectedInstrument: Instrument? {
        guard let selectedInstrument, visibleInstruments.contains(selectedInstrument) else { return nil }
        return selectedInstrument
    }

    var body: some View {
        FestivalModal("Filter Suggestions", closeIdentifier: "fst.suggestions.filter.done") {
            Form {
                if !visibleInstruments.isEmpty {
                    Section {
                        ForEach(visibleInstruments) { instrument in
                            // Web `ToggleRow` with the instrument icon beside its name.
                            Toggle(isOn: instrumentBinding(instrument)) {
                                HStack(spacing: 12) {
                                    InstrumentIcon(instrument, size: 28)
                                        .accessibilityHidden(true)
                                    Text(instrument.label)
                                }
                            }
                                .accessibilityIdentifier(
                                    "fst.suggestions.filter.instrument.\(instrument.rawValue)"
                                )
                        }
                    } header: {
                        FestivalSectionHeader(
                            "Instruments",
                            subtitle: "Hide suggestions for specific charts. Only instruments enabled in Settings are listed."
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

                if !visibleInstruments.isEmpty {
                    Section {
                        // Web: the shared InstrumentSelector (deferred selection) over the
                        // Settings-enabled instruments; the chosen one's toggles expand.
                        InstrumentSelector(
                            instruments: visibleInstruments, selected: $selectedInstrument,
                            deferSelection: true, identifier: "fst.suggestions.filter.instrument-picker"
                        )
                        .padding(.vertical, 6)
                        if let instrument = effectiveSelectedInstrument {
                            ForEach(SuggestionCategoryType.allCases) { type in
                                Toggle(type.label, isOn: perInstrumentBinding(type, instrument))
                                    .accessibilityIdentifier(
                                        "fst.suggestions.filter.type.\(instrument.rawValue).\(type.rawValue)"
                                    )
                            }
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
        .festivalSheet(.large)
        .onChange(of: draft) { _, updated in onChange(updated) }
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
