#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Search field

extension UKSongsViewController: UISearchResultsUpdating {
    func configureSearch() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.searchBar.placeholder = "Filter Songs"
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.overrideUserInterfaceStyle = .dark
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.preferredSearchBarPlacement = .stacked
        definesPresentationContext = true
    }

    func updateSearchResults(for searchController: UISearchController) {
        setSearch(searchController.searchBar.text ?? "")
    }

    /// The system Filter Songs field everywhere but iPhone Duo, which has its own at the bottom
    /// of the page (issues #333, #349).
    func installFilterPlacement() {
        let placement = SongsFilterFieldPlacement.resolve(pose: ukWindowLayout.pose)
        if placement == lastPlacement, navigationItem.searchController != nil || placement == .bottom { return }
        lastPlacement = placement
        if placement == .bottom {
            navigationItem.searchController = nil
            if bottomField == nil {
                let field = UKBottomSearchField(
                    prompt: "Filter Songs", label: "Filter Songs", identifier: "fst.songs.filter-field",
                    clearIdentifier: "fst.songs.filter-clear"
                )
                field.onChange = { [weak self] text in self?.setSearch(text) }
                field.onTopChange = { [weak self] _ in self?.bottomFieldMoved() }
                field.install(in: self, layout: { [weak self] in self?.ukWindowLayout ?? .standardPhone })
                bottomField = field
                bottomFade = UKBottomChromeFade(maskedView: bottomContainer, scrollView: collectionView)
            }
            bottomField?.isHidden = false
            bottomField?.refreshPlacement()
        } else {
            bottomField?.isHidden = true
            bottomFade?.chromeTop = nil
            if navigationItem.searchController == nil { navigationItem.searchController = searchController }
        }
    }

    func bottomFieldMoved() {
        guard let field = bottomField, !field.isHidden else { bottomFade?.chromeTop = nil; return }
        bottomFade?.chromeTop = bottomContainer.convert(field.bounds, from: field).minY
        layoutChrome()
    }
}

// MARK: - Status views

