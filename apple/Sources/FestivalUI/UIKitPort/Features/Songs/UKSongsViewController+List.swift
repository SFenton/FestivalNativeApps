#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Layout and data source

extension UKSongsViewController {
    /// Cards per list row: two side by side in a landscape regular window, else one.
    var songColumns: Int {
        SongProfilePanelPolicy.gridColumns(
            layout: ukLayout, hasSelectedProfile: session.selectedPlayer != nil || session.selectedBand != nil
        )
    }

    /// Rows may split into song | profile score cards: regular width and height.
    var allowsProfilePanel: Bool {
        let layout = ukLayout
        return layout.widthClass == .regular && layout.heightClass == .regular
    }

    /// Width to keep clear of the trailing A–Z rail beyond the rows' own margin.
    var scrubberExtraInset: CGFloat {
        guard showsIndex else { return 0 }
        let reserve = UKSongSectionIndexView.width(for: traitCollection.preferredContentSizeCategory)
            + max(2, ukLayout.cutoutInsets.trailing) + 6
        return max(0, reserve - 16)
    }

    func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, _ in
            guard let self else { return nil }
            return self.sectionLayout(at: index)
        }
    }

    private func sectionLayout(at index: Int) -> NSCollectionLayoutSection {
        let ids = dataSource?.snapshot().sectionIdentifiers ?? []
        let id = ids.indices.contains(index) ? ids[index] : .notices
        let fullWidth = NSCollectionLayoutDimension.fractionalWidth(1)
        if id == .notices {
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: fullWidth, heightDimension: .estimated(60)))
            let group = NSCollectionLayoutGroup.vertical(
                layoutSize: NSCollectionLayoutSize(widthDimension: fullWidth, heightDimension: .estimated(60)), subitems: [item]
            )
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 8
            section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16)
            return section
        }
        let columns = max(1, songColumns)
        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0 / CGFloat(columns)), heightDimension: .estimated(72))
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(widthDimension: fullWidth, heightDimension: .estimated(72)),
            repeatingSubitem: item, count: columns
        )
        group.interItemSpacing = .fixed(SongGridPolicy.spacing)
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 4
        section.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16 + scrubberExtraInset)
        if groups != nil {
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: NSCollectionLayoutSize(widthDimension: fullWidth, heightDimension: .estimated(32)),
                elementKind: UKSongsSectionHeaderView.kind, alignment: .top
            )
            section.boundarySupplementaryItems = [header]
            section.supplementariesFollowContentInsets = false
        }
        return section
    }

    func configureDataSource() {
        let songRegistration = UICollectionView.CellRegistration<UKSongRowCell, String> { [weak self] cell, _, id in
            self?.configure(cell, songId: id)
        }
        let noticeRegistration = UICollectionView.CellRegistration<UKSongsNoticeCell, Int> { [weak self] cell, _, index in
            guard let self, self.disclosureViews.indices.contains(index) else { return }
            cell.host(self.disclosureViews[index]())
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collection, indexPath, item in
            switch item {
            case let .song(id): collection.dequeueConfiguredReusableCell(using: songRegistration, for: indexPath, item: id)
            case let .notice(index, _): collection.dequeueConfiguredReusableCell(using: noticeRegistration, for: indexPath, item: index)
            }
        }
        let headerRegistration = UICollectionView.SupplementaryRegistration<UKSongsSectionHeaderView>(
            elementKind: UKSongsSectionHeaderView.kind
        ) { [weak self] header, _, indexPath in
            guard let self, case let ids = self.dataSource.snapshot().sectionIdentifiers, ids.indices.contains(indexPath.section), case let id = ids[indexPath.section],
                  case let .group(key) = id, let group = self.groups?.first(where: { "\($0.id)" == key }) else { return }
            header.configure(group: group)
        }
        dataSource.supplementaryViewProvider = { collection, _, indexPath in
            collection.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }

    // MARK: Row input

    /// The per-recompute facts every row shares.
    struct RowContext {
        var offers: [String: ShopSong]?
        var catalogueObservation: Int
        var chart: Instrument?
        var leeway: Double?
        var overThreshold: Set<Instrument>
        var currentSeason: Int?
        var highContrast: Bool
        var allowsPanel: Bool
    }

    func makeRowContext(pipeline: SongsPipeline, payload: CatalogPayload) -> RowContext {
        RowContext(
            offers: pipeline.shopOffersForCurrentSongs, catalogueObservation: payload.observedPublicationId,
            chart: instrument ?? Instrument.allCases.first(where: visibleInstruments.contains),
            leeway: pipeline.invalidScoreLeeway, overThreshold: pipeline.overThresholdCharts,
            currentSeason: pipeline.currentSeason, highContrast: UKAccessibility.moreContrast || traitCollection.accessibilityContrast == .high,
            allowsPanel: allowsProfilePanel
        )
    }

    func rowInput(for song: Song, context row: RowContext) -> UKSongRowInput {
        let highlight = ShopPresentationPolicy.highlight(
            for: row.offers?[song.songId], hidden: settings.hideShop, highlightingDisabled: settings.disableShopHighlighting
        )
        var input = UKSongRowInput(song: song, instrument: instrument, session: session)
        input.highContrast = row.highContrast
        input.shopHighlight = highlight
        input.inShop = !settings.hideShop && !settings.disableShopHighlighting && row.offers?[song.songId] != nil
        input.inShop = input.inShop || highlight != nil
        input.profileChart = row.chart
        input.catalogueObservation = row.catalogueObservation
        input.metadata = settings.metadata
        input.invalidScoreLeeway = row.leeway
        input.overThresholdCharts = row.overThreshold
        input.showInstrumentIcons = settings.showInstrumentIcons
        input.visibleInstruments = visibleInstruments
        input.currentSeason = row.currentSeason
        input.allowsProfilePanel = row.allowsPanel
        return input
    }

    private func cellWidth() -> CGFloat {
        let columns = CGFloat(max(1, songColumns))
        let content = collectionView.bounds.width - 32 - scrubberExtraInset
        return (content - (columns - 1) * SongGridPolicy.spacing) / columns
    }

    func configure(_ cell: UKSongRowCell, songId: String) {
        guard case let .loaded(payload) = state, let song = songsById[songId] else { return }
        let row = makeRowContext(pipeline: makePipeline(), payload: payload)
        cell.configure(rowInput(for: song, context: row), width: cellWidth(), traits: collectionView.traitCollection)
        cell.onOpen = { [weak self] in self?.open(song) }
        cell.onInvalidScore = { [weak self] warning in self?.explain(warning) }
    }

    func open(_ song: Song) {
        context.navigator?.push(.songDetail(song))
    }

    private func explain(_ warning: InvalidScoreWarning) {
        let alert = UIAlertController(title: InvalidScoreWarning.title, message: warning.message, preferredStyle: .alert)
        let ok = UIAlertAction(title: "OK", style: .cancel)
        ok.accessibilityIdentifier = "fst.songs.invalid-score.ok"
        alert.addAction(ok)
        if context.navigator != nil {
            let settingsAction = UIAlertAction(title: InvalidScoreWarning.settingsAction, style: .default) { [weak self] _ in
                self?.context.navigator?.select(.settings)
            }
            settingsAction.accessibilityIdentifier = "fst.songs.invalid-score.settings"
            alert.addAction(settingsAction)
        }
        present(alert, animated: true)
    }

    // MARK: Recompute

    /// Decides what the page shows from the session, settings and search, and applies it.
    func recompute() {
        guard isViewLoaded, dataSource != nil else { return }
        let pipeline = makePipeline()
        var next = Presented.loading
        var newDisclosures: [SongsDisclosure] = []
        var newVisible: [Song] = []
        var newGroups: [SongsListGroup]?
        var newShowsIndex = false
        var mode = pipeline.effectiveSortMode
        switch state {
        case .loading:
            next = .loading
        case let .failed(issue):
            next = .failed(issue)
        case let .loaded(payload):
            if let error = pipeline.savedFilterError {
                next = .savedFiltersInvalid(error.localizedDescription)
            } else {
                if songsByIdPayload != payload.observedPublicationId || songsById.count != payload.catalog.songs.count {
                    songsById = Dictionary(payload.catalog.songs.map { ($0.songId, $0) }, uniquingKeysWith: { first, _ in first })
                    songsByIdPayload = payload.observedPublicationId
                }
                mode = pipeline.effectiveSortMode
                newDisclosures = pipeline.disclosures(refreshFailure: refreshFailure, shopRefreshFailure: shopRefreshFailure)
                switch pipeline.visibleSongs(in: payload, search: settledSearch) {
                case let .failure(error):
                    next = .sortFailed(error.localizedDescription)
                case let .success(visible):
                    newVisible = visible
                    if visible.isEmpty {
                        let general = pipeline.appliedGeneralFilter ?? SongGeneralFilter()
                        let restricting = pipeline.effectiveShopFilter.isActive || general.restrictsMetadata
                            || pipeline.effectivePlayerScoreFilter.isActive
                        next = .empty(
                            search: settledSearch, filtersApplied: pipeline.filtersApplied(general: general),
                            restricting: restricting, disclosures: newDisclosures
                        )
                    } else {
                        let result = pipeline.groups(visible: visible, payload: payload)
                        newGroups = result.groups
                        newShowsIndex = result.showsIndex
                        if newShowsIndex {
                            indexSections = SongSectionIndex.sections(visible, mode: mode)
                        }
                        next = .list
                    }
                }
            }
        }
        presented = next
        disclosures = newDisclosures
        visibleSongs = newVisible
        groups = newGroups
        showsIndex = newShowsIndex
        effectiveMode = mode
        gate.update(key: reloadKey, isLoading: state.isLoading || searchText != settledSearch || refreshing)
        applyPresentation(pipeline: pipeline)
        updateTools(pipeline: pipeline)
    }

    private func applyPresentation(pipeline: SongsPipeline) {
        switch presented {
        case .list:
            statusView?.removeFromSuperview()
            statusView = nil
            collectionView.isHidden = false
            applySnapshot(pipeline: pipeline)
        default:
            collectionView.isHidden = true
            installStatusView()
            sectionBar.isHidden = true
            barBlocker.isHidden = true
            indexView.isHidden = true
            edgeFade?.update(edge: nil, scrollOffset: 0)
            quickLinks = nil
            quickLinksController.discover([])
            lastSnapshotKey = []
        }
        navigationItem.searchController?.searchBar.isEnabled = true
    }

    // MARK: Snapshot

    /// The notice views for the current disclosures, built when their cell asks.
    var disclosureViews: [() -> UIView] {
        var views: [() -> UIView] = []
        if let navigationNotice {
            views.append { [weak self] in self?.noticeBanner(navigationNotice) ?? UIView() }
        }
        for item in disclosures { views.append { [weak self] in self?.noticeView(item) ?? UIView() } }
        return views
    }

    private func applySnapshot(pipeline: SongsPipeline) {
        var snapshot = NSDiffableDataSourceSnapshot<UKSongsSectionID, UKSongsItem>()
        let noticeCount = disclosureViews.count
        if noticeCount > 0 {
            snapshot.appendSections([.notices])
            let tokens = (navigationNotice.map { [$0] } ?? []) + disclosures.map { "\($0)" }
            snapshot.appendItems((0..<noticeCount).map { UKSongsItem.notice($0, tokens[$0]) }, toSection: .notices)
        }
        if let groups {
            for group in groups {
                let id = UKSongsSectionID.group("\(group.id)")
                snapshot.appendSections([id])
                snapshot.appendItems(group.songs.map { .song($0.songId) }, toSection: id)
            }
        } else {
            snapshot.appendSections([.group("all")])
            snapshot.appendItems(visibleSongs.map { .song($0.songId) }, toSection: .group("all"))
        }
        let key = snapshot.sectionIdentifiers.map { "\($0)" } + snapshot.itemIdentifiers.map { "\($0)" }
        let columns = songColumns
        let layoutKey = ["\(columns)", "\(showsIndex)", "\(groups != nil)"]
        let reorderKey = [settings.sortMode.rawValue, String(settings.sortAscending), pipeline.filterAccessibilityValue, instrument?.rawValue ?? "", settledSearch]
        if key != lastSnapshotKey || layoutKey != lastLayoutKey {
            let top = reorderKey != lastReorderKey
            lastSnapshotKey = key
            if layoutKey != lastLayoutKey {
                lastLayoutKey = layoutKey
                collectionView.collectionViewLayout.invalidateLayout()
            }
            dataSource.apply(snapshot, animatingDifferences: false)
            if top { scrollToTop() }
        } else {
            reconfigureRows()
        }
        lastReorderKey = reorderKey
        configureQuickLinksAndIndex(pipeline: pipeline)
        collectionView.layoutIfNeeded()
        sectionBarNeedsUpdate()
        if presented.isList { gate.update(key: reloadKey, isLoading: state.isLoading || searchText != settledSearch || refreshing) }
    }

    /// Re-binds the visible rows after the session or settings changed under them.
    func reconfigureRows() {
        guard dataSource != nil else { return }
        var snapshot = dataSource.snapshot()
        let songs = snapshot.itemIdentifiers.filter { if case .song = $0 { true } else { false } }
        guard !songs.isEmpty else { return }
        snapshot.reconfigureItems(songs)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    func scrollToTop() {
        let top = -collectionView.adjustedContentInset.top
        UIView.performWithoutAnimation { collectionView.setContentOffset(CGPoint(x: 0, y: top), animated: false) }
    }

    // MARK: Delegate

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard case let .song(id)? = dataSource.itemIdentifier(for: indexPath), let song = songsById[id] else { return }
        open(song)
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        if case .song? = dataSource.itemIdentifier(for: indexPath) { return true }
        return false
    }

    func collectionView(
        _ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard case let .song(id)? = dataSource.itemIdentifier(for: indexPath),
              let action = UKWindows.menuAction(for: .song(songId: id)) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in UIMenu(children: [action]) }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateScrollChrome()
    }
}

extension UKSongsViewController.Presented {
    var isList: Bool {
        if case .list = self { true } else { false }
    }
}

#endif
