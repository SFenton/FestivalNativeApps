#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Press wash

/// A 6% white wash on press (the web row's `rowItemPressed`), for custom row controls.
@MainActor
enum UKProfilePress {
    /// Wires press feedback onto a control.
    ///
    /// - Parameter control: The control; its background is washed while pressed.
    static func attach(to control: UIControl) {
        control.addAction(UIAction { [weak control] _ in control?.backgroundColor = UIColor.white.withAlphaComponent(0.06) }, for: .touchDown)
        control.addAction(
            UIAction { [weak control] _ in control?.backgroundColor = nil },
            for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit]
        )
    }
}

// MARK: - Band row

/// One player-band card: member names with their instrument icons and appearance count
/// (``PlayerBandRow``). On its own card with an in-card chevron on the Player Bands list;
/// `grouped` drops the card for rows inside a flush group card (the profile's inline Bands
/// section, owner #596). One button element, spoken as its members and shared song count.
final class UKPlayerBandRowView: UIControl {
    private let entry: PlayerBandEntry
    private let card: UKCardView?
    private let onOpen: (AppRoute) -> Void

    /// Creates the row.
    ///
    /// - Parameters:
    ///   - entry: The band.
    ///   - grouped: The row sits in a group card and draws none of its own.
    ///   - identifier: Accessibility identifier override (default `fst.player-bands.row.<id>`).
    ///   - onOpen: Opens the band's page.
    init(entry: PlayerBandEntry, grouped: Bool, identifier: String? = nil, onOpen: @escaping (AppRoute) -> Void) {
        self.entry = entry
        self.onOpen = onOpen
        card = grouped ? nil : UKCardView(cornerRadius: UKProfileMetrics.rowCornerRadius)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build(grouped: grouped)
        isAccessibilityElement = true
        accessibilityLabel = PlayerBandRow.spokenLabel(entry)
        accessibilityHint = "Opens band"
        accessibilityTraits = .button
        accessibilityIdentifier = identifier ?? "fst.player-bands.row.\(entry.id)"
        addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onOpen(self.route)
        }, for: .touchUpInside)
        if grouped { UKProfilePress.attach(to: self) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var route: AppRoute {
        .band(bandId: entry.bandId, name: entry.membersLabel, bandType: entry.bandType, teamKey: entry.teamKey)
    }

    private func build(grouped: Bool) {
        if let card {
            card.isUserInteractionEnabled = false
            ukPin(card)
        }
        let details = UIStackView()
        details.axis = .vertical
        details.spacing = 8
        details.isUserInteractionEnabled = false
        for member in entry.members {
            let name = UKLabel(member.resolvedName, style: .body, lines: 1)
            let icons = UIStackView(arrangedSubviews: member.chartedInstruments.map {
                UKInstrumentIconView($0, size: 22, hidesFromAccessibility: true)
            })
            icons.spacing = 4
            icons.setContentHuggingPriority(.required, for: .horizontal)
            icons.setContentCompressionResistancePriority(.required, for: .horizontal)
            let row = UIStackView(arrangedSubviews: [name, icons])
            row.spacing = 8
            row.alignment = .center
            details.addArrangedSubview(row)
            nameLabels.append(name)
        }
        details.addArrangedSubview(UKLabel("\(entry.appearanceCount.formatted()) songs together", style: .caption1))
        let chevron = UIImageView(image: UIImage(systemName: "chevron.forward"))
        chevron.tintColor = BrandUIColors.textMuted
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.font(.footnote, weight: .semibold))
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.isUserInteractionEnabled = false
        let row = UIStackView(arrangedSubviews: [details, chevron])
        row.spacing = 8
        row.alignment = .center
        row.isUserInteractionEnabled = false
        ukPin(row, insets: UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12))
        heightAnchor.constraint(greaterThanOrEqualToConstant: UKLeaderboardRowMetrics.minHeight).isActive = true
        applyLineLimit()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKPlayerBandRowView, _) in self.applyLineLimit() }
    }

    private var nameLabels: [UKLabel] = []

    private func applyLineLimit() {
        let lines = UKFont.isAccessibilitySize(traitCollection) ? 0 : 1
        nameLabels.forEach { $0.numberOfLines = lines }
    }

    override var isHighlighted: Bool {
        didSet { if card != nil { alpha = isHighlighted ? 0.7 : 1 } }
    }
}

