#if os(iOS)
import FestivalAppSupport
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Sheet page

/// The Notifications sheet (``NotificationsSheet``), the native port of the web's
/// `MobileNotificationsModal`: a New / Older list of rows. Tapping a row marks it seen and,
/// when it has a destination, places its page on the presenting tab's stack (through `openRoute`)
/// and dismisses the sheet. Rows are decorated like the SwiftUI rows: media rail, marquee
/// title, bold-run message, colour-coded flag chips and the unread dot / chevron column.
@MainActor
final class UKNotificationsViewController: UIViewController, UICollectionViewDelegate, UKModalScrollProviding {
    private enum Section: Hashable { case new, older, allRead }

    private let session: FestivalSession
    private let openRoute: (AppRoute, UIViewController) -> Void
    private var center: NotificationsCenter { session.notificationsCenter }
    private var collection: UKNotificationsCollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, String>!
    private var stateView: UIView?
    private let observations = UKObservationBag()
    private var edgeSettings: UKAccessibilityObserver?
    private var opening = false
    private var shownKey: String?
    nonisolated(unsafe) private var settingsObserver: NSObjectProtocol?
    private var notificationsByID: [String: AppNotification] = [:]
    private var unread: Set<String> = []
    private var startsAtCoverPinLine = false

    var ukModalScrollView: UIScrollView? { collection }
    var ukModalRampOverride: CGFloat? { 0 }

    /// Creates the page.
    ///
    /// - Parameters:
    ///   - session: The shared session.
    ///   - openRoute: Dismisses the presented sheet and opens a route on its presenting tab.
    init(session: FestivalSession, openRoute: @escaping (AppRoute, UIViewController) -> Void) {
        self.session = session
        self.openRoute = openRoute
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
    }

