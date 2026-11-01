#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Filter sheet

/// The live Suggestions filter (``SuggestionsFilterSheet``): per-instrument visibility, a
/// global switch per ``SuggestionCategoryType`` and, under the instrument selector, one
/// switch per type for the chosen chart. Every switch applies at once (no Cancel or Apply),
/// Reset Filters sits at the end, and Close dismisses.
final class UKSuggestionsFilterViewController: UIViewController, UKModalScrollProviding {
    private var draft: SuggestionFilterSettings
    private let visibleInstruments: [Instrument]
    private let onChange: (SuggestionFilterSettings) -> Void
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var switches: [() -> Void] = []
    private let selectorHolder = UIView()
    private var selector: UKInstrumentSelectorView?

    var ukModalScrollView: UIScrollView? { scrollView }

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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrandUIColors.appBackground
        scrollView.alwaysBounceVertical = true
        scrollView.accessibilityIdentifier = "fst.suggestions.filter.form"
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.ukPin(to: view)
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
        ])
        build()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        installSelector()
    }

    /// Builds the instrument selector once the sheet has a width, choosing the arrow layout from it
    /// (the shared selector measures its own width only after layout).
    private func installSelector() {
        guard selector == nil, !visibleInstruments.isEmpty, view.bounds.width > 0 else { return }
        let width = view.bounds.width - 64
        let compact = InstrumentSelection(instruments: visibleInstruments, required: false, deferSelection: true).needsCompact(
            width: Double(width), buttonWidth: Double(InstrumentSelectorMetrics.buttonSize), gap: Double(InstrumentSelectorMetrics.gap)
        )
        let view = UKInstrumentSelectorView(
            instruments: visibleInstruments, selected: nil, compact: compact, deferSelection: true,
            identifier: "fst.suggestions.filter.instrument-picker",
            panel: { [weak self] instrument in self?.perInstrumentToggles(instrument) ?? UIView() }
        )
        view.onSelect = { [weak view] choice in view?.selected = choice }
        view.translatesAutoresizingMaskIntoConstraints = false
        selectorHolder.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: selectorHolder.leadingAnchor, constant: 16),
            view.trailingAnchor.constraint(equalTo: selectorHolder.trailingAnchor, constant: -16),
            view.topAnchor.constraint(equalTo: selectorHolder.topAnchor, constant: 6),
            view.bottomAnchor.constraint(equalTo: selectorHolder.bottomAnchor, constant: -6),
        ])
        selector = view
    }

    // MARK: Draft

    private func update(_ change: (inout SuggestionFilterSettings) -> Void) {
        change(&draft)
        onChange(draft)
        switches.forEach { $0() }
    }

    // MARK: Build

    private func build() {
        if !visibleInstruments.isEmpty {
            let rows = visibleInstruments.map { instrument in
                toggleRow(
                    title: instrument.label, identifier: "fst.suggestions.filter.instrument.\(instrument.rawValue)",
                    icon: instrument, isOn: { [weak self] in self?.draft.isInstrumentEnabled(instrument) ?? true }
                ) { [weak self] on in self?.update { $0.setInstrumentEnabled(instrument, enabled: on) } }
            }
            stack.addArrangedSubview(section(
                "Instruments", subtitle: "Hide suggestions for specific charts. Only instruments enabled in Settings are listed.", rows: rows
            ))
        }
        let generalRows = SuggestionCategoryType.allCases.map { type in
            toggleRow(
                title: type.label, detail: type.filterDescription, identifier: "fst.suggestions.filter.type.\(type.rawValue)",
                isOn: { [weak self] in self?.draft.isGlobalEnabled(type) ?? true }
            ) { [weak self] on in
                guard let self else { return }
                self.update { $0.setGlobalType(type, enabled: on, instruments: self.visibleInstruments) }
            }
        }
        stack.addArrangedSubview(section("General", subtitle: "Turn whole suggestion categories on or off.", rows: generalRows))
        if !visibleInstruments.isEmpty {
            stack.addArrangedSubview(section("Instrument-Specific", subtitle: "Fine-tune one chart at a time.", rows: [selectorHolder]))
        }
        var reset = UIButton.Configuration.plain()
        reset.title = "Reset Filters"
        reset.baseForegroundColor = BrandUIColors.textPrimary
        let resetButton = UIButton(configuration: reset)
        resetButton.contentHorizontalAlignment = .leading
        resetButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        resetButton.accessibilityIdentifier = "fst.suggestions.filter.reset"
        resetButton.addAction(UIAction { [weak self] _ in self?.update { $0.reset() } }, for: .primaryActionTriggered)
        stack.addArrangedSubview(section(nil, subtitle: nil, rows: [resetButton]))
    }

    private func perInstrumentToggles(_ instrument: Instrument) -> UIView {
        let rows = SuggestionCategoryType.allCases.map { type in
            toggleRow(
                title: type.label, identifier: "fst.suggestions.filter.type.\(instrument.rawValue).\(type.rawValue)",
                isOn: { [weak self] in self?.draft.isTypeEnabled(type, instrument: instrument) ?? true }
            ) { [weak self] on in
                guard let self else { return }
                self.update { $0.setPerInstrumentType(type, instrument: instrument, enabled: on, allInstruments: self.visibleInstruments) }
            }
        }
        let column = UIStackView()
        column.axis = .vertical
        for (index, row) in rows.enumerated() {
            if index == 0 { column.addArrangedSubview(UKHairlineView()) }
            column.addArrangedSubview(row)
            if index < rows.count - 1 { column.addArrangedSubview(UKHairlineView(leadingInset: 16)) }
        }
        return column
    }

    // MARK: Pieces

    private func section(_ title: String?, subtitle: String?, rows: [UIView]) -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        card.layer.cornerRadius = 10
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        let list = UIStackView()
        list.axis = .vertical
        for (index, row) in rows.enumerated() {
            if index > 0 { list.addArrangedSubview(UKHairlineView(leadingInset: 16)) }
            list.addArrangedSubview(row)
        }
        list.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(list)
        list.ukPin(to: card)
        var views: [UIView] = []
        if let title { views.append(UKSectionHeaderView(title, subtitle: subtitle).ukPadded(horizontal: 4)) }
        views.append(card)
        let outer = UIStackView(arrangedSubviews: views)
        outer.axis = .vertical
        outer.spacing = 8
        return outer
    }

    private func toggleRow(
        title: String, detail: String? = nil, identifier: String, icon: Instrument? = nil,
        isOn: @escaping () -> Bool, onToggle: @escaping (Bool) -> Void
    ) -> UIView {
        let toggle = UKRowSwitch()
        toggle.isOn = isOn()
        toggle.accessibilityLabel = title
        toggle.accessibilityIdentifier = identifier
        toggle.onTintColor = BrandUIColors.statusGreen
        toggle.addAction(UIAction { [weak toggle] _ in onToggle(toggle?.isOn ?? false) }, for: .valueChanged)
        switches.append { [weak toggle] in
            let value = isOn()
            if toggle?.isOn != value { toggle?.setOn(value, animated: true) }
        }
        let text = UIStackView(arrangedSubviews: [UKLabel(title, style: .body)])
        text.axis = .vertical
        text.spacing = 2
        if let detail { text.addArrangedSubview(UKLabel(detail, style: .caption1)) }
        var leading: [UIView] = []
        if let icon { leading.append(UKInstrumentIconView(icon, size: 28, hidesFromAccessibility: true)) }
        let row = UIStackView(arrangedSubviews: leading + [text, toggle])
        row.spacing = 12
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        // The whole row is the switch's target, as a SwiftUI `Toggle` row is.
        toggle.row = row
        row.addGestureRecognizer(UITapGestureRecognizer(target: toggle, action: #selector(UKRowSwitch.flip)))
        return row
    }
}
#endif
