#if os(iOS)
import FestivalAppSupport
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Global search

/// Global search (and the Profiles sheet's search): the UIKit counterpart of
/// ``GlobalSearchTab`` + ``GlobalSearchResults``.
///
/// A scope bar (a segmented control, All first) over song, player and band cards, with
/// one centred hint, spinner or empty state for the other phases. The query lives in the
/// shared ``GlobalSearchModel``, so it survives closing and reopening the tab. The field is
/// the system search bar in the navigation bar (the Search tab: a `UISearchTab` activates it
/// and returns to the previous tab when it is dismissed), or ``UKBottomSearchField`` on the
/// iPhone Duo inner display (``GlobalSearchFieldPlacement``).
@MainActor
final class UKGlobalSearchViewController: UIViewController, UISearchResultsUpdating, UISearchBarDelegate, UICollectionViewDelegate {
    // MARK: Types

    private enum CardID: Hashable {
        case song(String)
        case player(String)
        case band(String)
    }

    private enum Item: Hashable {
        case title(GlobalSearchScope, first: Bool)
        case failure(GlobalSearchScope)
        case cards([CardID])
    }

    private enum EntranceID: Hashable {
        case title(GlobalSearchScope)
        case failure(GlobalSearchScope)
        case card(CardID)
    }

    // MARK: Inputs

    private let model: GlobalSearchModel
    private let session: FestivalSession
    private let asTab: Bool
    private let layoutProvider: () -> DeviceLayout
    private let open: (AppRoute) -> Void
    private let dismissSearch: () -> Void

    // MARK: Views

    private let scopeControl = UISegmentedControl()
    private let resultsHost = UIView()
    private lazy var collection = UICollectionView(frame: .zero, collectionViewLayout: Self.makeLayout())
    private lazy var bottomFade = UKBottomChromeFade(maskedView: resultsHost, scrollView: collection)
    private lazy var resultsBottomConstraint = resultsHost.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    private var dataSource: UICollectionViewDiffableDataSource<Int, Item>?
    private let statusRegion = UILayoutGuide()
    private let hint = UILabel()
    private lazy var spinner = UKLoadingView(accessibilityLabel: "Searching", placement: .fill, identifier: ids("loading"))
    /// Holds the current ``UKEmptyStateView`` (`GlobalSearchEmptyStateView`), replaced per query.
    private let emptyState = UIView()
    private let searchController = UISearchController(searchResultsController: nil)
    private var bottomField: UKBottomSearchField?
    private var systemScopeConstraints: [NSLayoutConstraint] = []
    private var bottomFieldConstraints: [NSLayoutConstraint] = []

    // MARK: State

    private let observations = UKObservationBag()
    private var searchTask: Task<Void, Never>?
    private var announceTask: Task<Void, Never>?
    private var ids: GlobalSearchIdentifiers { GlobalSearchIdentifiers(model.targets) }
    private var lastRunKey: GlobalSearchModel.RunKey?
    private var isSelectedTab = false
    private var needsBottomFieldFocus = false
    private var resultColumns = 1
    private var lastResultHinge: CGRect?
    private let entranceScope = FestivalFadeInScope()
    private var entranceKey: [CardID]?
    private var entranceSlots: [EntranceID: Int] = [:]
    private var appearedItems: Set<EntranceID> = []
    private var entranceSettleTask: Task<Void, Never>?
    private var accessibilityObserver: UKAccessibilityObserver?