    /// The sheet for the shell's bell.
    ///
    /// - Parameters:
    ///   - session: The shared session.
    ///   - openRoute: Dismisses the presented sheet and opens a tapped row's page.
    /// - Returns: The sheet's navigation controller.
    static func makeSheet(
        session: FestivalSession, openRoute: @escaping (AppRoute, UIViewController) -> Void
    ) -> UKSheetNavigationController {
        UKSheet.make(
            UKNotificationsViewController(session: session, openRoute: openRoute), title: "Notifications",
            closeIdentifier: "fst.notifications.close", size: .large
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let layout = UICollectionViewCompositionalLayout { [weak self] index, environment in
            var list = UICollectionLayoutListConfiguration(appearance: .plain)
            list.backgroundColor = .clear
            list.showsSeparators = false
            let section = self?.dataSource?.sectionIdentifier(for: index)
            list.headerMode = section == .allRead ? .none : .supplementary
            if section == .new, self?.startsAtCoverPinLine == true {
                list.headerTopPadding = 0
            }
            return NSCollectionLayoutSection.list(using: list, layoutEnvironment: environment)
        }
        collection = UKNotificationsCollectionView(frame: .zero, collectionViewLayout: layout)
        collection.didLayOutRows = { [weak self] in self?.updatePinnedRows() }
        if #available(iOS 26.0, *) { collection.topEdgeEffect.isHidden = true }
        collection.backgroundColor = .clear
        collection.showsHorizontalScrollIndicator = false
        collection.alwaysBounceHorizontal = false
        collection.delegate = self
        collection.translatesAutoresizingMaskIntoConstraints = false
        collection.accessibilityIdentifier = "fst.notifications.list"
        view.addSubview(collection)
        NSLayoutConstraint.activate([
            collection.leadingAnchor.constraint(equalTo: view.leadingAnchor), collection.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collection.topAnchor.constraint(equalTo: view.topAnchor), collection.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let cell = UICollectionView.CellRegistration<UKNotificationCell, String> { [unowned self] cell, _, id in
            guard let notification = notificationsByID[id] else { return }
            cell.configure(notification: notification, isUnread: unread.contains(id), session: session) { [weak self] in
                Task { await self?.open(notification) }
            }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collection) { collection, indexPath, id in
            collection.dequeueConfiguredReusableCell(using: cell, for: indexPath, item: id)
        }
        let header = UICollectionView.SupplementaryRegistration<UKNotificationHeader>(elementKind: UICollectionView.elementKindSectionHeader) {
            [unowned self] view, _, indexPath in
            let section = dataSource.snapshot().sectionIdentifiers[indexPath.section]
            view.configure(isFirst: section == .new)
        }
        dataSource.supplementaryViewProvider = { collection, _, indexPath in
            collection.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }
        settingsObserver = NotificationCenter.default.addObserver(forName: UKSettings.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.center.setExperimentalRanks(UserDefaults.standard.object(forKey: ExperimentalRanks.storageKey) as? Bool ?? ExperimentalRanks.defaultValue)
            }
        }
        edgeSettings = UKAccessibilityObserver { [weak self] in self?.updatePinnedRows() }
        center.setExperimentalRanks(UserDefaults.standard.object(forKey: ExperimentalRanks.storageKey) as? Bool ?? ExperimentalRanks.defaultValue)
        observations.observe { [weak self] in self?.render() }
        Task { await center.refresh(session: session) }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let layout = ukWindowLayout
        let startsAtPinLine = layout.pose == .folded && layout.sectionChrome.isVerticalBar
        if startsAtCoverPinLine != startsAtPinLine {
            startsAtCoverPinLine = startsAtPinLine
            collection.collectionViewLayout.invalidateLayout()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            center.markSeen(center.notifications.map(\.id))
        }
    }

    // MARK: Rendering

    private func render() {
        let hasPlayer = session.selectedPlayer != nil
        let state = center.state
        let notifications = center.notifications
        let unreadIDs = center.unreadIds
        let isGenerated = center.isGenerated
        let issue: ServiceIssue? = { if case let .failed(issue) = state { issue } else { nil } }()
        let key: String
        if !hasPlayer { key = "no-player" } else {
            switch state {
            case .idle, .loading: key = "loading"
            case .failed: key = "failed-\(issue.map { "\($0)" } ?? "")"
            case .loaded: key = notifications.isEmpty ? "empty-\(isGenerated)" : "list"
            }
        }
        if key != shownKey {
            shownKey = key
            stateView?.removeFromSuperview()
            stateView = nil
            collection.isHidden = false
            if !hasPlayer {
                show(UKEmptyStateView(
                    "Choose a Profile", systemImage: "person.crop.circle", subtitle: "Select a profile to see your notifications.",
                    identifier: "fst.notifications.no-player"
                ))
            } else {
                switch state {
                case .idle, .loading:
                    let loading = UKLoadingView(accessibilityLabel: "Loading Notifications", placement: .fill)
                    loading.hingeProvider = nil
                    show(loading)
                case let .failed(failure):
                    show(UKServiceStatusView(failure, title: "Notifications unavailable") { [weak self] in
                        guard let self else { return }
                        Task { await self.center.refresh(session: self.session) }
                    })
                case .loaded:
                    if notifications.isEmpty {
                        show(UKEmptyStateView(
                            "No notifications available", systemImage: "bell.slash",
                            subtitle: isGenerated
                                ? "Notifications will appear here when new high scores are set or global ranks improve. "
                                    + "Set new high scores and compete with friends to see them!"
                                : "Notifications may appear here after the next leaderboard update. Set new high scores "
                                    + "and compete with friends to see them!",
                            identifier: "fst.notifications.empty"
                        ))
                    }
                }
            }
        }
        guard hasPlayer, case .loaded = state, !notifications.isEmpty else { return }
        notificationsByID = Dictionary(notifications.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        unread = unreadIDs
        let new = notifications.filter { unreadIDs.contains($0.id) }.map(\.id)
        let older = notifications.filter { !unreadIDs.contains($0.id) }.map(\.id)
        var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
        if !new.isEmpty {
            snapshot.appendSections([.new])
            snapshot.appendItems(new, toSection: .new)
        }
        if !older.isEmpty {
            let section: Section = new.isEmpty ? .allRead : .older
            snapshot.appendSections([section])
            snapshot.appendItems(older, toSection: section)
        }
        let first = dataSource.snapshot().itemIdentifiers.isEmpty
        dataSource.apply(snapshot, animatingDifferences: false)
        var reconfigure = snapshot
        reconfigure.reconfigureItems(snapshot.itemIdentifiers)
        dataSource.apply(reconfigure, animatingDifferences: false)
        if first { fadeInRows() }
    }

    private func updatePinnedRows() {
        guard let collection, !collection.isHidden else { return }
        let visibleTop = collection.bounds.minY
        let pinLine = visibleTop + collection.adjustedContentInset.top
        var edge = pinLine
        for case let header as UKNotificationHeader in
            collection.visibleSupplementaryViews(ofKind: UICollectionView.elementKindSectionHeader) {
            let frame = header.convert(header.bounds, to: collection)
            let gap = min(max(frame.minY, 0), PinnedHeaderEdgeFade.maximumHeaderGap)
            let lift = header.isFirst ? min(gap, max(0, frame.minY - pinLine)) : 0
            header.setLift(lift)
            if frame.minY - lift <= pinLine + 1 { edge = max(edge, frame.maxY - lift) }
        }
        for case let row as UKNotificationCell in collection.visibleCells {
            let frame = row.convert(row.bounds, to: collection)
            row.updateFade(frame: frame, edge: edge, visibleTop: visibleTop, scrollOffset: pinLine)
        }
    }

    private func show(_ state: UIView) {
        collection.isHidden = true
        state.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(state)
        let body = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            state.leadingAnchor.constraint(equalTo: body.leadingAnchor), state.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            state.topAnchor.constraint(equalTo: body.topAnchor), state.bottomAnchor.constraint(equalTo: body.bottomAnchor),
        ])
        stateView = state
    }

    /// The first reveal's stagger (operator batch 7): rows fade in once, not when rebuilt.
    private func fadeInRows() {
        collection.layoutIfNeeded()
        for (index, cell) in collection.visibleCells.sorted(by: { $0.frame.minY < $1.frame.minY }).enumerated() {
            UKFadeIn.fadeIn(cell, staggerIndex: index)
        }
    }

    // MARK: Opening

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath), let notification = notificationsByID[id] else { return }
        Task { await open(notification) }
    }

    /// Mark the tapped row seen; when it has a destination, place that page in the app and
    /// dismiss the sheet. A row without a destination, or whose song is gone, keeps it open.
    private func open(_ notification: AppNotification) async {
        center.markSeen([notification.id])
        guard !opening else { return }
        opening = true
        defer { opening = false }
        let session = session
        guard let route = await NotificationRoute.resolve(
            notification.destination, song: { try await session.song(songId: $0) }
        ) else { return }
        openRoute(route, navigationController ?? self)
    }
}

