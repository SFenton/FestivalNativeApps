#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Filter sheet

/// The live Suggestions filter (``SuggestionsFilterSheet``): per-instrument visibility,
/// global category switches, and the selected chart's overrides.
final class UKSuggestionsFilterViewController: UKFormViewController {
    private static let categoryFill = UIColor.white.withAlphaComponent(0.06)
    private var draft: SuggestionFilterSettings
    private let visibleInstruments: [Instrument]
    private let onChange: (SuggestionFilterSettings) -> Void
    private lazy var instrumentAccordion = UKAccordionView<Instrument> { [weak self] instrument in
        self?.perInstrumentToggles(instrument) ?? UIView()
    }
    private var instrumentPanels: [Instrument: UIView] = [:]

    /// Creates the sheet's page.
    ///
    /// - Parameters:
    ///   - applied: The currently saved filter.
    ///   - visibleInstruments: Settings-visible charts, in source order.
    ///   - onChange: Saves each change as it happens.
    init(applied: SuggestionFilterSettings, visibleInstruments: [Instrument], onChange: @escaping (SuggestionFilterSettings) -> Void) {
        draft = applied
        self.visibleInstruments = visibleInstruments
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func build() {
        scroll.accessibilityIdentifier = "fst.suggestions.filter.form"
        if !visibleInstruments.isEmpty {
            let instrumentRows = visibleInstruments.map { instrument in
                let icon = UKInstrumentIconView(instrument, size: 28, hidesFromAccessibility: true)
                let label = UIStackView(arrangedSubviews: [icon, UKLabel(instrument.label, usesSwiftUILeading: true)])
                label.alignment = .center
                label.spacing = 12
                return toggleRow(
                    instrument.label, identifier: "fst.suggestions.filter.instrument.\(instrument.rawValue)",
                    visual: paddedLabel(label),
                    isOn: { [unowned self] in draft.isInstrumentEnabled(instrument) }
                ) { [unowned self] enabled in update { $0.setInstrumentEnabled(instrument, enabled: enabled) } }
            }
            addSection(
                "Instruments", subtitle: "Hide suggestions for specific charts. Only instruments enabled in Settings are listed.",
                rows: instrumentRows, fill: Self.categoryFill
            )
        }
        let generalRows = SuggestionCategoryType.allCases.map { type in
            let label = UIStackView(arrangedSubviews: [
                UKLabel(type.label, wrapsToLayoutWidth: true),
                UKLabel(type.filterDescription, style: .caption1, wrapsToLayoutWidth: true),
            ])
            label.axis = .vertical
            label.spacing = 2
            return toggleRow(
                type.label, identifier: "fst.suggestions.filter.type.\(type.rawValue)",
                visual: paddedLabel(label), accessibilityLabel: "\(type.label), \(type.filterDescription)",
                isOn: { [unowned self] in draft.isGlobalEnabled(type) }
            ) { [unowned self] enabled in
                update { $0.setGlobalType(type, enabled: enabled, instruments: visibleInstruments) }
            }
        }
        addSection("General", subtitle: "Turn whole suggestion categories on or off.", rows: generalRows, fill: Self.categoryFill)
        if !visibleInstruments.isEmpty { addInstrumentSelector() }
        let reset = buttonRow("Reset Filters", color: BrandUIColors.textPrimary, identifier: "fst.suggestions.filter.reset") {
            [unowned self] in update { $0.reset() }
        }
        addSection(rows: [reset])
    }

    private func update(_ change: (inout SuggestionFilterSettings) -> Void) {
        change(&draft)
        onChange(draft)
    }

    private func paddedLabel(_ label: UIView) -> UIView {
        UKGroupSectionView.paddedRow(label, horizontal: 0, vertical: UKGroupSectionView.formTextPadding, minimumHeight: 0)
    }

    private func addInstrumentSelector() {
        let selector = UKInstrumentSelectorView(
            instruments: visibleInstruments, selected: nil, deferSelection: true,
            identifier: "fst.suggestions.filter.instrument-picker"
        )
        selector.onSelect = { [weak self] in self?.instrumentAccordion.follow($0) }
        let selectorRow = UKGroupSectionView.formRow(paddedLabel(selector), vertical: 10)
        let content = UIStackView(arrangedSubviews: [selectorRow, instrumentAccordion])
        content.axis = .vertical
        let section = UKGroupSectionView(
            "Instrument-Specific", subtitle: "Fine-tune one chart at a time.",
            rows: .flush(separatorInset: 0), surface: .form, formFill: Self.categoryFill
        )
        section.setRows([content])
        appendSection(section, titled: true)
    }

    private func perInstrumentToggles(_ instrument: Instrument) -> UIView {
        if let panel = instrumentPanels[instrument] { return panel }
        let rows = SuggestionCategoryType.allCases.map { type in
            toggleRow(
                type.label, identifier: "fst.suggestions.filter.type.\(instrument.rawValue).\(type.rawValue)",
                isOn: { [unowned self] in draft.isTypeEnabled(type, instrument: instrument) }
            ) { [unowned self] enabled in
                update { $0.setPerInstrumentType(type, instrument: instrument, enabled: enabled, allInstruments: visibleInstruments) }
            }
        }
        let panel = UIStackView(arrangedSubviews: UKGroupSectionView.formRows(rows, startsWithSeparator: true))
        panel.axis = .vertical
        instrumentPanels[instrument] = panel
        return panel
    }
}
#endif