    /// Creates a search page.
    ///
    /// - Parameters:
    ///   - model: The search state, kept by the shell while Search is closed.
    ///   - session: The shared session.
    ///   - asTab: The phone Search tab (focuses the field when chosen, returns to the
    ///     previous tab on dismissal) rather than a full-width page.
    ///   - layout: The window layout provider.
    ///   - open: Opens a result on the previous tab.
    ///   - dismiss: The field was dismissed.
    init(
        model: GlobalSearchModel, session: FestivalSession, asTab: Bool, layout: @escaping () -> DeviceLayout,
        open: @escaping (AppRoute) -> Void, dismiss: @escaping () -> Void
    ) {
        self.model = model
        self.session = session
        self.asTab = asTab
        self.layoutProvider = layout
        self.open = open
        self.dismissSearch = dismiss
        super.init(nibName: nil, bundle: nil)
        title = "Search"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityIdentifier = ids("surface")
        navigationItem.largeTitleDisplayMode = GlobalSearchTitleStyle.resolve(asTab: asTab) == .inlineLarge ? .inline : .always
        buildScopeBar()
        buildCollection()
        buildStates()
        configureField()
        accessibilityObserver = UKAccessibilityObserver { [weak self] in
            guard let self, UKAccessibility.reduceMotion else { return }
            self.entranceScope.close()
            for case let cell as UKSearchContentCell in self.collection.visibleCells { cell.finishEntrances() }
        }
        observations.observe { [weak self] in self?.render() }
        observations.observe { [weak self] in self?.driveSearch() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshFieldPlacement()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        focusBottomFieldIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = max(0, statusRegion.layoutFrame.width - 48)
        if hint.preferredMaxLayoutWidth != width { hint.preferredMaxLayoutWidth = width }
        bottomFade.chromeTop = bottomField == nil ? nil : resultsHost.bounds.height
        bottomFade.layout()
        let layout = layoutProvider()
        let columnCount = WideColumns.count(layout: layout, width: resultsHost.safeAreaLayoutGuide.layoutFrame.width)
        let hinge = columnCount > 1 ? layout.splitHinge : nil
        if columnCount != resultColumns || hinge != lastResultHinge {
            resultColumns = columnCount
            lastResultHinge = hinge
            render(reflowing: true)
        }
    }

    private var usesBottomField: Bool {
        GlobalSearchFieldPlacement.resolve(pose: layoutProvider().pose, asTab: asTab) == .bottom
    }

    /// Marks whether this page's tab is selected (focuses the field when chosen).
    ///
    /// - Parameter selected: The Search tab is showing.
    func setSelected(_ selected: Bool) {
        guard selected != isSelectedTab else { return }
        isSelectedTab = selected
        needsBottomFieldFocus = selected && asTab
        if needsBottomFieldFocus {
            if usesBottomField { focusBottomFieldIfNeeded() } else { searchController.isActive = true }
        }
    }

    private func focusBottomFieldIfNeeded() {
        guard needsBottomFieldFocus, let field = bottomField?.field, field.window?.isKeyWindow == true else { return }
        if field.becomeFirstResponder() { needsBottomFieldFocus = false }
    }

    // MARK: Field

    private func configureField() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.searchBar.delegate = self
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.searchTextField.accessibilityIdentifier = ids.field
        searchController.searchBar.searchTextField.textColor = BrandUIColors.textPrimary
        if asTab { searchController.automaticallyShowsCancelButton = true }
        definesPresentationContext = true
        refreshFieldPlacement()
    }