/// Reads the native supplementary header's position after compositional layout pins it.
private final class UKNotificationsCollectionView: UICollectionView {
    var didLayOutRows: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        didLayOutRows?()
    }
}

// MARK: - Section header

/// "New" / "Older": white subheadline semibold, a heading.
@MainActor
final class UKNotificationHeader: UICollectionReusableView {
    private let label = UKLabel(style: .subheadline, weight: .semibold, lines: 1)
    private(set) var isFirst = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = [.header, .staticText]
        label.isAccessibilityElement = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        UKNotificationCell.fitHorizontally(label, in: self)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 10), label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Sets the heading and resets any visual lift from its last section.
    func configure(isFirst: Bool) {
        self.isFirst = isFirst
        label.text = isFirst ? "New" : "Older"
        accessibilityLabel = label.text
        setLift(0)
    }

    /// Draws the first heading at its pin line without moving its layout band.
    func setLift(_ lift: CGFloat) { label.transform = CGAffineTransform(translationX: 0, y: -lift) }
}

// MARK: - Row

/// One notification row (``NotificationRow``): a leading media rail, the title, the message
/// with bold runs, flag chips, and the trailing unread dot / chevron column. The row reads as
/// one element, "title. message", followed by the flag labels.
@MainActor
final class UKNotificationCell: UKSelfSizingCell {
    private enum Layout {
        static let horizontalInset: CGFloat = 16
        static let verticalInset: CGFloat = 21 // SwiftUI row padding (6) plus the plain List's inset (15).
        static let spacing: CGFloat = 10
        static let railWidth: CGFloat = 64
        static let actionWidth: CGFloat = 20
        static let unreadDiameter: CGFloat = 9 + 2 // Include the outward half of the 2 pt stroke.
    }

