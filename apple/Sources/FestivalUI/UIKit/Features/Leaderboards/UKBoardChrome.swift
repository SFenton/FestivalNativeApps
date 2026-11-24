#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Count header

/// The board's ranked count as the first line under the title (``RankingsCountHeader``).
final class UKRankingsCountHeader: UIView {
    /// Creates the header.
    ///
    /// - Parameters:
    ///   - text: "868,901 ranked players".
    ///   - identifier: Accessibility identifier.
    init(text: String, identifier: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let label = UKLabel(text, style: .subheadline, weight: .semibold)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor), label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor), label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
        label.isAccessibilityElement = true
        label.accessibilityIdentifier = identifier
        accessibilityElements = [label]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Pager button

/// A 44 pt frosted circle arrow (web `arrowBtnBase`), faded when disabled.
final class UKPagerArrowButton: UIButton {
    private let card = UKCardView(cornerRadius: 22, capsule: true)
    private let glyph = UIImageView()
    private let symbol: String

    /// Creates the arrow.
    ///
    /// - Parameters:
    ///   - symbol: SF Symbol name.
    ///   - label: Spoken action.
    ///   - identifier: Accessibility identifier.
    ///   - framed: Draw the arrow on its own frosted circle (the text pager); the floating bar's arrows sit on the bar's capsule.
    init(symbol: String, label: String, identifier: String, framed: Bool) {
        self.symbol = symbol
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        if framed {
            card.isUserInteractionEnabled = false
            card.translatesAutoresizingMaskIntoConstraints = false
            addSubview(card)
            NSLayoutConstraint.activate([
                card.leadingAnchor.constraint(equalTo: leadingAnchor), card.trailingAnchor.constraint(equalTo: trailingAnchor),
                card.topAnchor.constraint(equalTo: topAnchor), card.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        glyph.isUserInteractionEnabled = false
        glyph.isAccessibilityElement = false
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)
        updateGlyph()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKPagerArrowButton, _) in
            self.updateGlyph()
        }
        accessibilityLabel = label
        accessibilityIdentifier = identifier
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 44), heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            glyph.centerXAnchor.constraint(equalTo: centerXAnchor), glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func updateGlyph() {
        let configuration = UIImage.SymbolConfiguration(font: UKFont.font(.body, weight: .semibold))
        glyph.image = UIImage(systemName: symbol, withConfiguration: configuration)?.withRenderingMode(.alwaysTemplate)
        updateGlyphTint()
    }

    private func updateGlyphTint() {
        glyph.tintColor = isEnabled ? BrandUIColors.textPrimary : BrandUIColors.textDisabled
    }

    override var isEnabled: Bool {
        didSet { updateGlyphTint() }
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }
}

/// The adjustable `page / total` badge both pagers share: one VoiceOver element
/// ("Page, 2 of 48"), swiped up or down to page.
final class UKPagerBadge: UIView {
    private let label = UKLabel(nil, style: .body, weight: .semibold, monospacedDigit: true, lines: 1, alignment: .center)
    private let card: UKCardView?
    private var state = RankingsPagerState(page: 1, totalPages: 1)
    /// Called with the destination page when VoiceOver adjusts.
    var onChange: ((Int) -> Void)?