extension UKSongsViewController {
    func installStatusView() {
        statusView?.removeFromSuperview()
        statusView = nil
        let content: UIView
        switch presented {
        case .list, .loading:
            return
        case let .failed(issue):
            content = UKServiceStatusView(issue, title: "Songs unavailable") { [weak self] in
                Task { @MainActor in await self?.reloadCatalogue() }
            }
        case let .savedFiltersInvalid(message):
            content = invalidFiltersView(message)
        case let .sortFailed(message):
            let retry = UKSongsButtons.plated("Retry", identifier: "fst.songs.sort-retry") { [weak self] in self?.shopRetryRevision += 1 }
            content = UKEmptyStateView("Song sort unavailable", systemImage: "exclamationmark.triangle", subtitle: message, actions: [retry])
        case let .empty(search, filtersApplied, restricting, notices):
            let stack = UIStackView()
            stack.axis = .vertical
            stack.spacing = 8
            for notice in notices {
                let view = noticeView(notice)
                let wrapper = UIView()
                view.translatesAutoresizingMaskIntoConstraints = false
                wrapper.addSubview(view)
                NSLayoutConstraint.activate([
                    view.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16),
                    view.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16),
                    view.topAnchor.constraint(equalTo: wrapper.topAnchor), view.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
                ])
                stack.addArrangedSubview(wrapper)
            }
            let subtitle = search.isEmpty
                ? (filtersApplied ? "No songs match your filters." : "No songs are available yet.")
                : (restricting ? "Try a different search or filter." : "Try a different search.")
            let empty = UKEmptyStateView(
                search.isEmpty ? "No Results" : "No Results for \"\(search)\"", systemImage: "magnifyingglass",
                subtitle: subtitle, identifier: "fst.songs.empty"
            )
            if notices.isEmpty {
                content = empty
            } else {
                stack.addArrangedSubview(empty)
                let scroll = UIScrollView()
                stack.translatesAutoresizingMaskIntoConstraints = false
                scroll.addSubview(stack)
                NSLayoutConstraint.activate([
                    stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
                    stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
                    stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 8),
                    stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
                    stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
                ])
                content = scroll
            }
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        gate.contentView.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: gate.contentView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: gate.contentView.trailingAnchor),
            content.topAnchor.constraint(equalTo: gate.contentView.safeAreaLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: gate.contentView.safeAreaLayoutGuide.bottomAnchor),
        ])
        statusView = content
    }

    /// A corrupt saved filter blocks the list until an explicit Reset.
    private func invalidFiltersView(_ message: String) -> UIView {
        let title = UKLabel("Saved song filters unavailable", style: .title2, weight: .bold).asHeader()
        let body = UKLabel(message)
        let reset = UKSongsButtons.plated("Reset saved filters", identifier: "fst.songs.filter-reset-invalid") { [weak self] in
            self?.resetSavedFilters()
        }
        let stack = UIStackView(arrangedSubviews: [title, body, reset])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        scroll.accessibilityIdentifier = "fst.songs.filter-invalid"
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48),
        ])
        return scroll
    }

    /// Resets only the corrupt saved filters.
    private func resetSavedFilters() {
        let pipeline = makePipeline()
        let defaults = UserDefaults.standard
        if pipeline.generalFilterError != nil, let data = try? SongGeneralFilter().encoded() {
            defaults.set(data, forKey: SongGeneralFilter.storageKey)
            defaults.set(false, forKey: SongGeneralFilter.legacyInShopKey)
            defaults.set(false, forKey: SongGeneralFilter.legacyLeavingTomorrowKey)
        }
        if pipeline.playerScoreFilterError != nil { defaults.set(Data(), forKey: SongPlayerScoreFilter.storageKey) }
        settings = SongsSettings.load()
        recompute()
    }

    // MARK: Notices

    func noticeView(_ item: SongsDisclosure) -> UIView {
        switch item {
        case let .refreshError(message):
            let banner = UKRefreshErrorBanner(message: message)
            return banner
        case let .freshness(message, symbol, identifier):
            let view = UKFreshnessDisclosureView(message: message, symbol: symbol)
            view.accessibilityIdentifier = identifier
            return view
        case .retryPlayer:
            return leading(UKSongsButtons.plated("Retry Player Scores", identifier: "fst.songs.profile-retry") { [weak self] in
                guard let self else { return }
                Task { @MainActor in await self.session.refreshSelectedPlayer() }
            })
        case .chooseProfile:
            return leading(UKSongsButtons.plated("Choose Profile", identifier: "fst.songs.profile-retry") { [weak self] in
                self?.context.navigator?.presentProfile()
            })
        case .retryShop:
            return leading(UKSongsButtons.plated("Retry Item Shop status", identifier: "fst.songs.shop-retry") { [weak self] in
                self?.shopRetryRevision += 1
            })
        }
    }

    private func leading(_ button: UIButton) -> UIView {
        let wrapper = UIView()
        button.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            button.trailingAnchor.constraint(lessThanOrEqualTo: wrapper.trailingAnchor),
            button.topAnchor.constraint(equalTo: wrapper.topAnchor), button.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])
        return wrapper
    }

    func noticeBanner(_ message: String) -> UIView {
        let label = UKLabel(message, style: .footnote, color: BrandUIColors.gold)
        var configuration = UIButton.Configuration.plain()
        configuration.title = "Dismiss"
        configuration.baseForegroundColor = BrandUIColors.gold
        let dismiss = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.navigationNotice = nil
            self?.recompute()
        })
        dismiss.titleLabel?.font = UKFont.font(.footnote)
        dismiss.setContentHuggingPriority(.required, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [label, dismiss])
        stack.spacing = 8
        stack.alignment = .center
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.backgroundColor = BrandUIColors.cardBackground
        stack.layer.cornerRadius = 12
        stack.layer.cornerCurve = .continuous
        stack.accessibilityIdentifier = "fst.songs.navigation-notice"
        return stack
    }
}

// MARK: - Scroll chrome

extension UKSongsViewController {
    /// The bar's top within the page: the visible region's top below the navigation bar.
    private var barTop: CGFloat { collectionView.adjustedContentInset.top }

