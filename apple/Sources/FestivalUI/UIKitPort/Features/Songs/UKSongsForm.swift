#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Form page

/// A sheet page of grouped rows (the SwiftUI `Form` in `FestivalModal`): a scrolling stack of
/// ``UKGroupSectionView`` cards with the sheet's top edge fade driven by its scroll view.
class UKFormViewController: UIViewController, UKModalScrollProviding {
    let scroll = UIScrollView()
    let stack = UIStackView()
    private var refreshers: [@MainActor () -> Void] = []

    var ukModalScrollView: UIScrollView? { scroll }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .clear
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .onDrag
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -40),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32),
        ])
        build()
    }

    /// Builds the form's sections; override.
    func build() {}

    /// Re-reads every row's state after a draft change.
    func refresh() { refreshers.forEach { $0() } }

    /// Registers a row's refresh closure.
    func onRefresh(_ refresh: @escaping @MainActor () -> Void) { refreshers.append(refresh) }

    // MARK: Sections

    /// Adds a titled card of rows with optional footnotes under it.
    @discardableResult
    func addSection(
        _ title: String? = nil, subtitle: String? = nil, titleIdentifier: String? = nil,
        rows: [UIView], footnotes: [UIView] = [], header: UIView? = nil
    ) -> UKGroupSectionView {
        let section = UKGroupSectionView(title, subtitle: subtitle, rows: .padded)
        section.setRows(rows)
        if let titleIdentifier { section.accessibilityIdentifier = titleIdentifier }
        var views: [UIView] = [section]
        views.append(contentsOf: footnotes)
        let holder = UIStackView(arrangedSubviews: views)
        holder.axis = .vertical
        holder.spacing = 8
        stack.addArrangedSubview(holder)
        return section
    }

    // MARK: Rows

    /// A switch row: the title (and optional hint) with a trailing switch.
    func toggleRow(
        _ title: String, hint: String? = nil, identifier: String, accessibilityHint: String? = nil, visual: UIView? = nil,
        isOn: @escaping @MainActor () -> Bool, enabled: @escaping @MainActor () -> Bool = { true }, set: @escaping @MainActor (Bool) -> Void
    ) -> UIView {
        let row = UKToggleRow(title: title, hint: hint, identifier: identifier, accessibilityHint: accessibilityHint, visual: visual)
        row.toggle.addAction(UIAction { [weak self, weak row] _ in
            guard let row else { return }
            set(row.toggle.isOn)
            self?.refresh()
        }, for: .valueChanged)
        let sync: @MainActor () -> Void = { [weak row] in
            row?.toggle.isOn = isOn()
            row?.toggle.isEnabled = enabled()
            row?.alpha = enabled() ? 1 : 0.5
        }
        sync()
        onRefresh(sync)
        return row
    }

    /// A choice row of an inline picker: the label with a trailing checkmark when selected.
    func radioRow(
        _ title: String, subtitle: String? = nil, identifier: String, selected: @escaping @MainActor () -> Bool,
        enabled: Bool = true, select: @escaping @MainActor () -> Void
    ) -> UIView {
        let row = UKRadioRow(title: title, subtitle: subtitle, identifier: identifier)
        row.addAction(UIAction { [weak self] _ in
            select()
            self?.refresh()
        }, for: .touchUpInside)
        row.isEnabled = enabled
        row.alpha = enabled ? 1 : 0.5
        let sync: @MainActor () -> Void = { [weak row] in row?.setSelected(selected()) }
        sync()
        onRefresh(sync)
        return row
    }

    /// A text button row (Reset in red).
    func buttonRow(_ title: String, color: UIColor, identifier: String, action: @escaping @MainActor () -> Void) -> UIView {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.baseForegroundColor = color
        configuration.contentInsets = .zero
        configuration.titleAlignment = .leading
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UKFont.font(.body)
            return outgoing
        }
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            action()
            self?.refresh()
        })
        button.contentHorizontalAlignment = .leading
        button.accessibilityIdentifier = identifier
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        return button
    }

    /// A footnote under a card.
    func footnote(_ text: String, identifier: String? = nil) -> UIView {
        let label = UKFootnoteLabel(text)
        label.accessibilityIdentifier = identifier
        let holder = UIView()
        label.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -4),
            label.topAnchor.constraint(equalTo: holder.topAnchor), label.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
        ])
        return holder
    }

    /// The destructive sheet action colour (#FF8C88).
    static let destructive = UIColor(red: 1.0, green: 140.0 / 255, blue: 136.0 / 255, alpha: 1)
}

