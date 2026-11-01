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
            label: "\(offer.title), \(offer.artist), \(state)Open Official Item Shop", traits: .button, frame: contentView.bounds
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
            "Availability", rows: rows,
            footnotes: [footnote("Turn a switch off to hide those offers. With every switch on, every offer shows.")]
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
final class UKShopViewController: UIViewController, UICollectionViewDelegate, UKPageToolsProviding {
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

    private var state = LoadState.loading
    private var retryRevision = 0
    private var loadedKey: [Int]?
    private var isVisible = false
    private var loadTask: Task<Void, Never>?
    private var offers: [ShopSong] = []
    private var disclosureItems: [(String, String, String?)] = []
    private var statusView: UIView?
    private var tools: [UKPageTool] = []
    private var sheetObserver: UKSongsSheetDismissObserver?
    private var toolsToken: [String] = []
    private var lastLayoutKey: [String] = []
    private var lastItems: [String] = []
    private var lastWidth: CGFloat = 0
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
        ukSetPageTitle("Item Shop", floatsPageTools: ukShell?.floatsPageTools ?? false)
        if pushed { ukInstallAccountItems() }
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.accessibilityIdentifier = "fst.shop.list"
        setContentScrollView(collectionView)
        configureDataSource()
        gate = UKReloadGate(key: viewMode, isLoading: true, spinnerLabel: "Loading Item Shop")
        gate.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gate)
        NSLayoutConstraint.activate([
            gate.leadingAnchor.constraint(equalTo: view.leadingAnchor), gate.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gate.topAnchor.constraint(equalTo: view.topAnchor), gate.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        gate.contentView.addSubview(collectionView)
        collectionView.frame = gate.contentView.bounds
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        observations.observe { [weak self] in self?.recompute() }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UKSettings.didChange, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.recompute() } }
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
        if collectionView.bounds.width != lastWidth {
            lastWidth = collectionView.bounds.width
            recompute()
        }
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
            if self.viewMode == .grid {
                let width = self.collectionView.bounds.width - 32
                let columns = max(1, ShopGridPolicy.columnCount(width: width, layout: self.ukLayout))
                let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1.0 / CGFloat(columns)), heightDimension: .fractionalWidth(1.0 / CGFloat(columns))))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: full, heightDimension: .fractionalWidth(1.0 / CGFloat(columns))), repeatingSubitem: item, count: columns)
                group.interItemSpacing = .fixed(ShopGridPolicy.spacing)
                let section = NSCollectionLayoutSection(group: group)
                section.interGroupSpacing = ShopGridPolicy.spacing
                section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 16, trailing: 16)
                return section
            }
            let columns = max(1, self.listColumns)
            let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1.0 / CGFloat(columns)), heightDimension: .estimated(72)))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: full, heightDimension: .estimated(72)), repeatingSubitem: item, count: columns)
            group.interItemSpacing = .fixed(SongGridPolicy.spacing)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 6
            section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
            return section
        }
    }

    private func configureDataSource() {
        let rowRegistration = UICollectionView.CellRegistration<UKSongRowCell, String> { [weak self] cell, _, id in self?.configureRow(cell, songId: id) }
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

    private func configureRow(_ cell: UKSongRowCell, songId: String) {
        guard let snapshot = snapshotValue, let offer = offers.first(where: { $0.songId == songId }) else { return }
        let large = isAX
        let row = ShopRowPolicy.row(
            for: offer, catalogue: snapshot.songsById, hidden: hideShop, highlightingDisabled: disableHighlights, reservesBag: !large
        )
        var input = UKSongRowInput(song: row.song, instrument: nil, session: session)
        input.highContrast = UKAccessibility.moreContrast || traitCollection.accessibilityContrast == .high
        input.shopOffer = row.decoration
        let columns = CGFloat(max(1, listColumns))
        let width = (collectionView.bounds.width - 32 - (columns - 1) * SongGridPolicy.spacing) / columns
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
        gate.update(key: viewMode, isLoading: state.isLoading)
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
                let stack = UIStackView(arrangedSubviews: disclosureItems.map { item in
                    let view = UKFreshnessDisclosureView(message: item.0, symbol: item.1)
                    view.accessibilityIdentifier = item.2
                    return view
                } + [empty])
                stack.axis = .vertical
                stack.spacing = 8
                install(stack)
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
        let layoutKey = [viewMode.rawValue, "\(listColumns)", "\(Int(collectionView.bounds.width))", "\(isAX)"]
        let items = snapshot.itemIdentifiers.map { "\($0)" } + disclosureItems.map(\.0)
        if layoutKey != lastLayoutKey || items != lastItems {
            let reordered = items != lastItems
            lastLayoutKey = layoutKey
            lastItems = items
            collectionView.collectionViewLayout.invalidateLayout()
            dataSource.apply(snapshot, animatingDifferences: false)
            if reordered, collectionView.contentOffset.y > -collectionView.adjustedContentInset.top {
                UIView.performWithoutAnimation {
                    collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: false)
                }
            }
        } else if !snapshot.itemIdentifiers.isEmpty {
            var current = dataSource.snapshot()
            current.reconfigureItems(current.itemIdentifiers)
            dataSource.apply(current, animatingDifferences: false)
        }
        updateTools()
    }

    private func install(_ content: UIView) {
        content.translatesAutoresizingMaskIntoConstraints = false
        gate.contentView.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: gate.contentView.leadingAnchor, constant: content is UIStackView ? 16 : 0),
            content.trailingAnchor.constraint(equalTo: gate.contentView.trailingAnchor, constant: content is UIStackView ? -16 : 0),
            content.topAnchor.constraint(equalTo: gate.contentView.safeAreaLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: gate.contentView.safeAreaLayoutGuide.bottomAnchor),
        ])
        statusView = content
    }

    // MARK: Tools

    var ukPageTools: [UKPageTool] { tools }

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
                    self.defaults.set((self.viewMode == .grid ? ShopViewMode.list : .grid).rawValue, forKey: "fst.shop.viewMode")
                    self.recompute()
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
        ukPresentSongsSheet(sheet, title: "Sort By", closeIdentifier: "fst.shop.sort.done", size: .compact) { sheetObserver = $0 }
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
        ukPresentSongsSheet(sheet, title: "Filter Shop", closeIdentifier: "fst.shop.filter.done", size: .compact) { sheetObserver = $0 }
    }
}
#endif