    func layoutChrome() {
        let top = barTop
        let barHeight = UKSongsSectionBar.height()
        sectionBar.frame = CGRect(x: 0, y: top, width: view.bounds.width, height: max(0, view.bounds.height - top))
        barBlocker.frame = CGRect(x: 0, y: top, width: view.bounds.width, height: barHeight)
        if let field = bottomField, !field.isHidden {
            let inset = max(0, view.bounds.maxY - view.convert(field.bounds, from: field).minY - view.safeAreaInsets.bottom)
            if collectionView.contentInset.bottom != inset {
                collectionView.contentInset.bottom = inset
                collectionView.verticalScrollIndicatorInsets.bottom = inset
            }
        } else if collectionView.contentInset.bottom != 0 {
            collectionView.contentInset.bottom = 0
            collectionView.verticalScrollIndicatorInsets.bottom = 0
        }
        layoutIndex()
    }

    func sectionBarNeedsUpdate() { updateScrollChrome() }

    /// Updates the section bar, the row fade under it, Quick Links and the rail position.
    func updateScrollChrome() {
        quickLinks?.scrollViewDidScroll()
        guard presented.isList, let groups else {
            sectionBar.isHidden = true
            barBlocker.isHidden = true
            edgeFade?.update(edge: nil, scrollOffset: 0)
            return
        }
        let inset = collectionView.adjustedContentInset.top
        let scrolled = collectionView.contentOffset.y + inset > 1
        guard scrolled else {
            sectionBar.isHidden = true
            barBlocker.isHidden = true
            edgeFade?.update(edge: nil, scrollOffset: 0)
            return
        }
        let visibleTop = collectionView.contentOffset.y + inset
        let ids = dataSource.snapshot().sectionIdentifiers
        var tops: [CGFloat] = []
        var order: [Int] = []
        for (index, id) in ids.enumerated() {
            guard case .group = id,
                  let attributes = collectionView.layoutAttributesForSupplementaryElement(
                      ofKind: UKSongsSectionHeaderView.kind, at: IndexPath(item: 0, section: index)
                  ) else { continue }
            tops.append(attributes.frame.minY)
            order.append(index)
        }
        guard let current = tops.lastIndex(where: { $0 <= visibleTop + 0.5 }), groups.indices.contains(current) else {
            sectionBar.isHidden = true
            barBlocker.isHidden = true
            edgeFade?.update(edge: nil, scrollOffset: 0)
            return
        }
        let barHeight = UKSongsSectionBar.height()
        var currentY: CGFloat = 0
        var incoming: String?
        var incomingY: CGFloat = 0
        var outgoing: String?
        if current + 1 < tops.count, groups.indices.contains(current + 1) {
            let relative = tops[current + 1] - visibleTop
            if relative < barHeight {
                currentY = relative - barHeight
                incoming = groups[current + 1].label
                incomingY = relative
            }
        }
        _ = outgoing
        outgoing = nil
        let group = groups[current]
        sectionBar.update(
            current: (group.label, group.spokenLabel ?? group.label), currentY: currentY, outgoing: outgoing, outgoingY: 0,
            incoming: incoming, incomingY: incomingY
        )
        barBlocker.isHidden = false
        edgeFade?.update(edge: barTop + barHeight, scrollOffset: visibleTop)
    }

    // MARK: Rail and Quick Links

    func configureQuickLinksAndIndex(pipeline: SongsPipeline) {
        let sections = showsIndex ? [] : (groups ?? []).compactMap(\.quickLink)
        let title = "\(effectiveMode.label) Quick Links"
        let key = sections.map(\.id) + [title]
        if key != quickLinksKey {
            quickLinksKey = key
            quickLinks?.willDisappear()
            let binding = UKQuickLinks(controller: quickLinksController, title: title, sections: sections, activationOffset: 0)
            binding.onToolChange = { [weak self] in self?.ukPageToolsDidChange() }
            binding.attach(to: collectionView, rect: { [weak self] id in self?.headerFrame(forQuickLink: id) })
            quickLinks = binding
            if isVisible { binding.didAppear() }
            ukPageToolsDidChange()
        }
        indexView.isHidden = !showsIndex
        layoutIndex()
    }