    /// Creates the badge.
    ///
    /// - Parameters:
    ///   - identifier: Accessibility identifier.
    ///   - framed: Sit on a 12 pt corner card (the text pager); the floating bar's badge is bare.
    init(identifier: String, framed: Bool) {
        card = framed ? UKCardView(cornerRadius: 12) : nil
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = framed ? 0.7 : 0.5
        if !framed { label.font = UKFont.font(.subheadline, weight: .semibold, monospacedDigit: true) }
        if let card {
            card.isUserInteractionEnabled = false
            card.translatesAutoresizingMaskIntoConstraints = false
            addSubview(card)
            NSLayoutConstraint.activate([
                card.leadingAnchor.constraint(equalTo: leadingAnchor), card.trailingAnchor.constraint(equalTo: trailingAnchor),
                card.topAnchor.constraint(equalTo: topAnchor), card.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        addSubview(label)
        let inset: CGFloat = framed ? 14 : 6
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset), label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            label.topAnchor.constraint(equalTo: topAnchor), label.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44), widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        label.setContentCompressionResistancePriority(UILayoutPriority(250), for: .horizontal)
        setContentCompressionResistancePriority(UILayoutPriority(250), for: .horizontal)
        isAccessibilityElement = true
        accessibilityLabel = "Page"
        accessibilityTraits = .adjustable
        accessibilityIdentifier = identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows a pager state.
    ///
    /// - Parameter state: Page and page count.
    func show(_ state: RankingsPagerState) {
        self.state = state
        label.text = state.label
        accessibilityValue = state.accessibilityValue
    }

    override func accessibilityIncrement() {
        if let destination = state.destination(for: .next) { onChange?(destination) }
    }

    override func accessibilityDecrement() {
        if let destination = state.destination(for: .previous) { onChange?(destination) }
    }
}

// MARK: - Pager

/// Places only the pager controls within their board's full-width chrome.
@MainActor
private final class UKPagerPlacement {
    static let margin: CGFloat = 16

    private var center: NSLayoutConstraint?
    private var left: NSLayoutConstraint?
    private var right: NSLayoutConstraint?
    private var layout: DeviceLayout = .standardPhone
    private var observation: UKObservation?

    /// Installs the controls and observes pose changes even when the window doesn't resize.
    ///
    /// - Parameters:
    ///   - content: The stack holding the controls.
    ///   - host: The full-width pager, before horizontal padding.
    ///   - shell: The window layout publisher, if the pager is in the app shell.
    func install(content: UIView, in host: UIView, shell: UKShellState?) {
        let center = content.centerXAnchor.constraint(equalTo: host.centerXAnchor)
        let left = content.leftAnchor.constraint(greaterThanOrEqualTo: host.leftAnchor, constant: Self.margin)
        let right = content.rightAnchor.constraint(lessThanOrEqualTo: host.rightAnchor, constant: -Self.margin)
        self.center = center
        self.left = left
        self.right = right
        // A resize can invalidate the last region before the pager lays out at its new width.
        center.priority = UILayoutPriority(998)
        left.priority = UILayoutPriority(999)
        right.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            center, left, right,
            content.leftAnchor.constraint(greaterThanOrEqualTo: host.leftAnchor, constant: Self.margin),
            content.rightAnchor.constraint(lessThanOrEqualTo: host.rightAnchor, constant: -Self.margin),
            content.topAnchor.constraint(equalTo: host.topAnchor),
            content.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        observation = UKObservation { [weak self, weak host] in
            self?.layout = shell?.layout ?? .standardPhone
            host?.setNeedsLayout()
        }
    }

    /// Applies the shared placement in window coordinates, without moving the pinned footer.
    ///
    /// - Parameter host: The measured, unpadded pager view.
    func update(in host: UIView) {
        guard host.window != nil, host.bounds.width > 0 else { return }
        let rtl = host.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let railIsLeading = if case .verticalBar(.leading) = layout.sectionChrome { true } else { false }
        let region = PagerScreenPlacement.region(
            container: host.convert(host.bounds, to: nil),
            hinge: layout.screenDivide(layoutDirection: rtl ? .rightToLeft : .leftToRight),
            preferredEdge: railIsLeading != rtl ? .leading : .trailing
        )
        let offset = region.map { $0.midX - host.bounds.width / 2 } ?? 0
        let leftInset = (region?.minX ?? 0) + Self.margin
        let rightInset = (region?.maxX ?? host.bounds.width) - host.bounds.width - Self.margin
        if center?.constant != offset { center?.constant = offset }
        if left?.constant != leftInset { left?.constant = leftInset }
        if right?.constant != rightInset { right?.constant = rightInset }
    }
}

/// The discoverable first/previous/next/last pager under the song boards and Full Rankings
/// (``RankingsPagerView``): four 44 pt frosted circle arrows around an adjustable
/// `page / total` badge on the rows' card surface.
final class UKRankingsPagerView: UIView {
    private let stack = UIStackView()
    private let placement = UKPagerPlacement()
    private let badge: UKPagerBadge
    private var buttons: [RankingsPagerAction: UKPagerArrowButton] = [:]
    private var state = RankingsPagerState(page: 1, totalPages: 1)
    /// Called with the destination page.
    var onChange: ((Int) -> Void)?

    /// Creates the pager.
    ///
    /// - Parameters:
    ///   - idPrefix: Identifier prefix (`fst.full-rankings`); controls are `<prefix>.page-*`, the group `<prefix>.pager`.
    ///   - shell: The window layout publisher.
    init(idPrefix: String, shell: UKShellState?) {
        badge = UKPagerBadge(identifier: "\(idPrefix).page-info", framed: true)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 10
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        func arrow(_ action: RankingsPagerAction) -> UKPagerArrowButton {
            let button = UKPagerArrowButton(
                symbol: UKRankingsPagerSymbols.symbol(action), label: UKRankingsPagerSymbols.title(action),
                identifier: "\(idPrefix).page-\(action.rawValue)", framed: true
            )
            button.addAction(UIAction { [weak self] _ in self?.go(action) }, for: .primaryActionTriggered)
            buttons[action] = button
            return button
        }
        stack.addArrangedSubview(arrow(.first))
        stack.addArrangedSubview(arrow(.previous))
        stack.addArrangedSubview(badge)
        stack.addArrangedSubview(arrow(.next))
        stack.addArrangedSubview(arrow(.last))
        badge.onChange = { [weak self] in self?.onChange?($0) }
        placement.install(content: stack, in: self, shell: shell)
        isAccessibilityElement = false
        accessibilityContainerType = .semanticGroup
        accessibilityIdentifier = "\(idPrefix).pager"
        accessibilityElements = [buttons[.first]!, buttons[.previous]!, badge, buttons[.next]!, buttons[.last]!]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        placement.update(in: self)
    }

    private func go(_ action: RankingsPagerAction) {
        if let destination = state.destination(for: action) { onChange?(destination) }
    }

    /// Shows a pager state.
    ///
    /// - Parameter state: Page and page count.
    func show(_ state: RankingsPagerState) {
        self.state = state
        badge.show(state)
        for action in RankingsPagerAction.allCases {
            buttons[action]?.isEnabled = state.destination(for: action) != nil
        }
    }
}

/// Symbols and spoken titles of the pager steps (``RankingsGlassPager``).
enum UKRankingsPagerSymbols {
    /// SF Symbol for a step.
    static func symbol(_ action: RankingsPagerAction) -> String {
        switch action {
        case .first: "chevron.backward.2"
        case .previous: "chevron.backward"
        case .next: "chevron.forward"
        case .last: "chevron.forward.2"
        }
    }

    /// Spoken title for a step.
    static func title(_ action: RankingsPagerAction) -> String {
        switch action {
        case .first: "First Page"
        case .previous: "Previous Page"
        case .next: "Next Page"
        case .last: "Last Page"
        }
    }
}

// MARK: - Floating bar

/// The material pager capsule `« ‹ 1 / 34,757 › »` beside the board's switcher menu
/// (``RankingsFloatingBar``): Band Rankings' bottom bar. Layout falls back in order: one row
/// with the menu's title, one row with an icon-only menu, then pager above menu.
final class UKRankingsFloatingBar: UIView {
    private let placement = UKPagerPlacement()
    private let capsule = UKCardView(cornerRadius: 22, capsule: true)
    private let capsuleStack = UIStackView()
    private let badge: UKPagerBadge
    private var buttons: [RankingsPagerAction: UKPagerArrowButton] = [:]
    private let menuButton = UIButton(type: .custom)
    private let pillCard = UKCardView(cornerRadius: 22, capsule: true)
    private let pillStack = UIStackView()
    private let pillIcon = UIImageView()
    private let pillTitle = UKLabel(nil, style: .subheadline, weight: .semibold, lines: 1)
    private let holder = UIStackView()
    private lazy var menuMinHeight = menuButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
    private lazy var menuMinWidth = menuButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44)
    private var state: RankingsPagerState?
    private var verticalBar = false
    private let pagerHolder = UIView()
    /// Called with the destination page.
    var onChange: ((Int) -> Void)?

    /// Creates the bar.
    ///
    /// - Parameters:
    ///   - idPrefix: Identifier prefix (`fst.band-rankings`).
    ///   - menuIdentifier: The switcher's identifier.
    ///   - menuIcon: The switcher's SF Symbol.
    ///   - shell: The window layout publisher.
    init(idPrefix: String, menuIdentifier: String, menuIcon: String, shell: UKShellState?) {
        badge = UKPagerBadge(identifier: "\(idPrefix).page-info", framed: false)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        capsuleStack.axis = .horizontal
        capsuleStack.alignment = .fill
        capsuleStack.translatesAutoresizingMaskIntoConstraints = false
        capsule.isUserInteractionEnabled = true
        capsule.contentView.addSubview(capsuleStack)
        NSLayoutConstraint.activate([
            capsuleStack.leadingAnchor.constraint(equalTo: capsule.contentView.leadingAnchor, constant: 4),
            capsuleStack.trailingAnchor.constraint(equalTo: capsule.contentView.trailingAnchor, constant: -4),
            capsuleStack.topAnchor.constraint(equalTo: capsule.contentView.topAnchor),
            capsuleStack.bottomAnchor.constraint(equalTo: capsule.contentView.bottomAnchor),
        ])
        func arrow(_ action: RankingsPagerAction) -> UKPagerArrowButton {
            let button = UKPagerArrowButton(
                symbol: UKRankingsPagerSymbols.symbol(action), label: UKRankingsPagerSymbols.title(action),
                identifier: "\(idPrefix).page-\(action.rawValue)", framed: false
            )
            button.addAction(UIAction { [weak self] _ in self?.go(action) }, for: .primaryActionTriggered)
            buttons[action] = button
            return button
        }
        for view in [arrow(.first), arrow(.previous), badge, arrow(.next), arrow(.last)] { capsuleStack.addArrangedSubview(view) }
        badge.onChange = { [weak self] in self?.onChange?($0) }
        capsule.isAccessibilityElement = false
        capsule.accessibilityContainerType = .semanticGroup
        capsule.accessibilityIdentifier = "\(idPrefix).pager"
        capsule.accessibilityElements = [buttons[.first]!, buttons[.previous]!, badge, buttons[.next]!, buttons[.last]!]
        pagerHolder.translatesAutoresizingMaskIntoConstraints = false
        capsule.translatesAutoresizingMaskIntoConstraints = false
        pagerHolder.addSubview(capsule)
        NSLayoutConstraint.activate([
            capsule.leadingAnchor.constraint(equalTo: pagerHolder.leadingAnchor), capsule.trailingAnchor.constraint(equalTo: pagerHolder.trailingAnchor),
            capsule.topAnchor.constraint(equalTo: pagerHolder.topAnchor), capsule.bottomAnchor.constraint(equalTo: pagerHolder.bottomAnchor),
        ])
        // Switcher pill.
        pillCard.isUserInteractionEnabled = false
        pillCard.translatesAutoresizingMaskIntoConstraints = false
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.addSubview(pillCard)
        pillIcon.image = UIImage(systemName: menuIcon, withConfiguration: UIImage.SymbolConfiguration(font: UKFont.font(.title3)))
        pillIcon.tintColor = BrandUIColors.textPrimary
        pillIcon.contentMode = .scaleAspectFit
        pillIcon.setContentHuggingPriority(.required, for: .horizontal)
        pillStack.axis = .horizontal
        pillStack.spacing = 8
        pillStack.alignment = .center
        pillStack.isUserInteractionEnabled = false
        pillStack.translatesAutoresizingMaskIntoConstraints = false
        pillTitle.setContentCompressionResistancePriority(.required, for: .horizontal)
        pillStack.addArrangedSubview(pillIcon)
        pillStack.addArrangedSubview(pillTitle)
        menuButton.addSubview(pillStack)
        let labelArea = menuButton.layoutMarginsGuide
        NSLayoutConstraint.activate([
            pillCard.leadingAnchor.constraint(equalTo: menuButton.leadingAnchor), pillCard.trailingAnchor.constraint(equalTo: menuButton.trailingAnchor),
            pillCard.topAnchor.constraint(equalTo: menuButton.topAnchor), pillCard.bottomAnchor.constraint(equalTo: menuButton.bottomAnchor),
            pillStack.leadingAnchor.constraint(greaterThanOrEqualTo: labelArea.leadingAnchor),
            pillStack.trailingAnchor.constraint(lessThanOrEqualTo: labelArea.trailingAnchor),
            pillStack.centerXAnchor.constraint(equalTo: labelArea.centerXAnchor), pillStack.centerYAnchor.constraint(equalTo: menuButton.centerYAnchor),
            menuMinHeight, menuMinWidth,
        ])
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKRankingsFloatingBar, _) in
            self.scaleMenuMinimum()
            self.lastArrangement = nil
            self.setNeedsLayout()
        }
        scaleMenuMinimum()
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.accessibilityIdentifier = menuIdentifier
        menuButton.accessibilityLabel = "Band size"
        holder.axis = .horizontal
        holder.spacing = 8
        holder.alignment = .center
        holder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(holder)
        placement.install(content: holder, in: self, shell: shell)
        isAccessibilityElement = false
        arrange(width: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func go(_ action: RankingsPagerAction) {
        if let destination = state?.destination(for: action) { onChange?(destination) }
    }

    /// The pill's minimum size scales with the text (``RankingsSwitcherPillLabel``'s scaled 44).
    private func scaleMenuMinimum() {
        let side = UKFont.scaled(44, relativeTo: .body, traits: traitCollection)
        menuMinHeight.constant = side
        menuMinWidth.constant = side
    }

    /// Updates the bar.
    ///
    /// - Parameters:
    ///   - state: The pager state; nil while the first page loads (the menu shows alone).
    ///   - menu: The switcher's menu.
    ///   - menuTitle: Current selection's name.
    ///   - verticalBar: The iPhone Duo vertical bar: the pager shows alone (the menu is in the rail).
    func show(state: RankingsPagerState?, menu: UIMenu, menuTitle: String, verticalBar: Bool) {
        self.state = state
        self.verticalBar = verticalBar
        pillTitle.text = menuTitle
        menuButton.menu = menu
        menuButton.accessibilityValue = menuTitle
        if let state {
            badge.show(state)
            for action in RankingsPagerAction.allCases { buttons[action]?.isEnabled = state.destination(for: action) != nil }
        }
        arrange(width: availableWidth)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        placement.update(in: self)
        arrange(width: availableWidth)
    }

    /// Space inside the pager bar's two content margins.
    private var availableWidth: CGFloat? {
        bounds.width > 0 ? max(0, bounds.width - 2 * UKPagerPlacement.margin) : nil
    }

    private var lastArrangement: String?

    private func arrange(width: CGFloat?) {
        let leadingMargin: CGFloat = 8
        let trailingMargin: CGFloat = 14
        let hasPager = state != nil
        var mode = hasPager ? "pagerOnly" : "empty"
        if !verticalBar {
            mode = hasPager ? "rowTitle" : "menuOnly"
            if hasPager, let width {
                let pager = capsuleStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width + 8
                let icon = pillIcon.intrinsicContentSize.width
                let title = pillTitle.intrinsicContentSize.width
                let pill = max(menuMinWidth.constant, icon + pillStack.spacing + title + leadingMargin + trailingMargin)
                if pager + holder.spacing + pill > width {
                    mode = pager + holder.spacing + max(menuMinWidth.constant, icon) <= width ? "rowIcon" : "column"
                }
            }
        }
        guard mode != lastArrangement else { return }
        lastArrangement = mode
        holder.arrangedSubviews.forEach { holder.removeArrangedSubview($0); $0.removeFromSuperview() }
        pagerHolder.removeFromSuperview()
        menuButton.removeFromSuperview()
        pillTitle.isHidden = mode == "rowIcon"
        menuButton.directionalLayoutMargins = pillTitle.isHidden ? .zero
            : NSDirectionalEdgeInsets(top: 0, leading: leadingMargin, bottom: 0, trailing: trailingMargin)
        switch mode {
        case "empty":
            break
        case "pagerOnly":
            holder.axis = .horizontal
            holder.addArrangedSubview(pagerHolder)
        case "menuOnly":
            holder.axis = .horizontal
            holder.addArrangedSubview(menuButton)
        case "rowTitle", "rowIcon":
            holder.axis = .horizontal
            holder.addArrangedSubview(pagerHolder)
            holder.addArrangedSubview(menuButton)
        default:
            holder.axis = .vertical
            holder.addArrangedSubview(pagerHolder)
            holder.addArrangedSubview(menuButton)
        }
        // Reading order: the pager first, then the menu (#620).
        var order: [Any] = []
        if hasPager { order.append(capsule) }
        if !verticalBar { order.append(menuButton) }
        accessibilityElements = order
    }
}

// MARK: - Pinned footer

/// The opaque backing of a board's pinned selected row when Reduce Transparency or
/// Increase Contrast turns the shared surfaces opaque (``PinnedFooterBacking``).
@MainActor
enum UKPinnedFooterBacking {
    /// Whether the pinned row needs its opaque backing.
    ///
    /// - Parameter traits: The row's trait collection.
    static func isOpaque(_ traits: UITraitCollection) -> Bool {
        UKAccessibility.glassSurface(traits) == .opaque
    }
}

/// A board's pinned selected-row footer: the row in a rounded plate that is opaque under
/// Reduce Transparency / Increase Contrast, as a button chosen by ``SelectedRowAction``
/// (jump to the player's page, or open their page), or a read-only message (loading,
/// not yet ranked).
final class UKPinnedFooterView: UIView {
    private let plate = UIView()
    private let band = UIView()
    private let control = UIControl()
    private var rowView: UIView?
    private var observer: UKAccessibilityObserver?
    /// Called when the button is tapped.
    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        for view in [plate, control] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.topAnchor.constraint(equalTo: topAnchor), view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        plate.layer.cornerRadius = 12
        plate.layer.cornerCurve = .continuous
        plate.clipsToBounds = true
        plate.isUserInteractionEnabled = false
        band.backgroundColor = UKLeaderboardMetrics.playerFill
        band.translatesAutoresizingMaskIntoConstraints = false
        plate.addSubview(band)
        NSLayoutConstraint.activate([
            band.leadingAnchor.constraint(equalTo: plate.leadingAnchor), band.trailingAnchor.constraint(equalTo: plate.trailingAnchor),
            band.topAnchor.constraint(equalTo: plate.topAnchor), band.bottomAnchor.constraint(equalTo: plate.bottomAnchor),
        ])
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        layer.borderColor = UKLeaderboardMetrics.playerBorder.cgColor
        control.addAction(UIAction { [weak self] _ in self?.onTap?() }, for: .touchUpInside)
        control.addAction(UIAction { [weak self] _ in self?.alpha = 0.7 }, for: [.touchDown, .touchDragEnter])
        control.addAction(UIAction { [weak self] _ in self?.alpha = 1 }, for: [.touchUpInside, .touchUpOutside, .touchDragExit, .touchCancel])
        observer = UKAccessibilityObserver { [weak self] in self?.refreshBacking() }
        registerForTraitChanges([UITraitAccessibilityContrast.self]) { (self: UKPinnedFooterView, _) in self.refreshBacking() }
        refreshBacking()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func refreshBacking() {
        plate.backgroundColor = UKPinnedFooterBacking.isOpaque(traitCollection) ? BrandUIColors.appBackground : .clear
    }

