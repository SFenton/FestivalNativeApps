#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Form content layout

/// Lays out a grouped form inside a scroll view that already respects the sheet's safe area.
@MainActor
struct UKFormContentLayout {
    private static let horizontalMargin: CGFloat = 16
    private let leading: NSLayoutConstraint
    private let trailing: NSLayoutConstraint

    /// Installs a form column with native gutters, optionally capping its readable width.
    ///
    /// - Parameters:
    ///   - column: The grouped form content.
    ///   - scroll: The scroll view containing the form.
    ///   - bottom: Spacing below the last row, inside the bottom safe area.
    ///   - maximumWidth: The optional cap for a readable form on a wide display.
    init(_ column: UIView, in scroll: UIScrollView, bottom: CGFloat, maximumWidth: CGFloat? = nil) {
        scroll.addSubview(column)
        column.translatesAutoresizingMaskIntoConstraints = false
        let content = scroll.contentLayoutGuide
        let usable = UILayoutGuide()
        scroll.addLayoutGuide(usable)
        leading = usable.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Self.horizontalMargin)
        trailing = usable.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Self.horizontalMargin)
        let fill = column.widthAnchor.constraint(equalTo: usable.widthAnchor)
        if let maximumWidth {
            fill.priority = UILayoutPriority(999)
            column.widthAnchor.constraint(lessThanOrEqualToConstant: maximumWidth).isActive = true
        }
        NSLayoutConstraint.activate([
            leading, trailing, fill,
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            column.centerXAnchor.constraint(equalTo: usable.centerXAnchor),
            column.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            column.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -bottom),
            usable.topAnchor.constraint(equalTo: column.topAnchor),
            usable.bottomAnchor.constraint(equalTo: column.bottomAnchor),
        ])
    }

    /// Avoids adding a second margin on the folded rail side when the safe area supplies one.
    ///
    /// - Parameters:
    ///   - view: The sheet root, before the scroll view has been inset to its safe area.
    ///   - layout: The current window layout, including the rail's directional edge.
    func updateGutters(in view: UIView, layout: DeviceLayout) {
        var leadingMargin = Self.horizontalMargin
        var trailingMargin = Self.horizontalMargin
        if layout.pose == .folded, case let .verticalBar(edge) = layout.sectionChrome {
            let rtl = view.effectiveUserInterfaceLayoutDirection == .rightToLeft
            let railOnLeft = edge == .leading ? !rtl : rtl
            let insets = view.safeAreaInsets
            if (railOnLeft ? insets.left : insets.right) >= Self.horizontalMargin {
                if edge == .leading { leadingMargin = 0 } else { trailingMargin = 0 }
            }
        }
        if leading.constant != leadingMargin { leading.constant = leadingMargin }
        if trailing.constant != -trailingMargin { trailing.constant = -trailingMargin }
    }
}

// MARK: - Form page

/// A sheet page of grouped rows (the SwiftUI `Form` in `FestivalModal`): a scrolling stack of
/// ``UKGroupSectionView`` form sections with the sheet's top edge fade driven by its scroll view.
class UKFormViewController: UIViewController, UKModalScrollProviding {
    /// Vertical separation between adjacent form sections, including accordion sections.
    static let sectionSpacing: CGFloat = 35
    static let titledSectionSpacing: CGFloat = 28
    private static let beforeFooterSpacing: CGFloat = 7
    private static let afterFooterSpacing: CGFloat = 23
    private var contentLayout: UKFormContentLayout?

    /// A collection view with no items, so the scrolling form is addressable as the list the
    /// SwiftUI `Form` is (XCUITest finds `Form` content in a table or collection view).
    let scroll: UIScrollView = {
        let collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        collection.backgroundColor = .clear
        return collection
    }()
    let stack = UIStackView()
    var refreshers: [() -> Void] = []