    private func headerFrame(forQuickLink id: String) -> CGRect? {
        guard let groups, let index = groups.firstIndex(where: { $0.quickLink?.id == id }) else { return nil }
        return headerFrame(forGroup: index)
    }

    /// A group's header frame in content coordinates.
    func headerFrame(forGroup index: Int) -> CGRect? {
        guard let section = sectionIndex(forGroup: index) else { return nil }
        return collectionView.layoutAttributesForSupplementaryElement(
            ofKind: UKSongsSectionHeaderView.kind, at: IndexPath(item: 0, section: section)
        )?.frame
    }

    private func sectionIndex(forGroup index: Int) -> Int? {
        guard let group = (groups.flatMap { $0.indices.contains(index) ? $0[index] : nil }) else { return nil }
        return dataSource.snapshot().sectionIdentifiers.firstIndex(of: .group("\(group.id)"))
    }

    func layoutIndex() {
        guard showsIndex, !indexView.isHidden else { return }
        let top = ukLayout.overlayInsets.top + 52
        let bottom = view.bounds.height - view.safeAreaInsets.bottom - 8
        let available = max(0, bottom - top)
        let size = indexView.configure(sections: indexSections, availableHeight: available)
        let x = view.bounds.width - view.safeAreaInsets.right - max(2, ukLayout.cutoutInsets.trailing) - size.width
        indexView.frame = CGRect(x: x, y: top + max(0, (available - size.height) / 2), width: size.width, height: size.height)
    }

    /// Jumps to a section's title from the A–Z rail and names it in the section bar at once.
    func jumpToSection(id: AnyHashable) {
        guard let groups, let index = groups.firstIndex(where: { $0.id == id }) else { return }
        jumpGeneration += 1
        let generation = jumpGeneration
        let move: @MainActor () -> Void = { [weak self] in
            guard let self, let frame = self.headerFrame(forGroup: index) else { return }
            let minimum = -self.collectionView.adjustedContentInset.top
            let maximum = max(minimum, self.collectionView.contentSize.height - self.collectionView.bounds.height + self.collectionView.adjustedContentInset.bottom)
            let y = min(max(frame.minY - self.collectionView.adjustedContentInset.top, minimum), maximum)
            self.collectionView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
            self.updateScrollChrome()
        }
        let viewport = collectionView.bounds.height
        let rowsBefore = groups.prefix(index).reduce(0) { $0 + $1.songs.count }
        let visibleFirst = collectionView.indexPathsForVisibleItems.compactMap { dataSource.itemIdentifier(for: $0) }
            .compactMap { item -> Int? in
                if case let .song(songId) = item { return visibleSongs.firstIndex(where: { $0.songId == songId }) }
                return nil
            }.min() ?? 0
        if UKListJump.isFar(rowDistance: abs(rowsBefore - visibleFirst), viewportHeight: viewport), !teleporting {
            teleporting = true
            Task { @MainActor [weak self] in
                await UKListJump.teleport(self?.collectionView ?? UIView(), scroll: move)
                self?.teleporting = false
            }
        } else {
            UIView.performWithoutAnimation { move() }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, self.jumpGeneration == generation else { return }
                UIView.performWithoutAnimation { move() }
            }
        }
    }
}

// MARK: - Page tools

extension UKSongsViewController {
    private var sortCustomized: Bool { !(settings.sortMode == .title && settings.sortAscending) }

    private var foldsInBar: Bool {
        guard ukWindowLayout.sectionChrome == .tabBar else { return false }
        if traitCollection.preferredContentSizeCategory.isAccessibilityCategory { return true }
        let width = view.bounds.width
        return width > 0 && width < SongsToolbarFold.minimumUnfoldedWidth
    }

    func pageTools() -> [UKPageTool] { tools + [quickLinks?.tool].compactMap { $0 } }