    private func place(_ view: UIView) {
        rowView?.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        plate.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: plate.leadingAnchor), view.trailingAnchor.constraint(equalTo: plate.trailingAnchor),
            view.topAnchor.constraint(equalTo: plate.topAnchor), view.bottomAnchor.constraint(equalTo: plate.bottomAnchor),
        ])
        rowView = view
    }

    /// Shows the player's row as a button.
    ///
    /// - Parameters:
    ///   - row: The row's content view.
    ///   - containerIdentifier: `fst.<board>.spotlight-footer`.
    ///   - buttonIdentifier: `…spotlight-jump` or `…spotlight-open`.
    ///   - label: The spoken label (``SelectedRowAction/footerLabel(for:rank:)``).
    func setButton(row: UIView, containerIdentifier: String, buttonIdentifier: String, label: String) {
        place(row)
        band.isHidden = false
        layer.borderWidth = 1
        control.isHidden = false
        control.isAccessibilityElement = true
        control.accessibilityTraits = .button
        control.accessibilityLabel = label
        control.accessibilityIdentifier = buttonIdentifier
        isAccessibilityElement = false
        accessibilityContainerType = .semanticGroup
        accessibilityIdentifier = containerIdentifier
        accessibilityElements = [control]
    }

    /// Shows a read-only message (loading, not yet ranked, failure).
    ///
    /// - Parameters:
    ///   - view: The message view (carrying its own accessibility).
    ///   - plated: Draw the card plate behind it.
    func setMessage(_ view: UIView, plated: Bool) {
        place(view)
        view.isUserInteractionEnabled = true
        band.isHidden = true
        layer.borderWidth = 0
        control.isHidden = true
        control.isAccessibilityElement = false
        isAccessibilityElement = false
        accessibilityContainerType = .none
        accessibilityIdentifier = nil
        accessibilityElements = nil
        plate.backgroundColor = .clear
        _ = plated
    }
}
#endif
