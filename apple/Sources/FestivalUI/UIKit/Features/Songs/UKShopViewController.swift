#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Shop grid card

/// One Item Shop grid card (`gridOffer`): square cover art under a bottom scrim with the
/// title and artist, a status border and the Leaving Tomorrow badge; opens the official Shop.
final class UKShopGridCell: UICollectionViewCell {
    private let image = UIImageView()
    private let scrim = CAGradientLayer()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let border = CALayer()
    private let badge = UIView()
    private var raw: String?
    private var task: Task<Void, Never>?
    private var offer: ShopSong?
    private var highlight: ShopHighlight?
    private let mainProxy = UKRowAccessibilityView()
    private let badgeProxy = UKRowAccessibilityView()
    /// Opens the official Shop page.
    var onOpen: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.clipsToBounds = true
        contentView.layer.cornerRadius = 12
        contentView.layer.cornerCurve = .continuous
        contentView.backgroundColor = BrandUIColors.cardBackground
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        contentView.addSubview(image)
        scrim.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.85).cgColor]
        scrim.startPoint = CGPoint(x: 0.5, y: 0.5)
        scrim.endPoint = CGPoint(x: 0.5, y: 1)
        contentView.layer.addSublayer(scrim)
        titleLabel.font = UKFont.font(.headline)
        artistLabel.font = UKFont.font(.subheadline)
        for label in [titleLabel, artistLabel] {
            label.textColor = BrandUIColors.textPrimary
            label.adjustsFontForContentSizeCategory = true
            contentView.addSubview(label)
        }
        border.borderWidth = 2
        border.cornerRadius = 12
        border.cornerCurve = .continuous
        contentView.layer.addSublayer(border)
        contentView.addSubview(badge)
        contentView.addSubview(mainProxy)
        contentView.addSubview(badgeProxy)
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { task?.cancel() }

    /// Fills the card.
    func configure(offer: ShopSong, highlight: ShopHighlight?, session: FestivalSession) {
        self.offer = offer
        self.highlight = highlight
        titleLabel.text = offer.title
        artistLabel.text = offer.artist
        let color: UIColor
        switch highlight {
        case .leavingTomorrow: color = BrandUIColors.statusRed
        case .new: color = BrandUIColors.gold
        case nil: color = BrandUIColors.glassBorder
        }
        border.borderColor = color.cgColor
        badge.subviews.forEach { $0.removeFromSuperview() }
        badge.backgroundColor = .clear
        if highlight == .leavingTomorrow {
            let content = UIStackView()
            content.spacing = 4
            content.alignment = .center
            let icon = UIImageView(image: UIImage(systemName: "clock"))
            icon.tintColor = BrandUIColors.textPrimary
            let text = UKLabel(ShopHighlight.leavingTomorrow.label, style: .caption1, weight: .bold, lines: 1)
            content.addArrangedSubview(icon)
            content.addArrangedSubview(text)
            content.isLayoutMarginsRelativeArrangement = true
            content.layoutMargins = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
            content.backgroundColor = BrandUIColors.statusRed
            content.layer.cornerRadius = 14
            content.layer.masksToBounds = true
            content.frame = CGRect(origin: .zero, size: content.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize))
            badge.addSubview(content)
            badge.bounds.size = content.frame.size
        } else {
            badge.bounds.size = CGSize(width: 1, height: 1)
        }
        loadImage(raw: offer.albumArt, session: session)
        setNeedsLayout()
        rebuildAccessibility()
    }

    private func loadImage(raw: String?, session: FestivalSession) {
        guard raw != self.raw || image.image == nil else { return }
        task?.cancel()
        self.raw = raw
        image.image = nil
        guard let raw, !raw.isEmpty else { return }
        let edge = ArtworkTile.decodedEdge(for: max(bounds.width, 160))
        if let cached = session.cachedArtwork(raw: raw, maxPixels: edge) {
            image.image = UIImage(cgImage: cached)
            return
        }
        task = Task { [weak self] in
            guard let result = try? await session.preparedArtwork(raw: raw, maxPixels: edge), !Task.isCancelled else { return }
            self?.image.image = UIImage(cgImage: result.image)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        image.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scrim.frame = bounds
        border.frame = bounds
        CATransaction.commit()
        let width = max(0, bounds.width - 32)
        let artist = ceil(artistLabel.font.lineHeight)
        let title = ceil(titleLabel.font.lineHeight)
        artistLabel.frame = CGRect(x: 16, y: bounds.height - 16 - artist, width: width, height: artist)
        titleLabel.frame = CGRect(x: 16, y: artistLabel.frame.minY - 4 - title, width: width, height: title)
        badge.frame = CGRect(x: bounds.width - 12 - badge.bounds.width, y: 12, width: badge.bounds.width, height: badge.bounds.height)
        rebuildAccessibility()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        task?.cancel()
        onOpen = nil
    }

    private func rebuildAccessibility() {
        guard let offer else { return }
        let state = highlight.map { "\($0.label), " } ?? ""
        mainProxy.set(
            identifier: "fst.shop.external.\(offer.songId)",
            label: "\(offer.title), \(offer.artist), \(state)Open Official Item Shop", traits: .link, frame: contentView.bounds
        )
        mainProxy.onActivate = { [weak self] in self?.onOpen?() }
        if let highlight, !UIAccessibility.isVoiceOverRunning {
            badgeProxy.isHidden = false
            badgeProxy.set(
                identifier: highlight == .new ? "fst.shop.badge.new.\(offer.songId)" : "fst.shop.badge.leaving.\(offer.songId)",
                label: highlight.label, traits: .staticText, frame: badge.frame
            )
        } else {
            badgeProxy.isHidden = true
            badgeProxy.isAccessibilityElement = false
        }
    }
}