    func updateTools(pipeline: SongsPipeline) {
        let filterActive = pipeline.generalFilterActive || pipeline.appliedPlayerScoreFilter?.isActive == true
        let canFilter = pipeline.canPresentFilter
        let floating = ukShell?.floatsPageTools ?? false
        let folds: Bool
        if floating {
            folds = FloatingPageToolsFit.folds(
                windowWidth: view.window?.bounds.width ?? 0, pageTools: (canFilter ? 2 : 1) + (quickLinks?.tool != nil ? 1 : 0)
            )
        } else {
            folds = foldsInBar
        }
        let token = [
            settings.sortMode.label, String(settings.sortAscending), pipeline.sortPausedMessage ?? "",
            pipeline.filterAccessibilityValue, String(filterActive), String(canFilter), String(folds), String(floating),
        ]
        guard token != toolsToken else { return }
        toolsToken = token
        let highlighted = sortCustomized || filterActive
        var built: [UKPageTool] = []
        if folds {
            let sort = UIAction(title: "Sort…", image: UIImage(systemName: "arrow.up.arrow.down")) { [weak self] _ in self?.presentSort() }
            sort.accessibilityIdentifier = "fst.songs.tools.sort"
            var children: [UIMenuElement] = [sort]
            if canFilter {
                let filter = UIAction(title: "Filter…", image: UIImage(systemName: "line.3.horizontal.decrease")) { [weak self] _ in self?.presentFilter() }
                filter.accessibilityIdentifier = "fst.songs.tools.filter"
                children.append(filter)
            }
            let item = UIBarButtonItem(title: "Sort and Filter", image: UIImage(systemName: "slider.horizontal.3"), menu: UIMenu(children: children))
            item.preferredMenuElementOrder = .fixed
            item.tintColor = highlighted ? BrandUIColors.gold : BrandUIColors.accentBlue
            item.accessibilityLabel = "Sort and Filter"
            item.accessibilityIdentifier = "fst.songs.tools"
            built.append(UKPageTool(order: PageToolOrder.primary, item: item))
        } else {
            let sort = UIBarButtonItem(
                title: "Sort", image: UIImage(systemName: "arrow.up.arrow.down"), primaryAction: UIAction { [weak self] _ in self?.presentSort() }
            )
            sort.accessibilityLabel = "Sort"
            sort.accessibilityValue = "\(settings.sortMode.label), \(settings.sortAscending ? "ascending" : "descending")"
                + (pipeline.sortPausedMessage == nil ? "" : ", paused; showing Title order")
            sort.accessibilityIdentifier = "fst.songs.sort"
            sort.tintColor = sortCustomized ? BrandUIColors.gold : BrandUIColors.accentBlue
            built.append(UKPageTool(order: PageToolOrder.primary, item: sort))
            if canFilter {
                let filter = UIBarButtonItem(
                    title: "Filter", image: UIImage(systemName: "line.3.horizontal.decrease"),
                    primaryAction: UIAction { [weak self] _ in self?.presentFilter() }
                )
                filter.accessibilityLabel = "Filter Songs"
                filter.accessibilityValue = pipeline.filterAccessibilityValue
                filter.accessibilityIdentifier = "fst.songs.filter"
                filter.tintColor = filterActive ? BrandUIColors.gold : BrandUIColors.accentBlue
                built.append(UKPageTool(order: PageToolOrder.secondary, item: filter))
            }
        }
        tools = built
        ukPageToolsDidChange()
    }

    // MARK: Debug

    #if DEBUG
    /// `FST_DEBUG_SONG=<title or songId>` pushes that song's page once the catalogue loads.
    func startDebugPush() {
        guard debugPushed == false, let target = FestivalDebugLaunch.songTitleOrId else { return }
        Task { @MainActor [weak self] in
            for _ in 0..<1200 {
                guard let self else { return }
                if case let .loaded(payload) = self.state,
                   let match = payload.catalog.songs.first(where: {
                       $0.songId == target || $0.title.localizedCaseInsensitiveCompare(target) == .orderedSame
                   }) {
                    self.debugPushed = true
                    if let bandType = FestivalDebugLaunch.songBandType {
                        self.context.navigator?.push(.songBandLeaderboard(match, bandType: bandType))
                    } else if let instrument = FestivalDebugLaunch.songInstrument {
                        self.context.navigator?.push(.songLeaderboard(match, instrument, 1))
                    } else {
                        self.context.navigator?.push(.songDetail(match))
                    }
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
    #endif
}
#endif