// MARK: - Pager

/// The board pager: First, Previous, a "page / total" badge, Next, Last (``RankingsPagerView``):
/// 44 pt capsule arrows around a 12 pt-radius card, one container read in that order, the
/// badge adjustable (swipe up or down to step).
final class UKProfilePagerView: UIView {
    private let idPrefix: String
    /// Called with the destination page.
    var onChange: (Int) -> Void
    private var state: RankingsPagerState
    private let badge = UKProfilePagerBadge()
    private let badgeLabel = UKLabel(style: .body, weight: .semibold, monospacedDigit: true, lines: 1, alignment: .center)
    private var arrows: [(RankingsPagerAction, UKProfileArrowButton)] = []

    /// Creates the pager.
    ///
    /// - Parameters:
    ///   - idPrefix: Identifier prefix (`fst.player-bands`).
    ///   - onChange: Called with the destination page.
    init(idPrefix: String, onChange: @escaping (Int) -> Void) {
        self.idPrefix = idPrefix
        self.onChange = onChange
        state = RankingsPagerState(page: 1, totalPages: 1)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
        show(page: 1, totalPages: 1)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func build() {
        let specs: [(RankingsPagerAction, String, String, String)] = [
            (.first, "chevron.backward.2", "First page", "page-first"),
            (.previous, "chevron.backward", "Previous page", "page-previous"),
            (.next, "chevron.forward", "Next page", "page-next"),
            (.last, "chevron.forward.2", "Last page", "page-last"),
        ]
        arrows = specs.map { action, symbol, label, id in
            let button = UKProfileArrowButton(symbol: symbol, label: label, identifier: "\(idPrefix).\(id)")
            button.addAction(UIAction { [weak self] _ in
                guard let self, let page = self.state.destination(for: action) else { return }
                self.onChange(page)
            }, for: .touchUpInside)
            return (action, button)
        }
        let card = UKCardView(cornerRadius: 12)
        card.isUserInteractionEnabled = false
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.ukPin(card)
        badge.ukPin(badgeLabel, insets: UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14))
        badgeLabel.adjustsFontSizeToFitWidth = true
        badgeLabel.minimumScaleFactor = 0.7
        badge.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        badge.isAccessibilityElement = true
        badge.accessibilityLabel = "Page"
        badge.accessibilityTraits = .adjustable
        badge.accessibilityIdentifier = "\(idPrefix).page-info"
        badge.onStep = { [weak self] action in self?.step(action) }
        let row = UIStackView(arrangedSubviews: [arrows[0].1, arrows[1].1, badge, arrows[2].1, arrows[3].1])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .fill
        ukPin(row, insets: UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16))
        ukContain(identifier: "\(idPrefix).pager")
    }

    /// Shows a page.
    ///
    /// - Parameters:
    ///   - page: Current 1-based page.
    ///   - totalPages: Page count.
    func show(page: Int, totalPages: Int) {
        state = RankingsPagerState(page: page, totalPages: totalPages)
        badgeLabel.text = state.label
        badge.accessibilityValue = state.accessibilityValue
        for (action, button) in arrows { button.isEnabled = state.destination(for: action) != nil }
    }

    fileprivate func step(_ action: RankingsPagerAction) {
        if let page = state.destination(for: action) { onChange(page) }
    }
}

/// The pager's "page / total" badge: adjustable, so swiping up or down steps a page.
private final class UKProfilePagerBadge: UIView {
    var onStep: ((RankingsPagerAction) -> Void)?
    override func accessibilityIncrement() { onStep?(.next) }
    override func accessibilityDecrement() { onStep?(.previous) }
}

/// A 44 pt capsule arrow (web `arrowBtnBase`), faded when disabled.
final class UKProfileArrowButton: UIControl {
    private let glyph: UIImageView

