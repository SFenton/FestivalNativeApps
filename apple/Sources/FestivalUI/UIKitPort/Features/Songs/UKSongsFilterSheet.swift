#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Filter sheet

/// The Filter Songs sheet (``SongsFilterSheet``): General filters for everyone, the player
/// Score and FC checks, the Instrument choice and, for one instrument, the Season,
/// Percentile, Stars and Intensity buckets. Each change applies at once.
final class UKSongsFilterSheetController: UKFormViewController {
    struct Inputs {
        var appliedGeneral: SongGeneralFilter
        var showShop: Bool
        var shopAvailable: Bool
        var availableDecades: [Int]
        var availableDurations: [Int]
        var appliedPlayerFilter: SongPlayerScoreFilter
        var appliedInstrument: Instrument?
        var visibleInstruments: Set<Instrument>
        var selectedPlayer: Bool
        var scoreAvailable: Bool
        var invalidScoreFilteringEnabled: Bool
        var availableSeasons: [Int]
    }

    private let inputs: Inputs
    private var draftGeneral: SongGeneralFilter
    private var draftPlayerFilter: SongPlayerScoreFilter
    private var draftInstrument: Instrument?
    private var committed: ChoiceKey
    private let availableDecades: [Int]
    private let availableDurations: [Int]
    private let onApply: (SongGeneralFilter, SongPlayerScoreFilter, Instrument?) throws -> Void
    private var errorLabel: UILabel?
    private var buckets: UKAccordionView<Instrument>?

    private struct ChoiceKey: Equatable {
        let general: SongGeneralFilter
        let player: SongPlayerScoreFilter
        let instrument: Instrument?
    }

    private var canEnableScores: Bool { inputs.selectedPlayer && inputs.scoreAvailable }

