#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Cells

/// Hosts one category card in the Suggestions list.
private final class UKSuggestionCell: UKSelfSizingCell {
    static let reuse = "UKSuggestionCell"
    private var card: UIView?

    /// Shows a card, replacing the previous one.
    func show(_ view: UIView) {
        if card === view { return }
        card?.removeFromSuperview()
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(view)
        view.ukPin(to: contentView)
        card = view
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        card?.removeFromSuperview()
        card = nil
    }
}

/// The list's last cell: a fixed-height spinner slot while more pages exist, else the
/// "seen every suggestion" message with Start New Mix.
private final class UKSuggestionFooterCell: UKSelfSizingCell {
    static let reuse = "UKSuggestionFooterCell"
    private var content: UIView?

    func configure(hasMore: Bool, isLoadingMore: Bool, startNewMix: @escaping () -> Void) {
        content?.removeFromSuperview()
        let view: UIView
        if hasMore {
            let loading = UKLoadingView(accessibilityLabel: "Loading more suggestions")
            loading.alpha = isLoadingMore ? 1 : 0
            loading.accessibilityElementsHidden = !isLoadingMore
            let holder = UIView()
            loading.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(loading)
            NSLayoutConstraint.activate([
                loading.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
                loading.topAnchor.constraint(equalTo: holder.topAnchor, constant: 12),
                loading.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -12),
            ])
            view = holder
        } else {
            let label = UKLabel("You've seen every current suggestion.", style: .subheadline, alignment: .center)
            let button = UKProminentButton(title: "Start New Mix", identifier: "fst.suggestions.start-new-mix", onTap: startNewMix)
            let stack = UIStackView(arrangedSubviews: [label, button])
            stack.axis = .vertical
            stack.spacing = 12
            stack.alignment = .center
            stack.isLayoutMarginsRelativeArrangement = true
            stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0)
            view = stack
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(view)
        view.ukPin(to: contentView)
        content = view
    }
}

/// A scroll view that only holds the Suggestions collection view, so VoiceOver and UI tests find
/// the list as a ScrollView (as the SwiftUI page's `ScrollView`); it never scrolls itself.
private final class UKSuggestionsListHolder: UIScrollView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isScrollEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Suggestions

/// `/suggestions`: score-driven song suggestions for the selected player
/// (``SuggestionsScreen``). One titled card per generated category, ten categories a page,
/// the next page loaded as the player nears the end, a Filter sheet for instrument and
/// category switches, pull to refresh for a new mix, and two card columns at regular width.
///
/// The Duo dual-source Item Shop pane (``SuggestionsCarouselPane``) is shelved with
/// ``DualSourcePolicy``, so only the page itself is drawn.
final class UKSuggestionsViewController: UKRivalsPageViewController, UICollectionViewDelegate {
    private enum Section: Hashable { case cards, footer }
    private enum Item: Hashable {
        case category(String)
        case footer
    }

    private enum Mode: Equatable {
        case noProfile, syncing, playerFailed, list
    }

    private let viewModel = SuggestionsViewModel(filter: .defaults())
    private lazy var collection = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>?
    private var gate: UKReloadGate?
    private var inner: UIView?
    private var mode: Mode?
    private var cards: [String: UKSuggestionCardView] = [:]
    private var visibleList: [SuggestionCategory] = []
    private var fadeIndexes: [String: Int] = [:]
    private var faded: Set<String> = []
    private var settledGeneration: Int?
    private var loadedAccountId: String?
    private var toolSignature: [Bool] = []
    private var handledPublication: Int?

    override var columnInsets: (top: CGFloat, bottom: CGFloat) { (0, 0) }