    /// Creates the arrow.
    ///
    /// - Parameters:
    ///   - symbol: Chevron symbol.
    ///   - label: Spoken action.
    ///   - identifier: Accessibility identifier.
    init(symbol: String, label: String, identifier: String) {
        glyph = UIImageView(image: UIImage(systemName: symbol))
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let card = UKCardView(cornerRadius: 22, capsule: true)
        card.isUserInteractionEnabled = false
        ukPin(card)
        glyph.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.font(.body, weight: .semibold))
        glyph.contentMode = .center
        glyph.isUserInteractionEnabled = false
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 44),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            glyph.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        isAccessibilityElement = true
        accessibilityLabel = label
        accessibilityIdentifier = identifier
        accessibilityTraits = .button
        applyState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isEnabled: Bool {
        didSet { applyState() }
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.7 : 1 }
    }

    private func applyState() {
        glyph.tintColor = isEnabled ? BrandUIColors.textPrimary : BrandUIColors.textDisabled
        accessibilityTraits = isEnabled ? .button : [.button, .notEnabled]
    }
}

// MARK: - Bands preview section

/// The player profile's inline "{name}'s Bands" section (``PlayerBandsPreviewSection``): a
/// section title with View All, then Duos, Trios and Quads, each one card of up to six band
/// rows ending with the purple "View All Bands (N)" when the group has more, or a "No Bands
/// Yet" card when empty. It loads on its own through ``FestivalSession/playerBandsPreview(accountId:)``
/// so the rest of the profile never waits for it, and a failure stays inside the section.
final class UKPlayerBandsPreviewSectionView: UIView, UKWidthDependent {
    private let session: FestivalSession
    private let accountId: String
    private let displayName: String
    private let routeDisplayName: String?
    private let navigate: (AppRoute) -> Void
    private let layoutProvider: () -> DeviceLayout
    private var phase: PlayerBandsPreviewSection.Phase = .loading
    private let column = UIStackView()
    private var body: UIView?
    private var width: CGFloat = 0
    private var loadTask: Task<Void, Never>?
    private var grid: UKProfileColumnGrid?