    /// Creates the sheet.
    init(_ inputs: Inputs, onApply: @escaping (SongGeneralFilter, SongPlayerScoreFilter, Instrument?) throws -> Void) {
        var inputs = inputs
        inputs.appliedPlayerFilter = inputs.appliedPlayerFilter.scoped(to: inputs.visibleInstruments)
        self.inputs = inputs
        availableDecades = Array(Set(inputs.availableDecades).union(inputs.appliedGeneral.excludedDecades)).sorted()
        availableDurations = Array(Set(inputs.availableDurations).union(inputs.appliedGeneral.excludedDurations)).sorted()
        draftGeneral = inputs.appliedGeneral
        draftPlayerFilter = inputs.appliedPlayerFilter
        draftInstrument = inputs.appliedInstrument
        committed = ChoiceKey(general: inputs.appliedGeneral, player: inputs.appliedPlayerFilter, instrument: inputs.appliedInstrument)
        self.onApply = onApply
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func refresh() {
        super.refresh()
        buckets?.follow(inputs.selectedPlayer ? draftInstrument : nil)
        let key = ChoiceKey(general: draftGeneral, player: draftPlayerFilter, instrument: draftInstrument)
        guard key != committed else { return }
        committed = key
        do {
            try onApply(draftGeneral, draftPlayerFilter, draftInstrument)
            errorLabel?.text = nil
            errorLabel?.superview?.isHidden = true
        } catch {
            errorLabel?.text = "Could not save filters: \(error.localizedDescription)"
            errorLabel?.superview?.isHidden = false
        }
    }

    // MARK: Build

    override func build() {
        let intro = UKLabel("General filters that apply to all songs.", style: .footnote)
        addSection("General", titleIdentifier: "fst.songs.filter.general", rows: [intro])
        bucketSection(
            id: "year", title: "Year", hint: "Filter songs by their release decade.", keys: availableDecades,
            label: SongGeneralFilter.decadeLabel, excluded: \.excludedDecades
        )
        bucketSection(
            id: "duration", title: "Duration", hint: "Filter songs by their duration.", keys: availableDurations,
            label: SongGeneralFilter.durationLabel, excluded: \.excludedDurations
        )
        if inputs.showShop { addShopSection() }
        addDoubleBassSection()
        if inputs.selectedPlayer {
            addScoreSections()
            addInstrumentSection()
        }
        addBucketAccordion()
        let reset = buttonRow("Reset Filters", color: Self.destructive, identifier: "fst.songs.filter.reset") { [unowned self] in
            draftGeneral = SongGeneralFilter()
            draftPlayerFilter = SongPlayerScoreFilter()
            draftInstrument = nil
        }
        addSection(rows: [reset])
        let error = UKLabel(color: BrandUIColors.gold)
        error.accessibilityIdentifier = "fst.songs.filter.save-error"
        errorLabel = error
        let section = addSection(rows: [error])
        section.isHidden = true
        scroll.accessibilityIdentifier = "fst.songs.filter.form"
    }

    private func label(_ title: String, hint: String, identifier: String) -> UIView {
        let titleLabel = UKLabel(title)
        let hintLabel = UKLabel(hint, style: .footnote)
        let stack = UIStackView(arrangedSubviews: [titleLabel, hintLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.isAccessibilityElement = false
        stack.accessibilityLabel = "\(title), \(hint)"
        stack.accessibilityIdentifier = identifier
        return stack
    }

    private func disclosure(
        title: String, hint: String, identifier: String, expanded: Bool, body: UIView
    ) -> UKDisclosureGroupView {
        let header = label(title, hint: hint, identifier: identifier)
        let group = UKDisclosureGroupView(label: header, body: body, initiallyExpanded: expanded, identifier: identifier)
        group.accessibilityLabel = "\(title), \(hint)"
        return group
    }

    private func bodyStack(_ rows: [UIView]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: rows.map { UKGroupSectionView.paddedRow($0) })
        stack.axis = .vertical
        return stack
    }

    private func bulkRow(id: String, title: String, enabled: Bool, all: @escaping () -> Void, none: @escaping () -> Void) -> UIView {
        func button(_ text: String, color: UIColor, suffix: String, action: @escaping () -> Void) -> UIButton {
            nonisolated(unsafe) let action = action
            var configuration = UIButton.Configuration.plain()
            configuration.title = text
            configuration.baseForegroundColor = color
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = UKFont.font(.subheadline, weight: .semibold)
                return outgoing
            }
            let view = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
                action()
                self?.refresh()
            })
            view.accessibilityLabel = "\(text), \(title)"
            view.accessibilityIdentifier = "fst.songs.filter.\(id).\(suffix)"
            view.accessibilityUserInputLabels = ["\(text) \(title)", text]
            view.isEnabled = enabled
            view.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            return view
        }
        let row = UIStackView(arrangedSubviews: [
            UIView(), button("Select All", color: BrandUIColors.textPrimary, suffix: "select-all", action: all),
            button("Clear All", color: Self.destructive, suffix: "clear-all", action: none),
        ])
        row.spacing = 16
        return row
    }

    // MARK: General

    private func bucketSection(
        id: String, title: String, hint: String, keys: [Int], label: @escaping (Int) -> String,
        excluded: WritableKeyPath<SongGeneralFilter, Set<Int>>
    ) {
        var rows: [UIView] = [
            bulkRow(
                id: id, title: title, enabled: true,
                all: { [unowned self] in draftGeneral[keyPath: excluded] = [] },
                none: { [unowned self] in draftGeneral[keyPath: excluded] = Set(keys) }
            ),
        ]
        for key in keys {
            rows.append(toggleRow(
                label(key), identifier: "fst.songs.filter.\(id).\(key)",
                isOn: { [unowned self] in !draftGeneral[keyPath: excluded].contains(key) },
                set: { [unowned self] included in
                    if included { draftGeneral[keyPath: excluded].remove(key) } else { draftGeneral[keyPath: excluded].insert(key) }
                }
            ))
        }
        let group = disclosure(
            title: title, hint: hint, identifier: "fst.songs.filter.\(id)",
            expanded: id == "year" ? inputs.appliedGeneral.restrictsYear : inputs.appliedGeneral.restrictsDuration, body: bodyStack(rows)
        )
        addSection(rows: [group])
    }

    private func addShopSection() {
        var rows: [UIView] = [
            toggleRow(
                "Available in Item Shop", identifier: "fst.songs.filter.shop-available",
                isOn: { [unowned self] in draftGeneral.shop.available },
                set: { [unowned self] value in draftGeneral.shop = SongShopFilter(available: value, unavailable: draftGeneral.shop.unavailable) }
            ),
            toggleRow(
                "Not Available in Item Shop", identifier: "fst.songs.filter.shop-unavailable",
                isOn: { [unowned self] in draftGeneral.shop.unavailable },
                set: { [unowned self] value in draftGeneral.shop = SongShopFilter(available: draftGeneral.shop.available, unavailable: value) }
            ),
        ]
        if !inputs.shopAvailable && draftGeneral.shop.needsShopFeed {
            rows.append(UKLabel("Item Shop filters need matching public Songs and Shop data.", style: .footnote))
        }
        let group = disclosure(
            title: "Item Shop", hint: "Filter songs by whether they are available in the Item Shop.",
            identifier: "fst.songs.filter.shop", expanded: inputs.appliedGeneral.shop.isActive, body: bodyStack(rows)
        )
        addSection(rows: [group])
    }

    private func addDoubleBassSection() {
        let rows: [UIView] = [
            toggleRow(
                "Double Bass Support", identifier: "fst.songs.filter.double-bass.supported",
                isOn: { [unowned self] in draftGeneral.doubleBassSupported }, set: { [unowned self] in draftGeneral.doubleBassSupported = $0 }
            ),
            toggleRow(
                "No Double Bass Support", identifier: "fst.songs.filter.double-bass.unsupported",
                isOn: { [unowned self] in draftGeneral.doubleBassUnsupported }, set: { [unowned self] in draftGeneral.doubleBassUnsupported = $0 }
            ),
        ]
        let group = disclosure(
            title: "Double Bass", hint: "Filter songs that have or don't have double bass charts for Pro Drums.",
            identifier: "fst.songs.filter.double-bass", expanded: inputs.appliedGeneral.restrictsDoubleBass, body: bodyStack(rows)
        )
        addSection(rows: [group])
    }

    // MARK: Player scores

    private func scoreLabel(_ kind: SongScoreFilterKind, chart: Instrument? = nil) -> String {
        switch (kind, chart) {
        case (.missingScores, nil): "Missing Scores"
        case (.hasScores, nil): "Has Scores"
        case (.missingFCs, nil): "Missing FCs"
        case (.hasFCs, nil): "Has FCs"
        case let (.missingScores, chart?): "Missing \(chart.label) Scores"
        case let (.hasScores, chart?): "Has \(chart.label) Scores"
        case let (.missingFCs, chart?): "Missing \(chart.label) FCs"
        case let (.hasFCs, chart?): "Has \(chart.label) FCs"
        }
    }

    private func addScoreSections() {
        let visible = inputs.visibleInstruments
        var rows: [UIView] = []
        let intro = UKLabel("Score and full combo checks match any enabled chart; selected checks on one chart apply together.", style: .footnote)
        rows.append(intro)
        if !inputs.scoreAvailable { rows.append(UKLabel("Score filters need published player scores from the current Songs catalogue.")) }
        let allHeader = UKLabel("All enabled charts", style: .footnote, weight: .semibold).asHeader()
        rows.append(allHeader)
        for kind in SongScoreFilterKind.allCases {
            rows.append(toggleRow(
                scoreLabel(kind), identifier: "fst.songs.filter.score.global.\(kind.rawValue)",
                isOn: { [unowned self] in draftPlayerFilter.allVisible(kind, visibleInstruments: visible) },
                enabled: { [unowned self] in canEnableScores },
                set: { [unowned self] in draftPlayerFilter = draftPlayerFilter.settingAll(kind, visibleInstruments: visible, enabled: $0) }
            ))
        }
        if inputs.invalidScoreFilteringEnabled {
            rows.append(toggleRow(
                "Over CHOpt Threshold", identifier: "fst.songs.filter.score.global.overThreshold",
                isOn: { [unowned self] in draftPlayerFilter.allVisibleOverThreshold(visibleInstruments: visible) },
                enabled: { [unowned self] in canEnableScores },
                set: { [unowned self] in draftPlayerFilter = draftPlayerFilter.settingAllOverThreshold(visibleInstruments: visible, enabled: $0) }
            ))
        }
        rows.append(UKLabel("Individual charts", style: .footnote, weight: .semibold).asHeader())
        for chart in Instrument.allCases.filter(visible.contains) {
            var chartRows: [UIView] = []
            for kind in SongScoreFilterKind.allCases {
                chartRows.append(toggleRow(
                    scoreLabel(kind, chart: chart), identifier: "fst.songs.filter.score.chart.\(chart.rawValue).\(kind.rawValue)",
                    isOn: { [unowned self] in draftPlayerFilter.contains(kind, for: chart) },
                    enabled: { [unowned self] in canEnableScores },
                    set: { [unowned self] in draftPlayerFilter = draftPlayerFilter.setting(kind, for: chart, enabled: $0) }
                ))
            }
            if inputs.invalidScoreFilteringEnabled {
                chartRows.append(toggleRow(
                    "\(chart.label) Over CHOpt Threshold", identifier: "fst.songs.filter.score.chart.\(chart.rawValue).overThreshold",
                    isOn: { [unowned self] in draftPlayerFilter.containsOverThreshold(chart) },
                    enabled: { [unowned self] in canEnableScores },
                    set: { [unowned self] in draftPlayerFilter = draftPlayerFilter.settingOverThreshold(chart, enabled: $0) }
                ))
            }
            let name = UKLabel(chart.label)
            name.accessibilityIdentifier = "fst.songs.filter.score.instrument.\(chart.rawValue)"
            let group = UKDisclosureGroupView(label: name, body: bodyStack(chartRows), initiallyExpanded: false, identifier: "fst.songs.filter.score.instrument.\(chart.rawValue)")
            rows.append(group)
        }
        let open = inputs.appliedPlayerFilter.isActive
        let title = UKLabel("Player Score and FC Filters")
        let group = UKDisclosureGroupView(
            label: title, body: bodyStack(rows), initiallyExpanded: inputs.selectedPlayer && open,
            identifier: "fst.songs.filter.score-sections"
        )
        group.accessibilityLabel = "Player Score and FC Filters"
        addSection(rows: [group])
    }

    private func addInstrumentSection() {
        var rows: [UIView] = [
            radioRow("All Instruments", identifier: "fst.songs.filter.instrument", selected: { [unowned self] in draftInstrument == nil }) { [unowned self] in
                draftInstrument = nil
            },
        ]
        for chart in Instrument.allCases.filter(inputs.visibleInstruments.contains) {
            rows.append(radioRow(chart.label, identifier: "fst.songs.filter.instrument", selected: { [unowned self] in draftInstrument == chart }) { [unowned self] in
                draftInstrument = chart
            })
        }
        addSection("Instrument", rows: rows, footnotes: [footnote("Filtering to a single instrument enables more filters.")])
    }

    // MARK: One-instrument buckets

    private func addBucketAccordion() {
        let accordion = UKAccordionView<Instrument>(inputs.selectedPlayer ? inputs.appliedInstrument : nil) { [unowned self] _ in
            let column = UIStackView()
            column.axis = .vertical
            column.spacing = 24
            for kind in SongBucketKind.allCases { column.addArrangedSubview(self.bucketGroup(kind)) }
            return column
        }
        buckets = accordion
        stack.addArrangedSubview(accordion)
    }

    private func bucketGroup(_ kind: SongBucketKind) -> UIView {
        let spec: (title: String, hint: String, keys: [Int])
        switch kind {
        case .season: spec = ("Season", "Filter songs by the season your high score was achieved.", inputs.availableSeasons)
        case .percentile: spec = ("Percentile", "Show or hide songs based on their leaderboard ranking bracket.", SongPercentileBucket.keys)
        case .stars: spec = ("Stars", "Filter songs by the number of stars on your high score.", SongStarsBucket.keys)
        case .intensity: spec = ("Intensity", "Filter songs by the chart's intensity.", SongIntensityBucket.keys)
        }
        var rows: [UIView] = [
            bulkRow(
                id: kind.rawValue, title: spec.title, enabled: canEnableScores,
                all: { [unowned self] in draftPlayerFilter = draftPlayerFilter.settingExcluded(kind, []) },
                none: { [unowned self] in draftPlayerFilter = draftPlayerFilter.settingExcluded(kind, Set(spec.keys)) }
            ),
        ]
        for key in spec.keys {
            let spoken = Self.spokenLabel(kind, key)
            var visual: UIView?
            if kind == .stars, key != 0 { visual = UKStarRatingView(stars: key) }
            if kind == .intensity, key != 0 { visual = UKDifficultyMeterView(level: Double(key)) }
            rows.append(toggleRow(
                spoken, identifier: "fst.songs.filter.\(kind.rawValue).\(key)", visual: visual,
                isOn: { [unowned self] in draftPlayerFilter.includes(kind, key) },
                enabled: { [unowned self] in canEnableScores },
                set: { [unowned self] in draftPlayerFilter = draftPlayerFilter.setting(kind, key, included: $0) }
            ))
        }
        let expanded = !inputs.appliedPlayerFilter.excluded(kind).isEmpty
        let group = disclosure(
            title: spec.title, hint: spec.hint, identifier: "fst.songs.filter.\(kind.rawValue)", expanded: expanded, body: bodyStack(rows)
        )
        let section = UKGroupSectionView(nil, rows: .padded)
        section.setRows([group])
        return section
    }

    private static func spokenLabel(_ kind: SongBucketKind, _ key: Int) -> String {
        switch kind {
        case .season: SongSeasonBucket.label(key)
        case .percentile: SongPercentileBucket.label(key)
        case .stars: SongStarsBucket.label(key)
        case .intensity: SongIntensityBucket.label(key)
        }
    }
}
#endif