// MARK: - Shop filter sheet

/// The Filter Shop sheet (``ShopFilterSheet``): one switch per availability group and Reset.
final class UKShopFilterSheetController: UKFormViewController {
    private var draft: ShopOfferFilter
    private let onApply: (ShopOfferFilter) -> Void

    init(applied: ShopOfferFilter, onApply: @escaping (ShopOfferFilter) -> Void) {
        draft = applied
        self.onApply = onApply
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func refresh() {
        super.refresh()
        onApply(draft)
    }

    override func build() {
        let rows = ShopAvailability.allCases.map { group in
            toggleRow(
                group.label, identifier: "fst.shop.filter.\(group.rawValue)", accessibilityHint: ShopFilterSheet.hint(group),
                isOn: { [unowned self] in draft.includes(group) },
                set: { [unowned self] in draft = draft.setting(group, included: $0) }
            )
        }
        addSection(
            rows: rows, header: UKGroupSectionView.formHeading("Availability"),
            footer: "Turn a switch off to hide those offers. With every switch on, every offer shows."
        )
        let reset = buttonRow("Reset Filters", color: Self.destructive, identifier: "fst.shop.filter.reset") { [unowned self] in
            draft = ShopOfferFilter()
        }
        addSection(rows: [reset])
        scroll.accessibilityIdentifier = "fst.shop.filter.form"
    }
}

// MARK: - Item Shop

/// The Item Shop page (``ShopScreen``): public Shop offers as song rows or a cover grid, with
/// Sort, Filter and the List/Grid switch, the loading, failed, empty and paused states, and the
/// official bag link on every offer.
final class UKShopViewController: UIViewController, UICollectionViewDelegate, UKPageToolsProviding, UKPageMenuProviding {
    private let context: UKContext
    private let pushed: Bool
    private var session: FestivalSession { context.session }

    private struct Snapshot {
        let payload: ShopPayload
        let songsById: [String: Song]
        let songDetailsError: String?
        var catalogueObservation: Int?
    }

    private enum LoadState {
        case loading
        case loaded(Snapshot)
        case failed(ServiceIssue)
        var isLoading: Bool { if case .loading = self { true } else { false } }
    }

    private enum ShopSection: Hashable { case notices, offers }
    private enum ShopItem: Hashable { case notice(Int), offer(String) }

    private struct OfferLayout: Equatable {
        let mode: ShopViewMode
        let width: CGFloat
        let columns: Int
        let accessibilitySize: Bool
        let fold: HingeColumnSpec?
    }