    /// Creates the page.
    ///
    /// - Parameter context: The context it was created in.
    override init(context: UKContext) {
        super.init(context: context)
        ukSetPageTitle("Suggestions")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var settingsSignature: AnyHashable { UKSettings.visibleInstruments() }

    private var visibleInstruments: Set<Instrument> { UKSettings.visibleInstruments() }
    private var showsFilter: Bool { session.selectedPlayer != nil && session.playerLoadState == .available }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        observations.observe { [weak self] in self?.refreshState() }
        observations.observe { [weak self] in
            guard let self else { return }
            let revision = self.session.publicationRevision
            guard self.handledPublication != revision else { return }
            self.handledPublication = revision
            guard self.mode == .list else { return }
            self.runTask { [weak self] in
                guard let self else { return }
                await self.viewModel.ensureLoaded(session: self.session)
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UKRefreshCommands.shared.register(self) { [weak self] in await self?.refresh() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        UKRefreshCommands.shared.unregister(self)
    }

    // MARK: Tools

    override var ukToolsStayInBar: Bool { true }

    override var pageTools: [UKPageTool] {
        guard showsFilter else { return [] }
        let tool = Self.tool(
            title: "Filter", symbol: "line.3.horizontal.decrease.circle", identifier: "fst.suggestions.filter-button"
        ) { [weak self] in self?.presentFilter() }
        tool.item.tintColor = viewModel.filter.isActive() ? BrandUIColors.gold : BrandUIColors.textPrimary
        return [tool]
    }

    private func presentFilter() {
        let sheet = UKSuggestionsFilterViewController(
            applied: viewModel.filter, visibleInstruments: Instrument.allCases.filter(visibleInstruments.contains)
        ) { [weak self] updated in
            guard let self else { return }
            self.viewModel.filter = updated
            if let data = try? updated.encoded() { UserDefaults.standard.set(data, forKey: SuggestionFilterSettings.storageKey) }
        }
        UKSheet.present(sheet, from: self, title: "Filter Suggestions", closeIdentifier: "fst.suggestions.filter.done")
    }

    // MARK: Build

    override func build() {
        mode = nil
        gate = nil
        inner = nil
        viewModel.filter = SuggestionFilterSettings.decodeSaved(UserDefaults.standard.data(forKey: SuggestionFilterSettings.storageKey) ?? Data())
        let accountId = session.selectedPlayer?.accountId
        if loadedAccountId != accountId {
            loadedAccountId = accountId
            viewModel.invalidate()
            cards = [:]
            faded = []
        }
        if accountId != nil {
            runTask { [weak self] in
                guard let self else { return }
                await self.viewModel.ensureLoaded(session: self.session)
            }
        }
        refreshState()
    }

    /// Chooses what the page shows for the session and view-model state, and keeps it current.
    private func refreshState() {
        guard isViewLoaded else { return }
        let next: Mode
        if session.selectedPlayer == nil {
            next = .noProfile
        } else if session.playerLoadState == .syncing {
            next = .syncing
        } else if case .failed = session.playerLoadState {
            next = .playerFailed
        } else {
            next = .list
        }
        if next != mode {
            mode = next
            switch next {
            case .noProfile:
                showEmpty(
                    "No Profile Selected", systemImage: "sparkles", subtitle: "Select a player to see personalized suggestions.",
                    identifier: "fst.suggestions.empty",
                    actions: [UKProminentButton(title: "Choose Profile", identifier: "fst.suggestions.choose-profile") { [weak self] in
                        self?.context.navigator?.presentProfile()
                    }]
                )
            case .syncing:
                let status = UKServiceStatusView(
                    .other(message: "This player's scores are still being published. Check back soon."), title: "Scores Syncing",
                    systemImage: "arrow.triangle.2.circlepath"
                ) { [weak self] in
                    guard let self else { return }
                    Task { await self.session.refreshSelectedPlayer() }
                }
                status.accessibilityIdentifier = "fst.suggestions.syncing"
                showFill(status)
            case .playerFailed:
                if case let .failed(issue) = session.playerLoadState {
                    showStatus(issue, title: "Could Not Load Player") { [weak self] in
                        guard let self else { return }
                        Task { await self.session.refreshSelectedPlayer() }
                    }
                }
            case .list:
                installList()
            }
        }
        if mode == .list { updateList() }
        let signature = [showsFilter, viewModel.filter.isActive()]
        if signature != toolSignature {
            toolSignature = signature
            ukPageToolsDidChange()
        }
    }

    // MARK: List

    private func installList() {
        let key = session.selectedPlayer?.accountId
        let gate = UKReloadGate(
            key: key ?? "", isLoading: isFirstPageLoading, spinnerLabel: "Loading Suggestions", spinnerIdentifier: "fst.suggestions.loading"
        )
        self.gate = gate
        showFill(gate, edgeToEdge: true)
        collection.backgroundColor = .clear
        collection.delegate = self
        collection.alwaysBounceVertical = true
        collection.translatesAutoresizingMaskIntoConstraints = false
        // The list reads as a ScrollView named `fst.suggestions.list` (the SwiftUI element type); a
        // plain scroll view holds the collection view, which does the scrolling.
        let holder = UKSuggestionsListHolder()
        holder.accessibilityIdentifier = "fst.suggestions.list"
        holder.translatesAutoresizingMaskIntoConstraints = false
        gate.contentView.addSubview(holder)
        holder.ukPin(to: gate.contentView)
        collection.translatesAutoresizingMaskIntoConstraints = true
        collection.frame = holder.bounds
        collection.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        holder.addSubview(collection)
        setContentScrollView(collection)
        collection.refreshControl = {
            let control = UIRefreshControl()
            control.tintColor = BrandUIColors.textPrimary
            control.addAction(UIAction { [weak self, weak control] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.refresh()
                    control?.endRefreshing()
                }
            }, for: .valueChanged)
            return control
        }()
        configureDataSource()
    }

    private var isFirstPageLoading: Bool {
        switch viewModel.loadState {
        case .idle, .loading: viewModel.categories.isEmpty
        case .failed, .loaded: false
        }
    }

    private func refresh() async {
        viewModel.startNewMix()
        cards = [:]
        faded = []
        await viewModel.ensureLoaded(session: session)
    }

    private func updateList() {
        gate?.update(key: session.selectedPlayer?.accountId ?? "", isLoading: isFirstPageLoading)
        inner?.removeFromSuperview()
        inner = nil
        visibleList = viewModel.visibleCategories(appVisibleInstruments: visibleInstruments)
        var showsCollection = false
        switch viewModel.loadState {
        case .idle, .loading:
            showsCollection = !viewModel.categories.isEmpty
        case let .failed(issue):
            overlay(UKServiceStatusView(issue, title: "Could Not Load Suggestions") { [weak self] in
                guard let self else { return }
                Task { await self.viewModel.ensureLoaded(session: self.session) }
            })
        case .loaded:
            if visibleList.isEmpty {
                let empty = UKEmptyStateView(
                    "No Suggestions", systemImage: "sparkles",
                    subtitle: viewModel.filter.isActive() ? "No suggestions match your filters." : "Play some songs to get personalized suggestions.",
                    identifier: "fst.suggestions.no-results"
                )
                empty.hingeProvider = { [weak self] in self?.ukLayout.splitHinge }
                overlay(empty)
            } else {
                showsCollection = true
            }
        }
        collection.isHidden = !showsCollection
        guard showsCollection else { return }
        let generation = viewModel.batchGeneration
        fadeIndexes = FadeStagger.batchIndexes(
            order: visibleList.map(\.id), batch: viewModel.latestBatchIds, settled: settledGeneration == generation
        )
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.cards, .footer])
        snapshot.appendItems(visibleList.map { .category($0.id) }, toSection: .cards)
        snapshot.appendItems([.footer], toSection: .footer)
        snapshot.reconfigureItems([.footer])
        dataSource?.apply(snapshot, animatingDifferences: false)
        if settledGeneration != generation {
            let count = viewModel.latestBatchIds.count
            runTask { [weak self] in
                await FadeStagger.settle(afterRevealing: count) { self?.settledGeneration = generation }
            }
        }
    }

