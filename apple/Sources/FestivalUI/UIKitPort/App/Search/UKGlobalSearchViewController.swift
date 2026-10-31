#if os(iOS)
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
final class UKGlobalSearchViewController: UIViewController, UISearchResultsUpdating, UISearchBarDelegate,
    UICollectionViewDelegate {
    // MARK: Types

    private enum Item: Hashable {
        case title(GlobalSearchScope)
        case failure(GlobalSearchScope)
        case song(String)
        case player(String)
        case band(String)
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
    private lazy var collection = UICollectionView(frame: .zero, collectionViewLayout: Self.makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Int, Item>?
    private let hint = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let emptyState = UIContentUnavailableView(configuration: .empty())
    private let searchController = UISearchController(searchResultsController: nil)
    private var bottomField: UKBottomSearchField?

    // MARK: State

    private let observations = UKObservationBag()
    private var searchTask: Task<Void, Never>?
    private var announceTask: Task<Void, Never>?
    private var ids: GlobalSearchIdentifiers { GlobalSearchIdentifiers(model.targets) }
    private var lastRunKey: GlobalSearchModel.RunKey?
    private var isSelectedTab = false

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
        observations.observe { [weak self] in self?.render() }
        observations.observe { [weak self] in self?.driveSearch() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshFieldPlacement()
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
        if selected, asTab {
            if usesBottomField { bottomField?.field.becomeFirstResponder() } else { searchController.isActive = true }
        }
    }

    // MARK: Field

    private func configureField() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.searchBar.placeholder = GlobalSearch.prompt(for: model.scope, targets: model.targets)
        searchController.searchBar.delegate = self
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.searchTextField.accessibilityLabel = model.targets.fieldLabel
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
                collection.contentInset.bottom = 80
            }
            bottomField?.refreshPlacement()
        } else {
            bottomField?.removeFromSuperview()
            bottomField = nil
            collection.contentInset.bottom = 0
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
        NSLayoutConstraint.activate([
            scopeControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            scopeControl.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            scopeControl.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
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
        collection.translatesAutoresizingMaskIntoConstraints = false
        collection.backgroundColor = .clear
        collection.delegate = self
        collection.keyboardDismissMode = .onDrag
        view.addSubview(collection)
        NSLayoutConstraint.activate([
            collection.topAnchor.constraint(equalTo: scopeControl.bottomAnchor, constant: 10),
            collection.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collection.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collection.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let titleCell = UICollectionView.CellRegistration<UICollectionViewListCell, GlobalSearchScope> { [weak self] cell, _, scope in
            guard let self else { return }
            var content = UIListContentConfiguration.cell()
            content.text = scope == .all ? "" : scope.title
            content.textProperties.font = UIFontMetrics(forTextStyle: .title3).scaledFont(for: .systemFont(ofSize: 20, weight: .bold))
            content.textProperties.color = BrandUIColors.textPrimary
            cell.contentConfiguration = content
            cell.backgroundConfiguration = .clear()
            cell.isAccessibilityElement = true
            cell.accessibilityLabel = scope.title
            cell.accessibilityTraits = .header
            cell.accessibilityIdentifier = self.ids("section.\(scope.rawValue)")
        }
        let cardCell = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { [weak self] cell, _, item in
            self?.configureCard(cell, for: item)
        }
        dataSource = UICollectionViewDiffableDataSource<Int, Item>(collectionView: collection) { collectionView, indexPath, item in
            if case let .title(scope) = item {
                return collectionView.dequeueConfiguredReusableCell(using: titleCell, for: indexPath, item: scope)
            }
            return collectionView.dequeueConfiguredReusableCell(using: cardCell, for: indexPath, item: item)
        }
    }

    private func card(_ cell: UICollectionViewListCell) -> UIBackgroundConfiguration {
        var background = UIBackgroundConfiguration.clear()
        background.backgroundColor = BrandUIColors.surfaceFrosted
        background.cornerRadius = 12
        background.strokeColor = BrandUIColors.glassBorder
        background.strokeWidth = 1
        background.backgroundInsets = NSDirectionalEdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16)
        return background
    }

    /// The cell's cover art tile, created on first use and hidden for rows without art.
    private func artworkTile(in cell: UICollectionViewListCell) -> UKArtworkTileView {
        if let existing = cell.contentView.viewWithTag(Self.artworkTag) as? UKArtworkTileView {
            existing.isHidden = false
            return existing
        }
        let tile = UKArtworkTileView(size: 44)
        tile.tag = Self.artworkTag
        cell.contentView.addSubview(tile)
        NSLayoutConstraint.activate([
            tile.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 28),
            tile.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
        ])
        return tile
    }

    private static let artworkTag = 4401

    private func configureCard(_ cell: UICollectionViewListCell, for item: Item) {
        cell.contentView.viewWithTag(Self.artworkTag)?.isHidden = true
        cell.backgroundConfiguration = card(cell)
        cell.isAccessibilityElement = true
        cell.accessibilityTraits = .button
        var content = UIListContentConfiguration.subtitleCell()
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 28, bottom: 10, trailing: 28)
        content.textProperties.color = BrandUIColors.textPrimary
        content.secondaryTextProperties.color = BrandUIColors.textPrimary
        switch item {
        case let .song(id):
            guard let song = model.songs.first(where: { $0.id == id }) else { return }
            content.text = song.title
            content.textProperties.font = .preferredFont(forTextStyle: .headline)
            content.secondaryText = GlobalSearchResults.subtitle(for: song)
            content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
            // The cover is a UKArtworkTileView over the image slot, as the SwiftUI row's ArtworkTile.
            content.image = UIImage()
            content.imageProperties.reservedLayoutSize = CGSize(width: 44, height: 44)
            artworkTile(in: cell).configure(raw: song.albumArt, session: session)
            cell.accessibilityLabel = [content.text, content.secondaryText].compactMap { $0 }.joined(separator: ", ")
            cell.accessibilityIdentifier = ids("result.song")
        case let .player(id):
            guard let player = model.players.first(where: { $0.accountId == id }) else { return }
            content = UIListContentConfiguration.cell()
            content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 15, leading: 32, bottom: 15, trailing: 32)
            content.text = player.displayName
            content.textProperties.color = BrandUIColors.textPrimary
            content.textProperties.font = .preferredFont(forTextStyle: .body)
            content.image = UIImage(systemName: "person.crop.circle")
            content.imageProperties.tintColor = BrandUIColors.textPrimary
            cell.accessibilityLabel = player.displayName
            cell.accessibilityIdentifier = ids.player(player.accountId)
        case let .band(id):
            guard let band = model.bands.first(where: { $0.id == id }) else { return }
            content = UIListContentConfiguration.subtitleCell()
            content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 28, bottom: 10, trailing: 28)
            content.text = band.members.map(\.resolvedName).joined(separator: "\n")
            content.textProperties.numberOfLines = 0
            content.textProperties.color = BrandUIColors.textPrimary
            content.secondaryText = "\(band.appearanceCount.formatted()) songs together"
            content.secondaryTextProperties.color = BrandUIColors.textPrimary
            content.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
            cell.accessibilityLabel = PlayerBandRow.spokenLabel(band)
            cell.accessibilityHint = "Opens band"
            cell.accessibilityIdentifier = ids("result.band")
            cell.accessories = [.disclosureIndicator()]
        case let .failure(scope):
            content = UIListContentConfiguration.cell()
            let issue: ServiceIssue? = {
                switch scope {
                case .songs: if case let .failed(i) = model.songState { return i }
                case .players: if case let .failed(i) = model.playerState { return i }
                case .bands: if case let .failed(i) = model.bandState { return i }
                case .all: break
                }
                return nil
            }()
            content.text = issue.map { $0.title ?? GlobalSearch.unavailableTitle(for: scope) }
            content.textProperties.font = .preferredFont(forTextStyle: .footnote)
            content.textProperties.color = BrandUIColors.textPrimary
            content.image = UIImage(systemName: issue.map { ServiceStatusView.symbolName(for: $0) } ?? "exclamationmark.triangle")
            content.imageProperties.tintColor = BrandUIColors.gold
            cell.accessibilityLabel = content.text
            cell.accessibilityTraits = .staticText
            cell.accessibilityIdentifier = ids("\(scope.rawValue)-error")
        case .title:
            break
        }
        cell.contentConfiguration = content
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        switch dataSource?.itemIdentifier(for: indexPath) {
        case .song, .player, .band: true
        default: false
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        switch dataSource?.itemIdentifier(for: indexPath) {
        case let .song(id):
            if let song = model.songs.first(where: { $0.id == id }) { open(.songDetail(song)) }
        case let .player(id):
            guard let player = model.players.first(where: { $0.accountId == id }) else { return }
            if session.selectedPlayer?.accountId == player.accountId {
                open(.statistics)
            } else {
                open(.player(accountId: player.accountId, displayName: player.displayName))
            }
        case let .band(id):
            if let band = model.bands.first(where: { $0.id == id }) {
                open(.band(bandId: band.bandId, name: band.membersLabel, bandType: band.bandType, teamKey: band.teamKey))
            }
        default: break
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
        spinner.color = BrandUIColors.textPrimary
        spinner.accessibilityLabel = "Searching"
        spinner.accessibilityIdentifier = ids("loading")
        spinner.isAccessibilityElement = true
        for state in [hint, spinner, emptyState] as [UIView] {
            state.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(state)
        }
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: collection.centerXAnchor),
            hint.centerYAnchor.constraint(equalTo: collection.centerYAnchor),
            hint.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            spinner.centerXAnchor.constraint(equalTo: collection.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: collection.centerYAnchor),
            emptyState.centerXAnchor.constraint(equalTo: collection.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: collection.centerYAnchor),
            emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        emptyState.backgroundColor = .clear
    }

    // MARK: Rendering

    /// Renders the model: the placeholder, spinner or empty state, or the result cards.
    private func render() {
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
            spinner.startAnimating()
        } else if empty, let state = GlobalSearch.emptyState(scope: scope, query: query, targets: model.targets) {
            var configuration = UIContentUnavailableConfiguration.empty()
            configuration.image = UIImage(systemName: "magnifyingglass")
            configuration.text = state.title
            configuration.secondaryText = state.subtitle
            configuration.textProperties.color = BrandUIColors.textPrimary
            configuration.secondaryTextProperties.color = BrandUIColors.textPrimary
            configuration.imageProperties.tintColor = BrandUIColors.textSecondary
            emptyState.configuration = configuration
            emptyState.isAccessibilityElement = true
            emptyState.accessibilityLabel = state.accessibilityLabel
            emptyState.accessibilityIdentifier = ids("hint")
            emptyState.isHidden = false
        } else {
            for section in scope.sections(in: model.targets) {
                let shown = GlobalSearch.showsSectionTitle(section, scope: scope, outcomes: outcomes)
                var rows: [Item] = []
                switch section {
                case .songs:
                    switch model.songState {
                    case .failed: rows = [.failure(.songs)]
                    case .ready: rows = model.songs.map { .song($0.id) }
                    default: break
                    }
                case .players:
                    switch model.playerState {
                    case .failed: rows = [.failure(.players)]
                    case .ready: rows = model.players.map { .player($0.accountId) }
                    default: break
                    }
                case .bands:
                    switch model.bandState {
                    case .failed: rows = [.failure(.bands)]
                    case .ready: rows = model.bands.map { .band($0.id) }
                    default: break
                    }
                case .all: break
                }
                guard !rows.isEmpty else { continue }
                if shown { items.append(.title(section)) }
                items += rows
            }
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, Item>()
        snapshot.appendSections([0])
        snapshot.appendItems(items, toSection: 0)
        dataSource?.apply(snapshot, animatingDifferences: false)
        collection.isHidden = items.isEmpty
        scheduleAnnouncement(model.resultAnnouncement)
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
        }
    }
}
#endif