    private static let offerInset: CGFloat = 16
    private var state = LoadState.loading
    private var retryRevision = 0
    private var loadedKey: [Int]?
    private var isVisible = false
    private var loadTask: Task<Void, Never>?
    private var offers: [ShopSong] = []
    private var disclosureItems: [(String, String, String?)] = []
    private var statusView: UIView?
    private var tools: [UKPageTool] = []
    private var toolsToken: [String] = []
    private var lastOfferLayout: OfferLayout?
    private var lastItems: [String] = []
    private let entranceScope = FestivalFadeInScope()
    private var entranceSettleTask: Task<Void, Never>?
    private var offerEntrances: [UICollectionViewCell: Task<Void, Never>] = [:]
    private var enteredOffers: Set<String> = []
    private var accessibilityObserver: UKAccessibilityObserver?
    private let observations = UKObservationBag()
    nonisolated(unsafe) private var defaultsObserver: NSObjectProtocol?
    private lazy var background = UKBackgroundRegistration(session: context.session, mode: .carousel)
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<ShopSection, ShopItem>!
    private var gate: UKReloadGate!

    init(context: UKContext, pushed: Bool) {
        self.context = context
        self.pushed = pushed
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) } }

    // MARK: Settings

    private var defaults: UserDefaults { .standard }
    /// A saved Boolean read like `@AppStorage` (a launch argument `-key YES` is a string).
    private func boolSetting(_ key: String) -> Bool { defaults.object(forKey: key) == nil ? false : defaults.bool(forKey: key) }
    private var preferredMode: ShopViewMode { ShopViewMode(rawValue: defaults.string(forKey: "fst.shop.viewMode") ?? "") ?? .grid }
    private var hideShop: Bool { boolSetting("fst.settings.hideShop") }
    private var disableHighlights: Bool { boolSetting("fst.settings.disableShopHighlighting") }
    private var isAX: Bool { traitCollection.preferredContentSizeCategory.isAccessibilityCategory }
    private var viewMode: ShopViewMode { traitCollection.horizontalSizeClass == .compact || isAX ? .list : preferredMode }
    private var showsViewToggle: Bool { traitCollection.horizontalSizeClass != .compact && !isAX }
    private var appliedFilter: ShopOfferFilter {
        ShopOfferFilter.decodeSaved(
            defaults.string(forKey: ShopOfferFilter.storageKey) ?? "",
            legacyNew: defaults.bool(forKey: ShopOfferFilter.legacyNewKey),
            legacyAvailable: defaults.bool(forKey: ShopOfferFilter.legacyAvailableKey),
            legacyLeavingTomorrow: defaults.bool(forKey: ShopOfferFilter.legacyLeavingTomorrowKey)
        )
    }
    private var appliedSort: ShopSortChoice {
        ShopSortChoice(
            mode: SongSortMode(rawValue: defaults.string(forKey: ShopSortChoice.modeKey) ?? "") ?? .title,
            ascending: (defaults.object(forKey: ShopSortChoice.ascendingKey) == nil ? true : defaults.bool(forKey: ShopSortChoice.ascendingKey))
        )
    }
    private var listColumns: Int { isAX ? 1 : WideColumns.count(layout: ukLayout) }

    private func displayedOffers(_ snapshot: Snapshot) -> ShopOfferSort.Result {
        ShopOfferSort.sorted(
            appliedFilter.filtered(snapshot.payload.sortedSongs), by: appliedSort,
            durations: ShopOfferSort.durations(
                catalogue: snapshot.songDetailsError == nil ? snapshot.songsById : nil,
                catalogueObservation: snapshot.catalogueObservation,
                shopObservation: snapshot.payload.observedPublicationId, currentObservation: session.publicationId
            )
        )
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .clear
        view.accessibilityIdentifier = "fst.shop.page"
        ukSetPageTitle("Item Shop")
        if pushed { ukInstallAccountItems() }
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.accessibilityIdentifier = "fst.shop.list"
        setContentScrollView(collectionView)
        configureDataSource()
        gate = UKReloadGate(key: viewMode, isLoading: true, spinnerLabel: "Loading Item Shop")
        gate.onReveal = { [weak self] in self?.revealOffers() }
        gate.spinnerHingeProvider = { [weak self] in self?.ukLayout.splitHinge }
        gate.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gate)
        NSLayoutConstraint.activate([
            gate.leadingAnchor.constraint(equalTo: view.leadingAnchor), gate.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gate.topAnchor.constraint(equalTo: view.topAnchor), gate.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        gate.contentView.addSubview(collectionView)
        collectionView.frame = gate.contentView.bounds
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        entranceScope.close()
        accessibilityObserver = UKAccessibilityObserver { [weak self] in
            if UKAccessibility.reduceMotion { self?.stopOfferEntrances() }
        }
        observations.observe { [weak self] in
            guard let self else { return }
            _ = context.shell?.layout
            recompute()
        }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UKSettings.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            // Text layout can register system defaults during a diffable snapshot apply.
            Task { @MainActor [weak self] in self?.recompute() }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isVisible = true
        UKRefreshCommands.shared.register(self) { [weak self] in self?.retryRevision += 1; self?.startLoad(force: true) }
        background.viewWillAppear()
        startLoad(force: false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        UKRefreshCommands.shared.unregister(self)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        background.viewDidDisappear()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if lastOfferLayout != offerLayout { recompute() }
    }

    // MARK: Load

    private func startLoad(force: Bool) {
        guard isVisible else { return }
        let key = [session.publicationRevision, retryRevision]
        if !force, case .loaded = state, loadedKey == key { return }
        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in await self?.load(key: key) }
    }

    private func load(key: [Int]) async {
        stopOfferEntrances()
        state = .loading
        recompute()
        do {
            let feed = try await session.shop()
            try Task.checkCancellation()
            if feed.sortedSongs.isEmpty {
                state = .loaded(Snapshot(payload: feed, songsById: [:], songDetailsError: nil))
                loadedKey = key
                recompute()
                return
            }
            let first = ShopOfferSort.sorted(appliedFilter.filtered(feed.sortedSongs), by: appliedSort, durations: nil).offers
            let paths = viewMode == .list
                ? ShopArtworkPrimePolicy.paths(for: first, limit: ShopArtworkPrimePolicy.limit(columns: listColumns)) : []
            async let primed: Void = primeArtwork(paths)
            var songsById: [String: Song] = [:]
            var detailsError: String?
            var observed: Int?
            do {
                let catalog = try await session.catalog()
                try Task.checkCancellation()
                observed = catalog.observedPublicationId
                songsById = Dictionary(catalog.catalog.songs.map { ($0.songId, $0) }, uniquingKeysWith: { first, _ in first })
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                detailsError = error.localizedDescription
            }
            await primed
            guard !Task.isCancelled else { return }
            state = .loaded(Snapshot(payload: feed, songsById: songsById, songDetailsError: detailsError, catalogueObservation: observed))
            loadedKey = key
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(ServiceIssue(error))
        }
        recompute()
    }

    private func primeArtwork(_ paths: [String]) async {
        guard !paths.isEmpty else { return }
        let session = session
        let maxPixels = Int(ShopRowMetrics.art * 3)
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await withTaskGroup(of: Void.self) { downloads in
                    for raw in paths { downloads.addTask { _ = try? await session.preparedArtwork(raw: raw, maxPixels: maxPixels) } }
                    await downloads.waitForAll()
                }
            }
            group.addTask { try? await Task.sleep(for: ShopArtworkPrimePolicy.timeout) }
            await group.next()
            group.cancelAll()
        }
    }

    // MARK: Layout

    /// Use the same visible span as the scroll layout, with the rail and offer margins removed.
    private var offerLayout: OfferLayout {
        let frame = collectionView.safeAreaLayoutGuide.layoutFrame.insetBy(dx: Self.offerInset, dy: 0)
        let mode = viewMode
        let grid = mode == .grid
        let columns = grid ? ShopGridPolicy.columnCount(width: frame.width, layout: ukLayout) : listColumns
        let spacing = grid ? ShopGridPolicy.spacing : WideColumns.spacing
        let fold = columns > 1 ? UKHinge.band(in: collectionView, layout: ukLayout, gutter: spacing, contentFrame: frame).map {
            HingeColumns.spec(
                band: $0, spacing: spacing, perSide: grid ? .fit(minimum: ShopGridPolicy.minimumFoldCardWidth) : .columns(1)
            )
        } : nil
        return OfferLayout(mode: mode, width: frame.width, columns: columns, accessibilitySize: isAX, fold: fold)
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, _ in
            guard let self else { return nil }
            let ids = self.dataSource?.snapshot().sectionIdentifiers ?? []
            let id = ids.indices.contains(index) ? ids[index] : .offers
            let full = NSCollectionLayoutDimension.fractionalWidth(1)
            if id == .notices {
                let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: full, heightDimension: .estimated(60)))
                let group = NSCollectionLayoutGroup.vertical(layoutSize: .init(widthDimension: full, heightDimension: .estimated(60)), subitems: [item])
                let section = NSCollectionLayoutSection(group: group)
                section.interGroupSpacing = 8
                section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16)
                return section
            }
            let layout = self.offerLayout
            let grid = layout.mode == .grid
            let height: NSCollectionLayoutDimension = grid ? .fractionalWidth(1 / CGFloat(layout.columns)) : .estimated(72)
            let gutter = grid ? ShopGridPolicy.spacing : WideColumns.spacing
            let group: NSCollectionLayoutGroup
            if let fold = layout.fold, grid {
                let widths = fold.widths
                let offsets = fold.offsets
                let rowHeight = max(fold.leadingColumnWidth, fold.trailingColumnWidth)
                group = .custom(layoutSize: .init(widthDimension: full, heightDimension: .absolute(rowHeight))) { _ in
                    zip(offsets, widths).map { x, width in
                        NSCollectionLayoutGroupCustomItem(frame: CGRect(x: x, y: 0, width: width, height: width))
                    }
                }
            } else if let fold = layout.fold {
                let items = fold.widths.map {
                    NSCollectionLayoutItem(layoutSize: .init(widthDimension: .absolute($0), heightDimension: height))
                }
                group = .horizontal(layoutSize: .init(widthDimension: full, heightDimension: height), subitems: items)
                group.interItemSpacing = .fixed(fold.gap)
            } else {
                let width = NSCollectionLayoutDimension.fractionalWidth(1 / CGFloat(layout.columns))
                let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: width, heightDimension: height))
                group = .horizontal(
                    layoutSize: .init(widthDimension: full, heightDimension: height), repeatingSubitem: item, count: layout.columns
                )
                group.interItemSpacing = .fixed(gutter)
            }
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = grid ? ShopGridPolicy.spacing : 6
            section.contentInsets = NSDirectionalEdgeInsets(
                top: grid ? 12 : 8, leading: Self.offerInset, bottom: grid ? 16 : 8, trailing: Self.offerInset
            )
            return section
        }
    }

    private func configureDataSource() {
        let rowRegistration = UICollectionView.CellRegistration<UKSongRowCell, String> { [weak self] cell, indexPath, id in
            self?.configureRow(cell, songId: id, index: indexPath.item)
        }
        let gridRegistration = UICollectionView.CellRegistration<UKShopGridCell, String> { [weak self] cell, _, id in self?.configureGrid(cell, songId: id) }
        let noticeRegistration = UICollectionView.CellRegistration<UKSongsNoticeCell, Int> { [weak self] cell, _, index in
            guard let self, self.disclosureItems.indices.contains(index) else { return }
            let item = self.disclosureItems[index]
            let view = UKFreshnessDisclosureView(message: item.0, symbol: item.1)
            view.accessibilityIdentifier = item.2
            cell.host(view)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { [weak self] collection, indexPath, item in
            switch item {
            case let .notice(index): return collection.dequeueConfiguredReusableCell(using: noticeRegistration, for: indexPath, item: index)
            case let .offer(id):
                if self?.viewMode == .grid { return collection.dequeueConfiguredReusableCell(using: gridRegistration, for: indexPath, item: id) }
                return collection.dequeueConfiguredReusableCell(using: rowRegistration, for: indexPath, item: id)
            }
        }
    }

    // MARK: Cells

    private var snapshotValue: Snapshot? { if case let .loaded(snapshot) = state { snapshot } else { nil } }

    private func configureRow(_ cell: UKSongRowCell, songId: String, index: Int) {
        guard let snapshot = snapshotValue, let offer = offers.first(where: { $0.songId == songId }) else { return }
        let large = isAX
        let row = ShopRowPolicy.row(
            for: offer, catalogue: snapshot.songsById, hidden: hideShop, highlightingDisabled: disableHighlights, reservesBag: !large
        )
        var input = UKSongRowInput(song: row.song, instrument: nil, session: session)
        input.highContrast = UKAccessibility.moreContrast || traitCollection.accessibilityContrast == .high
        input.shopOffer = row.decoration
        input.fieldOrder = UKSettings.songRowMetadataOrder()
        let layout = offerLayout
        let widths = layout.fold?.widths
        let columns = CGFloat(layout.columns)
        let width = widths.map { $0[index % $0.count] } ?? (layout.width - (columns - 1) * WideColumns.spacing) / columns
        cell.configure(input, width: width, traits: collectionView.traitCollection)
        cell.rowOpens = row.detailSong != nil
        cell.rowIdentifierOverride = row.detailSong != nil ? "fst.shop.song.\(offer.songId)" : "fst.shop.row.\(offer.songId)"
        let detail = row.detailSong
        cell.onOpen = { [weak self] in if let detail { self?.context.navigator?.push(.songDetail(detail)) } }
        let url = offer.shopUrl
        cell.shopLink = UKSongRowCell.ShopLink(
            label: "\(offer.title), Open Official Item Shop", identifier: "fst.shop.external.\(offer.songId)",
            action: { UIApplication.shared.open(url) }, below: large
        )
    }

    private func configureGrid(_ cell: UKShopGridCell, songId: String) {
        guard let offer = offers.first(where: { $0.songId == songId }) else { return }
        let highlight = ShopPresentationPolicy.highlight(for: offer, hidden: hideShop, highlightingDisabled: disableHighlights)
        cell.configure(offer: offer, highlight: highlight, session: session)
        let url = offer.shopUrl
        cell.onOpen = { UIApplication.shared.open(url) }
    }

    // MARK: Offer entrances

    /// Start the shared stagger only when the gate reveals a ready list or grid.
    private func revealOffers() {
        stopOfferEntrances()
        guard !offers.isEmpty, UKFadeIn.isEnabled, !UKAccessibility.reduceMotion else { return }
        enteredOffers.removeAll()
        entranceScope.noteContentOffset(collectionView.contentOffset.y)
        entranceScope.reset()
        for cell in collectionView.visibleCells {
            guard let indexPath = collectionView.indexPath(for: cell) else { continue }
            enterOffer(cell, at: indexPath)
        }
        let count = offers.count
        entranceSettleTask = Task { [weak self] in
            await FadeStagger.settle(afterRevealing: count) { self?.entranceScope.close() }
        }
    }

    /// Play an offer's entrance once per reveal, in displayed order.
    private func enterOffer(_ cell: UICollectionViewCell, at indexPath: IndexPath) {
        guard entranceScope.isOpen, case let .offer(id)? = dataSource.itemIdentifier(for: indexPath),
              enteredOffers.insert(id).inserted,
              let task = UKFadeIn.scopedEntrance(cell.contentView, index: indexPath.item, scope: entranceScope)
        else { return }
        offerEntrances[cell] = task
    }

    private func stopOfferEntrances() {
        entranceSettleTask?.cancel()
        entranceScope.close()
        for cell in Array(offerEntrances.keys) { finishOfferEntrance(cell) }
    }

    private func finishOfferEntrance(_ cell: UICollectionViewCell) {
        guard let task = offerEntrances.removeValue(forKey: cell) else { return }
        task.cancel()
        cell.contentView.layer.removeAllAnimations()
        cell.contentView.alpha = 1
        cell.contentView.transform = .identity
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        enterOffer(cell, at: indexPath)
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        finishOfferEntrance(cell)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.isDragging || scrollView.isDecelerating else { return }
        entranceScope.noteContentOffset(scrollView.contentOffset.y)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard case let .offer(id)? = dataSource.itemIdentifier(for: indexPath), let offer = offers.first(where: { $0.songId == id }),
              let snapshot = snapshotValue else { return }
        if viewMode == .grid {
            UIApplication.shared.open(offer.shopUrl)
        } else if let song = snapshot.songsById[offer.songId] {
            context.navigator?.push(.songDetail(song))
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard viewMode == .grid, case let .offer(id)? = dataSource.itemIdentifier(for: indexPath),
              let offer = offers.first(where: { $0.songId == id }) else { return nil }
        let song = snapshotValue?.songsById[offer.songId]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            var actions: [UIMenuElement] = []
            if let song {
                actions.append(UIAction(title: "View Song Details", image: UIImage(systemName: "music.note")) { _ in
                    self?.context.navigator?.push(.songDetail(song))
                })
            }
            actions.append(UIAction(title: "Open Official Item Shop", image: UIImage(systemName: "bag")) { _ in
                UIApplication.shared.open(offer.shopUrl)
            })
            return UIMenu(children: actions)
        }
    }

    // MARK: Recompute

    private func recompute() {
        guard isViewLoaded, dataSource != nil else { return }
        let layout = offerLayout
        let modeChanged = layout.mode != lastOfferLayout?.mode
        if modeChanged { stopOfferEntrances() }
        statusView?.removeFromSuperview()
        statusView = nil
        disclosureItems = []
        offers = []
        var snapshot = NSDiffableDataSourceSnapshot<ShopSection, ShopItem>()
        switch state {
        case .loading:
            collectionView.isHidden = true
        case let .failed(issue):
            collectionView.isHidden = true
            install(UKServiceStatusView(issue, title: "Item Shop unavailable") { [weak self] in
                self?.retryRevision += 1
                self?.startLoad(force: true)
            })
        case let .loaded(loaded):
            let result = displayedOffers(loaded)
            offers = result.offers
            if result.paused { disclosureItems.append((ShopScreen.sortPausedMessage, "arrow.up.arrow.down", "fst.shop.sort-paused")) }
            if loaded.payload.publicationId == nil {
                disclosureItems.append(("Showing live shop without publication verification", "info.circle", nil))
            }
            if let error = loaded.songDetailsError {
                disclosureItems.append(("Song details unavailable: \(error)", "exclamationmark.triangle", "fst.shop.song-details-error"))
            }
            if loaded.payload.sortedSongs.isEmpty {
                collectionView.isHidden = true
                install(UKEmptyStateView(ShopEmptyCopy.emptyTitle, systemImage: "bag", subtitle: ShopEmptyCopy.emptySubtitle, identifier: "fst.shop.empty"))
            } else if offers.isEmpty {
                collectionView.isHidden = true
                let empty = UKEmptyStateView(
                    ShopEmptyCopy.filteredTitle, systemImage: "line.3.horizontal.decrease", subtitle: ShopEmptyCopy.filteredSubtitle,
                    identifier: "fst.shop.filter-empty"
                )
                if disclosureItems.isEmpty {
                    install(empty)
                } else {
                    let notices = UIStackView(arrangedSubviews: disclosureItems.map { item in
                        let view = UKFreshnessDisclosureView(message: item.0, symbol: item.1)
                        view.accessibilityIdentifier = item.2
                        return view
                    })
                    notices.axis = .vertical
                    notices.spacing = 8
                    notices.isLayoutMarginsRelativeArrangement = true
                    notices.insetsLayoutMarginsFromSafeArea = false
                    notices.directionalLayoutMargins = .init(top: 0, leading: 16, bottom: 0, trailing: 16)
                    let stack = UIStackView(arrangedSubviews: [notices, empty])
                    stack.axis = .vertical
                    install(stack)
                }
            } else {
                collectionView.isHidden = false
                if !disclosureItems.isEmpty {
                    snapshot.appendSections([.notices])
                    snapshot.appendItems(disclosureItems.indices.map { .notice($0) }, toSection: .notices)
                }
                snapshot.appendSections([.offers])
                snapshot.appendItems(offers.map { .offer($0.songId) }, toSection: .offers)
            }
        }
        let items = snapshot.itemIdentifiers.map { "\($0)" } + disclosureItems.map(\.0)
        if layout != lastOfferLayout || items != lastItems {
            let reordered = items != lastItems
            if modeChanged {
                // The same offer uses a different cell and action when List becomes Grid.
                let retained = Set(dataSource.snapshot().itemIdentifiers)
                snapshot.reloadItems(snapshot.itemIdentifiers.filter {
                    if case .offer = $0 { return retained.contains($0) }
                    return false
                })
            }
            lastOfferLayout = layout
            lastItems = items
            collectionView.collectionViewLayout.invalidateLayout()
            dataSource.apply(snapshot, animatingDifferences: false)
            if reordered, collectionView.contentOffset.y > -collectionView.adjustedContentInset.top {
                UIView.performWithoutAnimation {
                    collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: false)
                }
                entranceScope.noteContentOffset(collectionView.contentOffset.y)
            }
        } else if !snapshot.itemIdentifiers.isEmpty {
            var current = dataSource.snapshot()
            current.reconfigureItems(current.itemIdentifiers)
            dataSource.apply(current, animatingDifferences: false)
        }
        gate.update(key: viewMode, isLoading: state.isLoading)
        updateTools()
    }

    private func install(_ content: UIView) {
        content.translatesAutoresizingMaskIntoConstraints = false
        gate.contentView.addSubview(content)
        let body = gate.contentView.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            content.topAnchor.constraint(equalTo: body.topAnchor),
            content.bottomAnchor.constraint(equalTo: body.bottomAnchor),
        ])
        statusView = content
    }

    // MARK: Tools

    var ukPageTools: [UKPageTool] { tools }

    func populatePageMenu(_ state: inout PageToolMenuState) {
        var commands = PageMenuCommands(
            sort: { [weak self] in self?.presentSort() },
            filter: { [weak self] in self?.presentFilter() }
        )
        if showsViewToggle {
            commands.layout = PageMenuLayoutChoice(isGrid: viewMode == .grid) { [weak self] grid in
                self?.selectViewMode(grid ? .grid : .list)
            }
        }
        state.page = commands
    }

    private func selectViewMode(_ mode: ShopViewMode) {
        guard viewMode != mode else { return }
        defaults.set(mode.rawValue, forKey: "fst.shop.viewMode")
        recompute()
    }

    private var sortPaused: Bool { snapshotValue.map { displayedOffers($0).paused } ?? false }

    private func updateTools() {
        let sort = appliedSort
        let filter = appliedFilter
        let token = [sort.accessibilityValue(paused: sortPaused), String(sort.isDefault), ShopScreen.filterAccessibilityValue(filter), String(filter.isActive), viewMode.rawValue, String(showsViewToggle)]
        guard token != toolsToken else { return }
        toolsToken = token
        let sortItem = UIBarButtonItem(title: "Sort", image: UIImage(systemName: "arrow.up.arrow.down"), primaryAction: UIAction { [weak self] _ in self?.presentSort() })
        sortItem.accessibilityLabel = "Sort Item Shop"
        sortItem.accessibilityValue = sort.accessibilityValue(paused: sortPaused)
        sortItem.accessibilityIdentifier = "fst.shop.sort"
        sortItem.tintColor = sort.isDefault ? BrandUIColors.accentBlue : BrandUIColors.gold
        let filterItem = UIBarButtonItem(title: "Filter", image: UIImage(systemName: "line.3.horizontal.decrease"), primaryAction: UIAction { [weak self] _ in self?.presentFilter() })
        filterItem.accessibilityLabel = "Filter Item Shop"
        filterItem.accessibilityValue = ShopScreen.filterAccessibilityValue(filter)
        filterItem.accessibilityIdentifier = "fst.shop.filter"
        filterItem.tintColor = filter.isActive ? BrandUIColors.gold : BrandUIColors.accentBlue
        var built = [UKPageTool(order: PageToolOrder.primary, item: sortItem), UKPageTool(order: PageToolOrder.secondary, item: filterItem)]
        if showsViewToggle {
            let grid = viewMode == .grid
            let toggle = UIBarButtonItem(
                title: grid ? "List View" : "Grid View", image: UIImage(systemName: grid ? "list.bullet" : "square.grid.2x2"),
                primaryAction: UIAction { [weak self] _ in
                    guard let self else { return }
                    self.selectViewMode(self.viewMode == .grid ? .list : .grid)
                }
            )
            toggle.accessibilityLabel = grid ? "List View" : "Grid View"
            toggle.accessibilityIdentifier = "fst.shop.view-toggle"
            built.append(UKPageTool(order: PageToolOrder.tertiary, item: toggle))
        }
        tools = built
        ukPageToolsDidChange()
    }

    private func presentSort() {
        let sheet = UKSongsSortSheetController(
            mode: appliedSort.mode, ascending: appliedSort.ascending, modes: ShopSortChoice.modes, identifier: "fst.shop.sort"
        ) { [weak self] mode, ascending in
            self?.defaults.set(mode.rawValue, forKey: ShopSortChoice.modeKey)
            self?.defaults.set(ascending, forKey: ShopSortChoice.ascendingKey)
            self?.recompute()
        }
        ukPresentSongsSheet(sheet, title: "Sort By", closeIdentifier: "fst.shop.sort.done", size: .compact)
    }

    private func presentFilter() {
        let sheet = UKShopFilterSheetController(applied: appliedFilter) { [weak self] filter in
            guard let self else { return }
            self.defaults.set(filter.encoded(), forKey: ShopOfferFilter.storageKey)
            self.defaults.set(false, forKey: ShopOfferFilter.legacyNewKey)
            self.defaults.set(false, forKey: ShopOfferFilter.legacyAvailableKey)
            self.defaults.set(false, forKey: ShopOfferFilter.legacyLeavingTomorrowKey)
            self.recompute()
        }
        ukPresentSongsSheet(sheet, title: "Filter Shop", closeIdentifier: "fst.shop.filter.done", size: .compact)
    }
}
#endif