    /// Switches between the system field and the Duo bottom field when the pose changes.
    func refreshFieldPlacement() {
        guard isViewLoaded else { return }
        if usesBottomField {
            navigationItem.searchController = nil
            if bottomField == nil {
                let field = UKBottomSearchField(
                    prompt: GlobalSearch.prompt(for: model.scope, targets: model.targets),
                    label: model.targets.fieldLabel, identifier: ids.field, clearIdentifier: ids.clear
                )
                field.onChange = { [weak self] in self?.model.query = $0 }
                field.onSubmit = { [weak self] in self?.model.submit() }
                field.install(in: self, layout: layoutProvider)
                field.text = model.query
                bottomField = field
                NSLayoutConstraint.deactivate(systemScopeConstraints)
                resultsBottomConstraint.isActive = false
                bottomFieldConstraints = [
                    scopeControl.leadingAnchor.constraint(equalTo: field.leadingAnchor),
                    scopeControl.trailingAnchor.constraint(equalTo: field.trailingAnchor),
                    resultsHost.bottomAnchor.constraint(equalTo: field.topAnchor),
                    statusRegion.bottomAnchor.constraint(
                        lessThanOrEqualTo: field.topAnchor, constant: -BottomSearchFieldPlacement.rowPadding
                    ),
                ]
                NSLayoutConstraint.activate(bottomFieldConstraints)
                collection.contentInset.bottom = BottomSearchFieldPlacement.rowPadding
            }
            bottomField?.refreshPlacement()
            focusBottomFieldIfNeeded()
        } else {
            if let bottomField {
                NSLayoutConstraint.deactivate(bottomFieldConstraints)
                bottomFieldConstraints.removeAll()
                bottomField.removeFromSuperview()
                self.bottomField = nil
                NSLayoutConstraint.activate(systemScopeConstraints)
                resultsBottomConstraint.isActive = true
                collection.contentInset.bottom = 0
            }
            if navigationItem.searchController == nil {
                navigationItem.searchController = searchController
                navigationItem.preferredSearchBarPlacement = .stacked
                navigationItem.hidesSearchBarWhenScrolling = false
            }
        }
        view.setNeedsLayout()
    }

    func updateSearchResults(for searchController: UISearchController) {
        let text = searchController.searchBar.text ?? ""
        if model.query != text { model.query = text }
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        model.submit()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        if asTab { dismissSearch() }
    }

    // MARK: Scope bar