    /// Web `UNREAD_DOT_COLOR` (#FACC15).
    static let unreadDot = UIColor(red: 250 / 255, green: 204 / 255, blue: 21 / 255, alpha: 1)
    private let rail = UIView()
    private let title = UKMarqueeLabel("", font: UKFont.font(.headline, weight: nil), color: BrandUIColors.textPrimary)
    private let message = UKLabel(style: .subheadline)
    private let flags = UKNotificationFlagsView()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.forward"))
    private let dot = UIView()
    private let trailing = UIView()
    private var railContent: UIView?
    private lazy var edgeFade = UKPinnedHeaderEdgeFade(maskedView: contentView)
    private var hiddenInCut = false
    private let proxy = UKRowAccessibilityView()
    private var proxyLabel = ""
    private var proxyID = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        let texts = UIStackView(arrangedSubviews: [title, message, flags])
        texts.axis = .vertical
        texts.spacing = 4
        message.lineBreakStrategy = []
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let row = UIStackView(arrangedSubviews: [rail, texts, spacer, trailing])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = Layout.spacing
        row.translatesAutoresizingMaskIntoConstraints = false
        row.accessibilityElementsHidden = true
        contentView.addSubview(row)
        Self.fitHorizontally(row, in: contentView)
        rail.translatesAutoresizingMaskIntoConstraints = false
        trailing.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = BrandUIColors.textPrimary.withAlphaComponent(0.72)
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.font(.body, weight: .semibold))
        chevron.translatesAutoresizingMaskIntoConstraints = false
        dot.backgroundColor = Self.unreadDot
        dot.layer.cornerRadius = Layout.unreadDiameter / 2
        dot.layer.borderWidth = 2
        dot.layer.borderColor = BrandUIColors.surfaceSubtle.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        trailing.addSubview(chevron)
        trailing.addSubview(dot)
        NSLayoutConstraint.activate([
            rail.widthAnchor.constraint(equalToConstant: Layout.railWidth),
            rail.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
            spacer.widthAnchor.constraint(equalToConstant: 0),
            trailing.widthAnchor.constraint(equalToConstant: Layout.actionWidth),
            chevron.centerXAnchor.constraint(equalTo: trailing.centerXAnchor), chevron.centerYAnchor.constraint(equalTo: trailing.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: Layout.unreadDiameter),
            dot.heightAnchor.constraint(equalToConstant: Layout.unreadDiameter),
            dot.centerXAnchor.constraint(equalTo: trailing.centerXAnchor), dot.centerYAnchor.constraint(equalTo: trailing.centerYAnchor, constant: -24),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Layout.verticalInset),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Layout.verticalInset),
        ])
        UKPinnedHeaderEdgeFade.addSeparator(to: contentView, leading: texts.leadingAnchor, trailing: row.trailingAnchor)
        isAccessibilityElement = false
        contentView.addSubview(proxy)
        // The row reads as the one proxy button; its title, message and chips are not separate stops.
        accessibilityElements = [proxy]
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        edgeFade.layout()
        layoutProxy()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Fits sheet content inside either the normal List padding or the wider
    /// safe-area inset, without adding both on the Duo Close rail.
    ///
    /// - Parameters:
    ///   - content: The header label or row body.
    ///   - host: Its full-width supplementary view or cell content view.
    static func fitHorizontally(_ content: UIView, in host: UIView) {
        let safe = host.safeAreaLayoutGuide
        let leading = content.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: Layout.horizontalInset)
        let trailing = content.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -Layout.horizontalInset)
        [leading, trailing].forEach { $0.priority = .defaultHigh }
        NSLayoutConstraint.activate([
            leading, trailing,
            content.leadingAnchor.constraint(greaterThanOrEqualTo: host.leadingAnchor, constant: Layout.horizontalInset),
            content.trailingAnchor.constraint(lessThanOrEqualTo: host.trailingAnchor, constant: -Layout.horizontalInset),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: safe.leadingAnchor),
            content.trailingAnchor.constraint(lessThanOrEqualTo: safe.trailingAnchor),
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        railContent?.removeFromSuperview()
        railContent = nil
        edgeFade.updateRow(top: 0, edge: nil, scrollOffset: 0)
        hiddenInCut = false
        proxy.onActivate = nil
    }

    /// Binds a notification.
    func configure(notification: AppNotification, isUnread: Bool, session: FestivalSession, open: @escaping () -> Void) {
        title.text = notification.title
        message.attributedText = Self.message(notification.messageParts, traits: message.traitCollection)
        flags.configure(notification: notification)
        trailing.isHidden = !isUnread && notification.destination == nil
        chevron.isHidden = notification.destination == nil
        dot.isHidden = !isUnread
        setRail(notification.media, session: session)
        proxyLabel = NotificationRow.accessibilityLabel(notification)
        proxyID = "fst.notifications.row.\(notification.id)"
        proxy.onActivate = open
        setNeedsLayout()
    }

    /// Fades the row beneath the heading and skips wholly covered stops.
    func updateFade(frame: CGRect, edge: CGFloat, visibleTop: CGFloat, scrollOffset: CGFloat) {
        edgeFade.updateRow(top: frame.minY, edge: edge, scrollOffset: scrollOffset)
        let hidden = PinnedHeaderEdgeFade.hiddenInCut(
            rowTop: frame.minY, rowHeight: frame.height, edge: edge, visibleTop: visibleTop
        )
        if hiddenInCut != hidden {
            hiddenInCut = hidden
            layoutProxy()
        }
    }

    private func layoutProxy() {
        proxy.set(identifier: proxyID, label: proxyLabel, traits: .button,
                  frame: contentView.bounds, exposed: !hiddenInCut)
    }

    private func setRail(_ media: NotificationMedia, session: FestivalSession) {
        railContent?.removeFromSuperview()
        let content: UIView
        switch media {
        case let .song(albumArt):
            let art = UKArtworkTileView(size: 54)
            art.configure(raw: albumArt, session: session)
            content = art
        case let .songInstrumentGrid(albumArt, instruments):
            let art = UKArtworkTileView(size: 44)
            art.configure(raw: albumArt, session: session)
            let stack = UIStackView(arrangedSubviews: [art, Self.iconGrid(instruments)])
            stack.axis = .vertical
            stack.alignment = .center
            stack.spacing = 4
            content = stack
        case let .soloInstrument(instrument):
            content = UKInstrumentIconView(instrument, size: 36)
        }
        content.isAccessibilityElement = false
        content.translatesAutoresizingMaskIntoConstraints = false
        rail.addSubview(content)
        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: rail.centerXAnchor),
            content.centerYAnchor.constraint(equalTo: rail.centerYAnchor),
            rail.heightAnchor.constraint(greaterThanOrEqualTo: content.heightAnchor),
        ])
        railContent = content
    }

    private static func iconGrid(_ instruments: [Instrument]) -> UIView {
        let rows = stride(from: 0, to: instruments.count, by: 2).map { Array(instruments[$0..<min($0 + 2, instruments.count)]) }
        let grid = UIStackView()
        grid.axis = .vertical
        grid.alignment = .leading
        grid.spacing = 3
        for pair in rows {
            let line = UIStackView(arrangedSubviews: pair.map { UKInstrumentIconView($0, size: 18, hidesFromAccessibility: true) })
            line.axis = .horizontal
            line.spacing = 3
            if pair.count == 1 {
                let spacer = UIView()
                spacer.widthAnchor.constraint(equalToConstant: 18).isActive = true
                line.addArrangedSubview(spacer)
            }
            grid.addArrangedSubview(line)
        }
        return grid
    }

    /// Builds the message with Dynamic Type fonts and the SwiftUI text's interline spacing.
    ///
    /// - Parameters:
    ///   - parts: Plain and emphasized runs from `NotificationText`.
    ///   - traits: The message label's content-size traits.
    /// - Returns: The styled message.
    static func message(_ parts: [NotificationMessagePart], traits: UITraitCollection) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let body = UKFont.preferredFont(.subheadline)
        let bold = UKFont.preferredFont(.subheadline, bold: true)
        let paragraph = UKFont.isAccessibilitySize(traits)
            ? NSParagraphStyle.default
            : UKFont.swiftUILeading(.subheadline, traits: traits)
        for part in parts {
            result.append(NSAttributedString(string: part.text, attributes: [
                .font: part.emphasis ? bold : body, .foregroundColor: BrandUIColors.textPrimary, .paragraphStyle: paragraph,
            ]))
        }
        return result
    }

    override var fittingHeightScale: CGFloat { max(1, traitCollection.displayScale) }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        // The chips wrap to the text column's width, which is the row less the rail, the
        // trailing column and the padding.
        let action = trailing.isHidden ? 0 : Layout.actionWidth + Layout.spacing
        let safe = contentView.safeAreaInsets
        let padding = max(Layout.horizontalInset, safe.left) + max(Layout.horizontalInset, safe.right)
        let inset = padding + Layout.railWidth + Layout.spacing * 2 + action
        flags.availableWidth = max(0, layoutAttributes.size.width - inset)
        return super.preferredLayoutAttributesFitting(layoutAttributes)
    }
}