    var ukModalScrollView: UIScrollView? { scroll }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .clear
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .onDrag
        stack.axis = .vertical
        stack.spacing = Self.sectionSpacing
        view.addSubview(scroll)
        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        contentLayout = UKFormContentLayout(stack, in: scroll, bottom: 20)
        build()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        contentLayout?.updateGutters(in: view, layout: ukWindowLayout)
    }

    /// Builds the form's sections; override.
    func build() {}

    /// Re-reads every row's state after a draft change.
    func refresh() { refreshers.forEach { $0() } }

    /// Registers a row's refresh closure.
    func onRefresh(_ refresh: @escaping () -> Void) { refreshers.append(refresh) }

    // MARK: Sections

    /// Adds a grouped form section with an optional native footer beneath it.
    @discardableResult
    func addSection(
        _ title: String? = nil, subtitle: String? = nil, titleIdentifier: String? = nil,
        rows: [UIView], header: UIView? = nil, footer: String? = nil, fill: UIColor? = nil
    ) -> UKGroupSectionView {
        let section = UKGroupSectionView(
            header: header ?? title.map { UKSectionHeaderView($0, subtitle: subtitle) },
            surface: .form, formFill: fill
        )
        section.setRows(rows)
        if let titleIdentifier { section.accessibilityIdentifier = titleIdentifier }
        let titled = title != nil || header != nil
        if let footer {
            let holder = UIStackView(arrangedSubviews: [section, UKGroupSectionView.formFooter(footer)])
            holder.axis = .vertical
            holder.spacing = Self.beforeFooterSpacing
            appendSection(holder, titled: titled)
            stack.setCustomSpacing(Self.afterFooterSpacing, after: holder)
        } else {
            appendSection(section, titled: titled)
        }
        return section
    }

    /// Appends a prebuilt grouped form section using the same gaps as ``addSection``.
    func appendSection(_ section: UIView, titled: Bool = false) {
        if titled, let preceding = stack.arrangedSubviews.last {
            stack.setCustomSpacing(Self.titledSectionSpacing, after: preceding)
        }
        stack.addArrangedSubview(section)
    }

    // MARK: Rows

    /// A switch row: the title (and optional hint) with a trailing switch.
    func toggleRow(
        _ title: String, hint: String? = nil, identifier: String, accessibilityHint: String? = nil, visual: UIView? = nil,
        accessibilityLabel: String? = nil,
        isOn: @escaping () -> Bool, enabled: @escaping () -> Bool = { true }, set: @escaping (Bool) -> Void
    ) -> UIView {
        let row = UKToggleRow(
            title: title, hint: hint, identifier: identifier, accessibilityHint: accessibilityHint,
            visual: visual, accessibilityLabel: accessibilityLabel
        )
        nonisolated(unsafe) let set = set
        row.toggle.addAction(UIAction { [weak self, weak row] _ in
            guard let row else { return }
            set(row.toggle.isOn)
            self?.refresh()
        }, for: .valueChanged)
        let sync: () -> Void = { [weak row] in
            row?.toggle.isOn = isOn()
            row?.toggle.isEnabled = enabled()
        }
        sync()
        onRefresh(sync)
        return row
    }

    /// A choice row of an inline picker: the label with a trailing checkmark when selected.
    func radioRow(
        _ title: String, subtitle: String? = nil, identifier: String, selected: @escaping () -> Bool,
        enabled: Bool = true, select: @escaping () -> Void
    ) -> UIView {
        let row = UKRadioRow(title: title, subtitle: subtitle, identifier: identifier)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: UKGroupSectionView.minimumRowHeight).isActive = true
        nonisolated(unsafe) let select = select
        row.addAction(UIAction { [weak self] _ in
            select()
            self?.refresh()
        }, for: .touchUpInside)
        row.isEnabled = enabled
        let sync: () -> Void = { [weak row] in row?.isSelected = selected() }
        sync()
        onRefresh(sync)
        return row
    }

    /// A text button row (Reset in red).
    func buttonRow(_ title: String, color: UIColor, identifier: String, action: @escaping () -> Void) -> UIView {
        nonisolated(unsafe) let action = action
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.baseForegroundColor = color
        // The group owns the rounded surface; the button's rounding clips its wrapped title.
        configuration.cornerStyle = .fixed
        configuration.background.cornerRadius = 0
        let padding = UKGroupSectionView.formTextPadding
        configuration.contentInsets = NSDirectionalEdgeInsets(top: padding, leading: 0, bottom: padding, trailing: 0)
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
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: UKGroupSectionView.minimumRowHeight).isActive = true
        return button
    }

    /// The destructive sheet action colour (#FF8C88).
    static let destructive = UIColor(red: 1.0, green: 140.0 / 255, blue: 136.0 / 255, alpha: 1)
}

// MARK: - Toggle row

/// A switch row.
final class UKToggleRow: UIView {
    let toggle = UKRowSwitch()