    private func buildScopeBar() {
        for (index, scope) in model.targets.scopes.enumerated() {
            scopeControl.insertSegment(withTitle: scope.title, at: index, animated: false)
        }
        scopeControl.selectedSegmentIndex = model.targets.scopes.firstIndex(of: model.scope) ?? 0
        scopeControl.accessibilityLabel = "Search Scope"
        scopeControl.accessibilityIdentifier = ids("scope")
        scopeControl.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.model.scope = self.model.targets.scopes[self.scopeControl.selectedSegmentIndex]
        }, for: .valueChanged)
        scopeControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scopeControl)
        systemScopeConstraints = [
            scopeControl.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            scopeControl.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        ]
        NSLayoutConstraint.activate(systemScopeConstraints + [
            // Use the surrounding gaps for the larger target without moving the results.
            scopeControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 2),
            scopeControl.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    // MARK: Results

    private static func makeLayout() -> UICollectionViewCompositionalLayout {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.backgroundColor = .clear
        configuration.showsSeparators = false
        return UICollectionViewCompositionalLayout.list(using: configuration)
    }

    private func buildCollection() {
        resultsHost.translatesAutoresizingMaskIntoConstraints = false
        collection.backgroundColor = .clear
        collection.keyboardDismissMode = .onDrag
        collection.allowsSelection = false
        collection.delegate = self
        view.addSubview(resultsHost)
        resultsHost.ukPin(collection)
        NSLayoutConstraint.activate([
            resultsHost.topAnchor.constraint(equalTo: scopeControl.bottomAnchor, constant: 4),
            resultsHost.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            resultsHost.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            resultsBottomConstraint,
        ])
        let contentCell = UICollectionView.CellRegistration<UKSearchContentCell, Item> { [weak self] cell, _, item in
            guard let self else { return }
            switch item {
            case let .title(scope, first):
                let heading = UKSectionHeaderView(scope.title, identifier: ids("section.\(scope.rawValue)"))
                let horizontal = GlobalSearchResultLayout.headingHorizontalInset
                cell.show(heading, insets: UIEdgeInsets(
                    top: GlobalSearchResultLayout.headingTopInset(first: first),
                    left: horizontal, bottom: GlobalSearchResultLayout.headingBottomInset, right: horizontal
                ))
                enter(heading, as: .title(scope), in: cell)
            case let .cards(ids):
                guard resultColumns > 1 else {
                    if let id = ids.first, let card = makeCard(id, rowInsets: Self.resultInsets) {
                        cell.show(card, insets: .zero)
                        enter(card, as: .card(id), in: cell)
                    }
                    return
                }
                let cards = ids.compactMap { id in makeCard(id).map { (id, $0) } }
                let row = UKProfileColumnGrid(
                    columns: .fixed(self.resultColumns), spacing: WideColumns.spacing
                )
                row.layoutProvider = self.layoutProvider
                row.setCells(cards.map(\.1))
                cell.show(row, insets: Self.resultInsets)
                for (id, card) in cards { enter(card, as: .card(id), in: cell) }
            case let .failure(scope):
                let issue: ServiceIssue? = {
                    switch scope {
                    case .songs: if case let .failed(issue) = model.songState { return issue }
                    case .players: if case let .failed(issue) = model.playerState { return issue }
                    case .bands: if case let .failed(issue) = model.bandState { return issue }
                    case .all: break
                    }
                    return nil
                }()
                guard let issue else { return }
                let status = UKServiceStatusInlineView(
                    issue, scope: "\(ids.statusScope).\(scope.rawValue)", showsRetryButton: false,
                    fallbackTitle: GlobalSearch.unavailableTitle(for: scope)
                ) { [weak self] in self?.model.retry() }
                status.accessibilityIdentifier = ids("\(scope.rawValue)-error")
                cell.show(status, insets: Self.resultInsets)
                enter(status, as: .failure(scope), in: cell)
            }
        }
        dataSource = UICollectionViewDiffableDataSource<Int, Item>(collectionView: collection) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: contentCell, for: indexPath, item: item)
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.isDragging || scrollView.isDecelerating else { return }
        entranceScope.noteContentOffset(scrollView.contentOffset.y)
    }

    private func enter(_ content: UIView, as id: EntranceID, in cell: UKSearchContentCell) {
        guard let index = entranceSlots[id], appearedItems.insert(id).inserted else { return }
        cell.enter(content, index: index, scope: entranceScope)
    }

    private static let resultInsets = UIEdgeInsets(
        top: GlobalSearchResultLayout.cardVerticalInset, left: GlobalSearchResultLayout.cardHorizontalInset,
        bottom: GlobalSearchResultLayout.cardVerticalInset, right: GlobalSearchResultLayout.cardHorizontalInset
    )

    /// - Parameters:
    ///   - id: The result to show.
    ///   - rowInsets: Space inside a single-column button but outside its painted card.
    /// - Returns: The result action, if the model still contains the result.
    private func makeCard(_ id: CardID, rowInsets: UIEdgeInsets = .zero) -> UIView? {
        switch id {
        case let .song(id):
            guard let song = model.songs.first(where: { $0.id == id }) else { return nil }
            let subtitle = GlobalSearchResults.subtitle(for: song)
            let art = UKArtworkTileView(size: GlobalSearchResultLayout.artworkSize)
            art.configure(raw: song.albumArt, session: session)
            let labels = UIStackView(arrangedSubviews: [
                UKMarqueeLabel(song.title, font: UKFont.font(.headline)),
                UKMarqueeLabel(subtitle, font: UKFont.font(.subheadline)),
            ])
            labels.axis = .vertical
            labels.spacing = 4
            let row = UIStackView(arrangedSubviews: [art, labels])
            row.spacing = 12
            row.alignment = .center
            let vertical = GlobalSearchResultLayout.songVerticalPadding
            return UKSearchResultButton(
                content: row, insets: UIEdgeInsets(top: vertical, left: 12, bottom: vertical, right: 12),
                rowInsets: rowInsets,
                identifier: ids("result.song"), label: "\(song.title), \(subtitle)"
            ) { [open] in open(.songDetail(song)) }
        case let .player(id):
            guard let player = model.players.first(where: { $0.accountId == id }) else { return nil }
            let icon = UIImageView(image: UIImage(systemName: "person.crop.circle"))
            icon.tintColor = BrandUIColors.textPrimary
            icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .body)
            icon.adjustsImageSizeForAccessibilityContentSizeCategory = true
            icon.setContentHuggingPriority(.required, for: .horizontal)
            icon.setContentCompressionResistancePriority(.required, for: .horizontal)
            let row = UIStackView(arrangedSubviews: [icon, UKLabel(player.displayName)])
            row.alignment = .center
            row.spacing = 8
            return UKSearchResultButton(
                content: row, insets: UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16),
                rowInsets: rowInsets, minimumCardHeight: GlobalSearchResultLayout.playerCardMinimumHeight,
                identifier: ids.player(player.accountId), label: player.displayName
            ) { [session, open] in
                if session.selectedPlayer?.accountId == player.accountId {
                    open(.statistics)
                } else {
                    open(.player(accountId: player.accountId, displayName: player.displayName))
                }
            }
        case let .band(id):
            guard let band = model.bands.first(where: { $0.id == id }) else { return nil }
            return UKPlayerBandRowView(
                entry: band, grouped: false, identifier: ids("result.band"), cardInsets: rowInsets, onOpen: open
            )
        }
    }

    // MARK: States

    private func buildStates() {
        hint.numberOfLines = 0
        hint.textAlignment = .center
        hint.font = .preferredFont(forTextStyle: .body)
        hint.adjustsFontForContentSizeCategory = true
        hint.textColor = BrandUIColors.textPrimary
        hint.accessibilityIdentifier = ids("hint")
        spinner.hingeProvider = { [weak self] in self?.layoutProvider().splitHinge }
        for state in [hint, spinner, emptyState] as [UIView] {
            state.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(state)
        }
        // The system keyboard guide already reserves the search accessory. The custom
        // bottom field is separately constrained when installed.
        let region = statusRegion
        view.addLayoutGuide(region)
        let safeArea = view.safeAreaLayoutGuide
        let fill = region.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor)
        fill.priority = .defaultHigh
        NSLayoutConstraint.activate([
            region.topAnchor.constraint(equalTo: collection.topAnchor),
            region.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            region.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            region.bottomAnchor.constraint(lessThanOrEqualTo: safeArea.bottomAnchor),
            region.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor),
            fill,
            hint.centerXAnchor.constraint(equalTo: region.centerXAnchor),
            hint.centerYAnchor.constraint(equalTo: region.centerYAnchor),
            hint.leadingAnchor.constraint(greaterThanOrEqualTo: region.leadingAnchor, constant: 24),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: region.trailingAnchor, constant: -24),
            spinner.topAnchor.constraint(equalTo: region.topAnchor),
            spinner.bottomAnchor.constraint(equalTo: region.bottomAnchor),
            spinner.leadingAnchor.constraint(equalTo: region.leadingAnchor),
            spinner.trailingAnchor.constraint(equalTo: region.trailingAnchor),
            emptyState.topAnchor.constraint(equalTo: region.topAnchor),
            emptyState.bottomAnchor.constraint(equalTo: region.bottomAnchor),
            emptyState.leadingAnchor.constraint(equalTo: region.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: region.trailingAnchor),
        ])
        emptyState.backgroundColor = .clear
    }

    // MARK: Rendering

    /// Renders the model: the placeholder, spinner or empty state, or the result cards.
    private func render(reflowing: Bool = false) {
        let scope = model.scope
        let query = model.query
        let outcomes = model.outcomes
        let hasQuery = model.hasQuery
        let searching = model.isSearching
        let empty = model.isEmpty
        _ = (model.songs, model.players, model.bands, model.songState, model.playerState, model.bandState)
        scopeControl.selectedSegmentIndex = model.targets.scopes.firstIndex(of: scope) ?? 0
        let prompt = GlobalSearch.prompt(for: scope, targets: model.targets)
        searchController.searchBar.placeholder = prompt
        searchController.searchBar.searchTextField.accessibilityLabel = model.targets == .profiles
            ? prompt : model.targets.fieldLabel
        bottomField?.setPrompt(prompt)
        if searchController.searchBar.text != query, !searchController.searchBar.searchTextField.isFirstResponder {
            searchController.searchBar.text = query
        }
        bottomField?.text = query

        hint.isHidden = true
        spinner.isHidden = true
        emptyState.isHidden = true
        var items: [Item] = []
        if !hasQuery {
            hint.text = GlobalSearch.enterQueryHint(for: scope, targets: model.targets)
            hint.isHidden = false
        } else if searching {
            spinner.isHidden = false
        } else if empty, let state = GlobalSearch.emptyState(scope: scope, query: query, targets: model.targets) {
            // The shared empty state (empty-error-states R5/R8), read as one element (#299).
            emptyState.subviews.forEach { $0.removeFromSuperview() }
            let emptyView = UKEmptyStateView(
                state.title, systemImage: "magnifyingglass", subtitle: state.subtitle,
                reading: .combined, identifier: ids("hint")
            )
            emptyView.hingeProvider = { [weak self] in self?.layoutProvider().splitHinge }
            emptyView.translatesAutoresizingMaskIntoConstraints = false
            emptyState.addSubview(emptyView)
            NSLayoutConstraint.activate([
                emptyView.topAnchor.constraint(equalTo: emptyState.topAnchor),
                emptyView.bottomAnchor.constraint(equalTo: emptyState.bottomAnchor),
                emptyView.leadingAnchor.constraint(equalTo: emptyState.leadingAnchor),
                emptyView.trailingAnchor.constraint(equalTo: emptyState.trailingAnchor),
            ])
            emptyState.isHidden = false
        } else {
            for section in scope.sections(in: model.targets) {
                let shown = GlobalSearch.showsSectionTitle(section, scope: scope, outcomes: outcomes)
                var rows: [Item] = []
                switch section {
                case .songs:
                    switch model.songState {
                    case .failed: rows = [.failure(.songs)]
                    case .ready: rows = cardRows(model.songs.map { .song($0.id) })
                    default: break
                    }
                case .players:
                    switch model.playerState {
                    case .failed: rows = [.failure(.players)]
                    case .ready: rows = cardRows(model.players.map { .player($0.accountId) })
                    default: break
                    }
                case .bands:
                    switch model.bandState {
                    case .failed: rows = [.failure(.bands)]
                    case .ready: rows = cardRows(model.bands.map { .band($0.id) })
                    default: break
                    }
                case .all: break
                }
                guard !rows.isEmpty else { continue }
                if shown { items.append(.title(section, first: items.isEmpty)) }
                items += rows
            }
        }
        updateEntrances(for: items, reflowing: reflowing)
        var snapshot = NSDiffableDataSourceSnapshot<Int, Item>()
        snapshot.appendSections([0])
        snapshot.appendItems(items, toSection: 0)
        if reflowing, let previous = dataSource?.snapshot() {
            snapshot.reconfigureItems(items.filter {
                if case .cards = $0 { return previous.indexOfItem($0) != nil }
                return false
            })
        }
        dataSource?.apply(snapshot, animatingDifferences: false)
        resultsHost.isHidden = items.isEmpty
        if !reflowing { scheduleAnnouncement(model.resultAnnouncement) }
    }

    private func updateEntrances(for items: [Item], reflowing: Bool) {
        let key = model.songs.map { CardID.song($0.id) }
            + model.players.map { CardID.player($0.accountId) }
            + model.bands.map { CardID.band($0.id) }
        if !items.isEmpty, entranceKey != key {
            entranceKey = key
            appearedItems.removeAll()
            entranceScope.noteContentOffset(collection.contentOffset.y)
            entranceScope.reset()
            entranceSettleTask?.cancel()
            let count = GlobalSearch.staggerSlotTotal(scope: model.scope, outcomes: model.outcomes, targets: model.targets)
            entranceSettleTask = Task { [weak self] in
                await FadeStagger.settle(afterRevealing: count) { self?.entranceScope.close() }
            }
        }
        entranceSlots = [:]
        var next = 0
        for item in items {
            let ids: [EntranceID] = switch item {
            case let .title(scope, _): [.title(scope)]
            case let .failure(scope): [.failure(scope)]
            case let .cards(cards): cards.map(EntranceID.card)
            }
            for id in ids {
                if reflowing { appearedItems.insert(id) }
                entranceSlots[id] = next
                next += 1
            }
        }
    }

    private func cardRows(_ cards: [CardID]) -> [Item] {
        WideColumns.rows(cards, columns: resultColumns).map(Item.cards)
    }

    /// Runs the search for the current query (cancelling the previous run).
    private func driveSearch() {
        let key = model.runKey
        guard key != lastRunKey else { return }
        lastRunKey = key
        searchTask?.cancel()
        let model = model
        let session = session
        searchTask = Task { @MainActor in await model.search(session: session) }
    }

    private func scheduleAnnouncement(_ text: String?) {
        announceTask?.cancel()
        guard let text else { return }
        announceTask = Task { @MainActor in
            try? await Task.sleep(for: GlobalSearchResults.announcementDelay)
            guard !Task.isCancelled else { return }
            UIAccessibility.post(notification: .announcement, argument: text)
        }
    }

    deinit {
        MainActor.assumeIsolated {
            searchTask?.cancel()
            announceTask?.cancel()
            entranceSettleTask?.cancel()
        }
    }
}