    /// Creates the section.
    ///
    /// - Parameters:
    ///   - session: Shared app session.
    ///   - accountId: Viewed account.
    ///   - displayName: Name for the section title.
    ///   - routeDisplayName: Name for the pushed Player Bands title.
    ///   - layoutProvider: The window layout.
    ///   - navigate: Pushes a route.
    init(
        session: FestivalSession, accountId: String, displayName: String, routeDisplayName: String?,
        layoutProvider: @escaping () -> DeviceLayout, navigate: @escaping (AppRoute) -> Void
    ) {
        self.session = session
        self.accountId = accountId
        self.displayName = displayName
        self.routeDisplayName = routeDisplayName
        self.layoutProvider = layoutProvider
        self.navigate = navigate
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        column.axis = .vertical
        column.spacing = 12
        ukPin(column)
        column.addArrangedSubview(makeHeader())
        ukContain(identifier: "fst.player.bands")
        render()
        load(resetting: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { loadTask?.cancel() }

    /// Whether the section keeps the Quick Links "Bands" entry (always).
    func prepare(width: CGFloat) {
        guard abs(width - self.width) > 0.5 else { return }
        self.width = width
        body?.ukPrepare(width: width)
    }

    // MARK: Header

    private func makeHeader() -> UIView {
        let title = UKSectionHeaderView("\(displayName)'s Bands")
        let viewAll = UKViewAllButton(identifier: "fst.player.bands-link", listName: "\(displayName)'s Bands") { [weak self] in
            guard let self else { return }
            self.navigate(.playerBands(accountId: self.accountId, displayName: self.routeDisplayName ?? self.displayName, group: .all))
        }
        let row = UIStackView(arrangedSubviews: [title, viewAll])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        return UKProfileInset(row, horizontal: 4)
    }

    // MARK: Render

    private func render() {
        body?.removeFromSuperview()
        grid = nil
        let next: UIView
        switch phase {
        case .loading:
            let loading = UKLoadingView(accessibilityLabel: "Loading bands")
            loading.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            loading.accessibilityIdentifier = "fst.player.bands.loading"
            next = loading
        case let .failed(issue):
            let section = UKGroupSectionView()
            let status = UKServiceStatusInlineView(issue, scope: "player.bands", fallbackTitle: "Bands unavailable") { [weak self] in
                self?.retry()
            }
            section.setRows([status])
            section.ukContain(identifier: "fst.player.bands.error")
            next = section
        case let .loaded(preview):
            next = groups(preview)
        }
        column.addArrangedSubview(next)
        body = next
        next.ukPrepare(width: width)
    }

    private func groups(_ preview: PlayerBandsPreview) -> UIView {
        let sections = preview.groups.map(groupSection)
        if ukLayout.widthClass == .regular {
            let grid = UKProfileColumnGrid(columns: .fixed(2), spacing: 20)
            grid.layoutProvider = layoutProvider
            grid.setCells(sections)
            self.grid = grid
            return grid
        }
        let stack = UKProfileSection(sections, spacing: 12)
        return stack
    }

    private var ukLayout: DeviceLayout { layoutProvider() }

    private func groupSection(_ group: PlayerBandsPreview.Group) -> UIView {
        let heading = UKLabel(group.group.label, style: .title3, weight: .bold).asHeader()
        heading.accessibilityIdentifier = "fst.player.bands.group.\(group.group.rawValue)"
        heading.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        let content: UIView
        if group.entries.isEmpty {
            content = emptyCard(group.group)
        } else {
            let section = UKGroupSectionView(rows: .flush(separatorInset: 12))
            section.setRows(group.entries.map { entry in
                UKPlayerBandRowView(entry: entry, grouped: true) { [weak self] route in self?.navigate(route) }
            })
            if group.hasMore {
                let action = UKProfilePurpleActionButton(
                    title: PlayerBandsPreviewSection.viewAllTitle(group),
                    identifier: "fst.player.bands.view-all.\(group.group.rawValue)", card: group.group.label
                )
                action.onTap = { [weak self] in
                    guard let self else { return }
                    self.navigate(.playerBands(
                        accountId: self.accountId, displayName: self.routeDisplayName ?? self.displayName, group: group.group
                    ))
                }
                section.setAction(action)
            }
            section.ukContain(identifier: "fst.player.bands.card.\(group.group.rawValue)")
            content = section
            UKFadeIn.fadeIn(section)
        }
        let stack = UKProfileSection([heading, content], spacing: 8)
        stack.ukContain(identifier: "fst.player.bands.group-container.\(group.group.rawValue)")
        stack.accessibilityIdentifier = nil
        stack.accessibilityContainerType = .semanticGroup
        return stack
    }

    /// Web `InstrumentEmptyState`: a scoped title and next step on the shared card.
    private func emptyCard(_ group: PlayerBandGroup) -> UIView {
        let card = UKCardView(cornerRadius: 12)
        let title = UKLabel("No Bands Yet", style: .headline)
        let subtitle = UKLabel("Band lineups will appear here once this player posts band scores.", style: .subheadline)
        let stack = UIStackView(arrangedSubviews: [title, subtitle])
        stack.axis = .vertical
        stack.spacing = 4
        card.embed(stack, insets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        card.isAccessibilityElement = true
        card.accessibilityLabel = "No Bands Yet, Band lineups will appear here once this player posts band scores."
        card.accessibilityIdentifier = "fst.player.bands.empty.\(group.rawValue)"
        UKFadeIn.fadeIn(card)
        return card
    }

    // MARK: Load

    private func retry() {
        phase = .loading
        render()
        load(resetting: false)
    }

    /// Read the three group previews (three keyless player-bands reads).
    private func load(resetting: Bool) {
        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let preview = try await self.session.playerBandsPreview(accountId: self.accountId)
                try Task.checkCancellation()
                self.phase = .loaded(preview)
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.phase = .failed(ServiceIssue(error))
            }
            self.render()
        }
    }
}
#endif