// MARK: - Toggle row

/// A switch row.
final class UKToggleRow: UIView {
    let toggle = UISwitch()

    init(title: String, hint: String?, identifier: String, accessibilityHint: String?, visual: UIView? = nil) {
        super.init(frame: .zero)
        let label: UIView = visual ?? UKLabel(title)
        let texts = UIStackView(arrangedSubviews: [label])
        texts.alignment = visual == nil ? .fill : .leading
        texts.axis = .vertical
        texts.spacing = 2
        if let hint { texts.addArrangedSubview(UKLabel(hint, style: .footnote)) }
        texts.isUserInteractionEnabled = false
        toggle.onTintColor = BrandUIColors.accentBlue
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.accessibilityLabel = title
        toggle.accessibilityHint = accessibilityHint
        toggle.accessibilityIdentifier = identifier
        let row = UIStackView(arrangedSubviews: [texts, toggle])
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        isAccessibilityElement = false
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func tapped() {
        guard toggle.isEnabled else { return }
        toggle.setOn(!toggle.isOn, animated: true)
        toggle.sendActions(for: .valueChanged)
    }
}

// MARK: - Radio row

/// One choice of an inline picker.
final class UKRadioRow: UIControl {
    private let check = UIImageView(image: UIImage(systemName: "checkmark"))

    init(title: String, subtitle: String?, identifier: String) {
        super.init(frame: .zero)
        let label = UKLabel(title)
        let texts = UIStackView(arrangedSubviews: [label])
        texts.axis = .vertical
        texts.spacing = 2
        if let subtitle { texts.addArrangedSubview(UKLabel(subtitle, style: .footnote)) }
        texts.isUserInteractionEnabled = false
        check.tintColor = BrandUIColors.accentBlue
        check.setContentHuggingPriority(.required, for: .horizontal)
        check.isHidden = true
        check.isUserInteractionEnabled = false
        let row = UIStackView(arrangedSubviews: [texts, check])
        row.spacing = 12
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button
        accessibilityIdentifier = identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Marks the row as the chosen one.
    func setSelected(_ selected: Bool) {
        check.isHidden = !selected
        accessibilityTraits = selected ? [.button, .selected] : .button
    }

    override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.6 : 1 } }
}

// MARK: - Sort direction

/// The Ascending / Descending control (``SortDirectionControl``).
final class UKSortDirectionControl: UIView {
    private let title = UKLabel()
    private let detail = UKLabel(style: .footnote)
    private var buttons: [Bool: UIButton] = [:]
    private let ascendingDetail: String
    private let descendingDetail: String
    var ascending: Bool { didSet { update() } }
    var onChange: ((Bool) -> Void)?

    init(ascending: Bool, identifier: String, ascendingDetail: String = "A–Z, low to high", descendingDetail: String = "Z–A, high to low") {
        self.ascending = ascending
        self.ascendingDetail = ascendingDetail
        self.descendingDetail = descendingDetail
        super.init(frame: .zero)
        let texts = UIStackView(arrangedSubviews: [title, detail])
        texts.axis = .vertical
        texts.spacing = 2
        let pill = UIStackView()
        pill.spacing = 4
        pill.isLayoutMarginsRelativeArrangement = true
        pill.layoutMargins = UIEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
        pill.backgroundColor = BrandUIColors.surfaceMuted
        pill.layer.cornerCurve = .continuous
        pill.layer.cornerRadius = 22
        for up in [true, false] {
            var configuration = UIButton.Configuration.plain()
            configuration.image = UIImage(systemName: up ? "arrow.up" : "arrow.down")
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(font: UKFont.font(.body, weight: .semibold))
            configuration.cornerStyle = .capsule
            let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
                self?.ascending = up
                self?.onChange?(up)
            })
            button.accessibilityLabel = up ? "Ascending" : "Descending"
            button.accessibilityIdentifier = "\(identifier).\(up ? "ascending" : "descending")"
            button.widthAnchor.constraint(equalToConstant: 44).isActive = true
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
            buttons[up] = button
            pill.addArrangedSubview(button)
        }
        let row = UIStackView(arrangedSubviews: [texts, pill])
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        accessibilityIdentifier = identifier
        update()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func update() {
        title.text = ascending ? "Ascending" : "Descending"
        detail.text = ascending ? ascendingDetail : descendingDetail
        for (up, button) in buttons {
            let selected = ascending == up
            var configuration = button.configuration
            configuration?.baseForegroundColor = selected ? BrandUIColors.textPrimary : BrandUIColors.textSecondary
            configuration?.background.backgroundColor = selected ? BrandUIColors.accentPurple : .clear
            button.configuration = configuration
            button.accessibilityTraits = selected ? [.button, .selected] : .button
        }
    }
}