    init(
        title: String, hint: String?, identifier: String, accessibilityHint: String?,
        visual: UIView?, accessibilityLabel: String?
    ) {
        super.init(frame: .zero)
        let label: UIView = visual ?? UKLabel(title)
        let texts = UIStackView(arrangedSubviews: [label])
        texts.alignment = visual == nil ? .fill : .leading
        texts.axis = .vertical
        texts.spacing = 2
        if let hint { texts.addArrangedSubview(UKLabel(hint, style: .footnote)) }
        texts.isUserInteractionEnabled = false
        texts.accessibilityElementsHidden = accessibilityLabel != nil
        toggle.onTintColor = BrandUIColors.accentBlue
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.accessibilityLabel = accessibilityLabel ?? title
        toggle.accessibilityHint = accessibilityHint
        toggle.accessibilityIdentifier = identifier
        toggle.row = self
        toggle.framePadding = UIEdgeInsets(top: -6, left: -16, bottom: -6, right: -16)
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

    @objc private func tapped() { toggle.flip() }
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
        let padding = UKGroupSectionView.formTextPadding
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
        ])
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button
        accessibilityIdentifier = identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isSelected: Bool { didSet { updateAppearance() } }
    override var isEnabled: Bool { didSet { updateAppearance() } }
    override var isHighlighted: Bool { didSet { updateAppearance() } }

    private func updateAppearance() {
        check.isHidden = !isSelected
        var traits: UIAccessibilityTraits = .button
        if isSelected { traits.insert(.selected) }
        if !isEnabled { traits.insert(.notEnabled) }
        accessibilityTraits = traits
        alpha = isHighlighted ? 0.6 : 1
    }
}

// MARK: - Sort direction

/// The Ascending / Descending control (``SortDirectionControl``).
final class UKSortDirectionControl: UIView {
    private let title = UKLabel()
    private let detail = UKLabel(style: .footnote)
    private var choices: [(ascending: Bool, button: UIButton, arrow: UIImageView)] = []
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
        let buttonWidth: CGFloat = 44
        let pillWidth = 2 * buttonWidth + pill.spacing + pill.layoutMargins.left + pill.layoutMargins.right
        pill.widthAnchor.constraint(equalToConstant: pillWidth).isActive = true
        for up in [true, false] {
            var configuration = UIButton.Configuration.plain()
            configuration.cornerStyle = .capsule
            let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
                self?.ascending = up
                self?.onChange?(up)
            })
            button.accessibilityLabel = up ? "Ascending" : "Descending"
            button.accessibilityIdentifier = "\(identifier).\(up ? "ascending" : "descending")"
            button.widthAnchor.constraint(equalToConstant: buttonWidth).isActive = true
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
            let arrow = UIImageView(image: UIImage(systemName: up ? "arrow.up" : "arrow.down"))
            arrow.isAccessibilityElement = false
            arrow.isUserInteractionEnabled = false
            arrow.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(arrow)
            NSLayoutConstraint.activate([
                arrow.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                arrow.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ])
            choices.append((up, button, arrow))
            pill.addArrangedSubview(button)
        }
        let row = UIStackView(arrangedSubviews: [texts, pill])
        // Match the reference's 8 pt spacer and the 12 pt spacing on either side.
        row.spacing = 12 + 8 + 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -11),
        ])
        accessibilityIdentifier = identifier
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (control: UKSortDirectionControl, _) in
            control.updateArrowFonts()
        }
        updateArrowFonts()
        update()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func updateArrowFonts() {
        let font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
        let symbol = UIImage.SymbolConfiguration(pointSize: font.pointSize, weight: .semibold)
        choices.forEach { $0.arrow.preferredSymbolConfiguration = symbol }
    }

    private func update() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.usesDefaultHyphenation = true
        title.attributedText = NSAttributedString(
            string: ascending ? "Ascending" : "Descending", attributes: [.paragraphStyle: paragraph]
        )
        detail.text = ascending ? ascendingDetail : descendingDetail
        for (up, button, arrow) in choices {
            let selected = ascending == up
            var configuration = button.configuration
            configuration?.background.backgroundColor = selected ? BrandUIColors.accentPurple : .clear
            button.configuration = configuration
            arrow.tintColor = selected ? BrandUIColors.textPrimary : BrandUIColors.textMuted
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
        let choices = modes.filter { showShop || $0 != .shop }
        var rows = choices.map { choice in
            radioRow(
                choice.label, identifier: "\(identifier).mode", selected: { [unowned self] in draftMode == choice },
                enabled: !(choice == .shop && !shopAvailable)
            ) { [unowned self] in
                draftMode = choice
                commit()
            }
        }
        if showShop && !shopAvailable {
            rows.append(UKGroupSectionView.formNote("Item Shop sorting requires matching public Songs and Shop data."))
        } else if !showShop && mode == .shop {
            rows.append(UKGroupSectionView.formNote("Item Shop sort is saved but hidden. Reset to Title A-Z to choose another mode."))
        }
        addSection("Sort Mode", rows: rows)
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