// MARK: - Flags

/// Web `NotificationFlags`: per-instrument flag lines for multi-chart rows, else one wrapping
/// line of chips.
@MainActor
final class UKNotificationFlagsView: UIStackView {
    /// The width the chips wrap to; set before measuring a row.
    var availableWidth: CGFloat = 0 {
        didSet { if availableWidth != oldValue { flows.forEach { $0.availableWidth = flowWidth($0) } } }
    }
    private var flows: [UKChipFlowView] = []
    private var iconWidth: [ObjectIdentifier: CGFloat] = [:]

    init() {
        super.init(frame: .zero)
        axis = .vertical
        spacing = 4
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func flowWidth(_ flow: UKChipFlowView) -> CGFloat {
        max(0, availableWidth - (iconWidth[ObjectIdentifier(flow)] ?? 0))
    }

    /// Binds a notification's flags.
    func configure(notification: AppNotification) {
        arrangedSubviews.forEach { $0.removeFromSuperview() }
        flows = []
        iconWidth = [:]
        if !notification.flagGroups.isEmpty {
            for group in notification.flagGroups {
                let icon = UKInstrumentIconView(group.instrument, size: 20, hidesFromAccessibility: true)
                icon.setContentHuggingPriority(.required, for: .horizontal)
                let flow = UKChipFlowView(kinds: group.flags)
                iconWidth[ObjectIdentifier(flow)] = 24
                let line = UIStackView(arrangedSubviews: [icon, flow])
                line.axis = .horizontal
                line.alignment = .center
                line.spacing = 4
                addArrangedSubview(line)
                flows.append(flow)
            }
        } else if !notification.flags.isEmpty {
            let flow = UKChipFlowView(kinds: notification.flags)
            addArrangedSubview(flow)
            flows.append(flow)
        }
        isHidden = arrangedSubviews.isEmpty
        flows.forEach { $0.availableWidth = flowWidth($0) }
    }
}

/// Wraps chips onto as many lines as the width needs (``NotificationChipFlow``).
@MainActor
final class UKChipFlowView: UIView {
    private let chips: [UIView]
    private let sizes: [CGSize]
    private var heightConstraint: NSLayoutConstraint!
    /// The width to wrap to; sets the height.
    var availableWidth: CGFloat = 0 {
        didSet { if availableWidth != oldValue { updateHeight() } }
    }