// MARK: - Sort sheet

/// The Sort sheet (``SongsSortSheet``): sort mode, the filtered-instrument modes, the
/// direction and Reset; each change applies at once.
final class UKSongsSortSheetController: UKFormViewController {
    private var draftMode: SongSortMode
    private var draftAscending: Bool
    private let mode: SongSortMode
    private let showShop: Bool
    private let shopAvailable: Bool
    private let playerModes: [SongSortMode]
    private let modes: [SongSortMode]
    private let identifier: String
    private let onApply: (SongSortMode, Bool) -> Void

    /// Creates the sheet.
    init(
        mode: SongSortMode, ascending: Bool, showShop: Bool = false, shopAvailable: Bool = false,
        playerModes: [SongSortMode] = [], modes: [SongSortMode] = SongSortMode.catalogueModes,
        identifier: String = "fst.songs.sort", onApply: @escaping (SongSortMode, Bool) -> Void
    ) {
        self.mode = mode
        draftMode = mode
        draftAscending = ascending
        self.showShop = showShop
        self.shopAvailable = shopAvailable
        self.playerModes = playerModes
        self.modes = modes
        self.identifier = identifier
        self.onApply = onApply
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var isApplicable: Bool {
        if draftMode.isPlayerChartMode { return playerModes.contains(draftMode) }
        guard modes.contains(draftMode) else { return false }
        return draftMode != .shop || (showShop && shopAvailable)
    }

    private func commit() {
        guard isApplicable else { return }
        onApply(draftMode, draftAscending)
    }

    override func build() {
        var notes: [UIView] = []
        let choices = modes.filter { showShop || $0 != .shop }
        let rows = choices.map { choice in
            radioRow(
                choice.label, identifier: "\(identifier).mode", selected: { [unowned self] in draftMode == choice },
                enabled: !(choice == .shop && !shopAvailable)
            ) { [unowned self] in
                draftMode = choice
                commit()
            }
        }
        if showShop && !shopAvailable {
            notes.append(footnote("Item Shop sorting requires matching public Songs and Shop data."))
        } else if !showShop && mode == .shop {
            notes.append(footnote("Item Shop sort is saved but hidden. Reset to Title A-Z to choose another mode."))
        }
        addSection("Sort Mode", rows: rows, footnotes: notes)
        if !playerModes.isEmpty {
            let playerRows = playerModes.map { choice in
                radioRow(choice.label, identifier: "\(identifier).player-mode", selected: { [unowned self] in draftMode == choice }) { [unowned self] in
                    draftMode = choice
                    commit()
                }
            }
            addSection(
                "Filtered Instrument Sort Mode", subtitle: "Filtering to a single instrument enables more sort options.", rows: playerRows
            )
        }
        let direction = UKSortDirectionControl(ascending: draftAscending, identifier: "\(identifier).direction")
        direction.onChange = { [unowned self] value in
            draftAscending = value
            commit()
        }
        addSection("Sort Direction", rows: [direction])
        let reset = buttonRow("Reset to Title A–Z", color: Self.destructive, identifier: "\(identifier).reset") { [unowned self] in
            draftMode = .title
            draftAscending = true
            direction.ascending = true
            commit()
        }
        addSection(rows: [reset])
    }
}
#endif