    private func overlay(_ view: UIView) {
        guard let host = gate?.contentView else { return }
        view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(view)
        view.ukPin(to: host)
        inner = view
    }

    private func configureDataSource() {
        collection.register(UKSuggestionCell.self, forCellWithReuseIdentifier: UKSuggestionCell.reuse)
        collection.register(UKSuggestionFooterCell.self, forCellWithReuseIdentifier: UKSuggestionFooterCell.reuse)
        dataSource = UICollectionViewDiffableDataSource(collectionView: collection) { [weak self] collection, indexPath, item in
            guard let self else { return nil }
            switch item {
            case let .category(id):
                let cell = collection.dequeueReusableCell(withReuseIdentifier: UKSuggestionCell.reuse, for: indexPath) as! UKSuggestionCell
                if let category = self.visibleList.first(where: { $0.id == id }) {
                    cell.show(self.card(for: category))
                }
                return cell
            case .footer:
                let cell = collection.dequeueReusableCell(withReuseIdentifier: UKSuggestionFooterCell.reuse, for: indexPath) as! UKSuggestionFooterCell
                cell.configure(hasMore: self.viewModel.hasMore, isLoadingMore: self.viewModel.isLoadingMore) { [weak self] in
                    self?.viewModel.startNewMix()
                    self?.cards = [:]
                    self?.faded = []
                }
                return cell
            }
        }
    }

    private func card(for category: SuggestionCategory) -> UKSuggestionCardView {
        let key = "\(category.id)|\(category.songs.map(\.id).joined(separator: ","))"
        if let cached = cards[key] { return cached }
        let card = UKSuggestionCardView(
            category: category, context: context, currentSeason: viewModel.currentSeason, visibleInstruments: visibleInstruments
        )
        cards[key] = card
        return card
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] sectionIndex, _ in
            let grid = sectionIndex == 0 && (self?.ukLayout.widthClass == .regular)
            let columns = grid ? 2 : 1
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0 / CGFloat(columns)), heightDimension: .estimated(320)
            ))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(320)),
                repeatingSubitem: item, count: columns
            )
            group.interItemSpacing = .fixed(20)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 20
            section.contentInsets = NSDirectionalEdgeInsets(
                top: sectionIndex == 0 ? 16 : 0, leading: 16, bottom: sectionIndex == 0 ? 20 : 16, trailing: 16
            )
            return section
        }
    }

    // MARK: Delegate

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard indexPath.section == 0, visibleList.indices.contains(indexPath.item) else { return }
        let category = visibleList[indexPath.item]
        if let index = fadeIndexes[category.id], !faded.contains(category.id) {
            faded.insert(category.id)
            UKFadeIn.fadeIn(cell.contentView, staggerIndex: index)
        }
        guard category.id == visibleList.suffix(3).first?.id else { return }
        runTask { [weak self] in await self?.viewModel.loadMore() }
    }
}
#endif