    /// Creates the flow.
    ///
    /// - Parameter kinds: The chips, in order.
    init(kinds: [NotificationFlagKind]) {
        chips = kinds.map(Self.chip)
        sizes = chips.map { $0.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize) }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        chips.forEach(addSubview)
        heightConstraint = heightAnchor.constraint(equalToConstant: sizes.map(\.height).max() ?? 0)
        heightConstraint.isActive = true
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKChipFlowView, _) in self.setNeedsLayout() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static func chip(_ kind: NotificationFlagKind) -> UIView {
        let label = UKLabel(kind.label, style: .caption1, weight: .semibold, lines: 1)
        let view = UIView()
        let hex = NotificationFlagChip.hex(kind)
        view.backgroundColor = UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1
        )
        view.layer.cornerRadius = 8
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = NotificationFlagChip.outlineWidth
        view.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6), label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: view.topAnchor, constant: 4), label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
        ])
        return view
    }

    private func frames(width: CGFloat) -> [CGRect] {
        NotificationChipFlow.arrange(sizes, width: width, spacing: 4)
    }

    private func updateHeight() {
        let all = frames(width: availableWidth > 0 ? availableWidth : .infinity)
        heightConstraint.constant = all.map(\.maxY).max() ?? 0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width > 0 ? bounds.width : availableWidth
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        for (chip, frame) in zip(chips, frames(width: width > 0 ? width : .infinity)) {
            chip.frame = rtl ? frame.offsetBy(dx: bounds.width - frame.minX * 2 - frame.width, dy: 0) : frame
        }
        if bounds.width > 0, abs(availableWidth - bounds.width) > 0.5, availableWidth == 0 { availableWidth = bounds.width }
    }
}
#endif