/// Hosts a self-sizing result row without the native list-cell margins.
private final class UKSearchContentCell: UKSelfSizingCell {
    private var hosted: UIView?
    private var insets: UIEdgeInsets = .zero
    private var entrances: [(UIView, Task<Void, Never>)] = []

    /// Pins the content inside the row's own insets.
    ///
    /// - Parameters:
    ///   - content: The heading or band card.
    ///   - insets: The spacing around that content.
    func show(_ content: UIView, insets: UIEdgeInsets) {
        finishEntrances()
        hosted?.removeFromSuperview()
        hosted = content
        self.insets = insets
        isAccessibilityElement = false
        contentView.ukPin(content, insets: insets)
    }

    /// Gives one card (or heading) its own entrance slot, including in a two-column row.
    func enter(_ content: UIView, index: Int, scope: FestivalFadeInScope) {
        if let task = UKFadeIn.scopedEntrance(content, index: index, scope: scope) {
            entrances.append((content, task))
        }
    }

    /// Stops waiting and restores visibility before reuse or a motion-setting change.
    func finishEntrances() {
        for (view, task) in entrances {
            task.cancel()
            view.layer.removeAllAnimations()
            view.alpha = 1
            view.transform = .identity
        }
        entrances.removeAll()
    }

    override func preferredLayoutAttributesFitting(_ attributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        hosted?.ukPrepare(width: max(0, attributes.size.width - insets.left - insets.right))
        return super.preferredLayoutAttributesFitting(attributes)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        finishEntrances()
        hosted?.removeFromSuperview()
        hosted = nil
    }
}

/// One result action with an inset surface when the button owns the whole list row.
private final class UKSearchResultButton: UIButton {
    /// - Parameters:
    ///   - content: The decorative result contents.
    ///   - insets: Padding inside the card.
    ///   - rowInsets: Padding outside the painted card but inside the button.
    ///   - minimumCardHeight: The minimum height of the painted card in points.
    ///   - identifier: The result's stable test identifier.
    ///   - label: The combined spoken result name.
    ///   - onOpen: Opens the result.
    init(
        content: UIView, insets: UIEdgeInsets, rowInsets: UIEdgeInsets, minimumCardHeight: CGFloat = 0,
        identifier: String, label: String, onOpen: @escaping () -> Void
    ) {
        super.init(frame: .zero)
        let card = UKCardView(cornerRadius: UKProfileMetrics.rowCornerRadius)
        card.embed(content, insets: insets)
        card.isUserInteractionEnabled = false
        card.accessibilityElementsHidden = true
        ukPin(card, insets: rowInsets)
        if minimumCardHeight > 0 {
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: minimumCardHeight).isActive = true
        }
        accessibilityIdentifier = identifier
        accessibilityLabel = label
        addAction(UIAction { _ in onOpen() }, for: .primaryActionTriggered)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.7 : 1 }
    }
}
#endif
