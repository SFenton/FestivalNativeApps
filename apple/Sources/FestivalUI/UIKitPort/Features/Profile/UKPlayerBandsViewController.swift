#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Player bands

/// `/bands/player/:accountId`: a player's Duo/Trio/Quad bands, matching the web client's
/// `PlayerBandsPage` (``PlayerBandsScreen``).
///
/// `GET /api/player/{accountId}/bands?group=&page=&pageSize=` is a pure read. A group or page
/// change fades the bands out, shows the spinner and fades the new list in (web
/// `usePageTransition`); the cards stagger in on first reveal, fade out above the pinned pager
/// and are not drawn beneath it (issue #305).
@MainActor
final class UKPlayerBandsViewController: UIViewController, UICollectionViewDelegate {
    // MARK: Types

    private struct RequestKey: Hashable {
        let accountId: String
        let group: PlayerBandGroup
        let page: Int
    }

    private enum Section { case bands }

    private static let rowGap: CGFloat = 8
    private static let pageSize = 25

    // MARK: Inputs

    private let context: UKContext
    private let accountId: String
    private let displayName: String?

    // MARK: State

    private var group: PlayerBandGroup
    private var page = 1
    private var state: RankLoadState<PlayerBandListPayload> = .loading
    private var staggerSettled = false
    private var entries: [String: PlayerBandEntry] = [:]
    private var loadTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?

    // MARK: Views

    private let picker = UISegmentedControl()
    private let gate: UKReloadGate
    private let pager: UKProfilePagerView
    private lazy var collection = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<Section, String>?
    private var bottomFade: UKBottomChromeFade?
    private var pagerBottomInset: NSLayoutConstraint?

    private var requestKey: RequestKey { RequestKey(accountId: accountId, group: group, page: page) }

    // MARK: Init

    /// Creates the page.
    ///
    /// - Parameters:
    ///   - context: The screen's context.
    ///   - accountId: Player whose bands to list.
    ///   - displayName: Player name for the title.
    ///   - group: Band size the list opens on (the profile's per-group View All).
    init(context: UKContext, accountId: String, displayName: String?, group: PlayerBandGroup) {
        self.context = context
        self.accountId = accountId
        self.displayName = displayName
        self.group = group
        gate = UKReloadGate(
            key: RequestKey(accountId: accountId, group: group, page: 1), isLoading: true, spinnerLabel: "Loading bands"
        )
        pager = UKProfilePagerView(idPrefix: "fst.player-bands") { _ in }
        super.init(nibName: nil, bundle: nil)
        ukSetPageTitle(displayName.map { "\($0)'s Bands" } ?? "Bands")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        loadTask?.cancel()
        settleTask?.cancel()
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        buildPicker()
        buildContent()
        pager.onChange = { [weak self] destination in self?.go(to: destination) }
        pager.isHidden = true
        load()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        bottomFade?.layout()
        updateChromeTop()
        let inset = pager.isHidden ? 0 : pager.bounds.height - Self.rowGap
        if collection.contentInset.bottom != inset {
            collection.contentInset.bottom = inset
            collection.verticalScrollIndicatorInsets.bottom = inset
        }
    }

    private func updateChromeTop() {
        guard !pager.isHidden, let masked = gate.contentView as UIView? else {
            bottomFade?.chromeTop = nil
            return
        }
        let top = masked.convert(pager.bounds, from: pager).minY
        if bottomFade?.chromeTop != top { bottomFade?.chromeTop = top }
    }

    // MARK: Build

    private func buildPicker() {
        for (index, group) in PlayerBandGroup.allCases.enumerated() {
            picker.insertSegment(withTitle: group.label, at: index, animated: false)
        }
        picker.selectedSegmentIndex = PlayerBandGroup.allCases.firstIndex(of: group) ?? 0
        picker.accessibilityIdentifier = "fst.player-bands.group-picker"
        picker.accessibilityLabel = "Band Group"
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            let next = PlayerBandGroup.allCases[self.picker.selectedSegmentIndex]
            guard next != self.group else { return }
            self.group = next
            self.page = 1
            self.load()
        }, for: .valueChanged)
        view.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            picker.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            picker.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
        ])
    }

    private func buildContent() {
        gate.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gate)
        pager.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pager)
        NSLayoutConstraint.activate([
            gate.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 12),
            gate.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gate.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gate.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pager.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            pager.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            pager.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        collection.backgroundColor = .clear
        collection.delegate = self
        collection.alwaysBounceVertical = true
        collection.accessibilityIdentifier = "fst.player-bands.list"
        let registration = UICollectionView.CellRegistration<UKPlayerBandCell, String> { [weak self] cell, _, id in
            guard let self, let entry = self.entries[id] else { return }
            cell.configure(entry: entry) { [weak self] route in self?.context.navigator?.push(route) }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collection) { collection, indexPath, id in
            collection.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
        }
        bottomFade = UKBottomChromeFade(maskedView: gate.contentView, scrollView: collection)
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, _ in
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1), heightDimension: .estimated(80)
            ))
            let group = NSCollectionLayoutGroup.vertical(layoutSize: item.layoutSize, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = UKPlayerBandsViewController.rowGap
            section.contentInsets = NSDirectionalEdgeInsets(
                top: 4, leading: UKProfileMetrics.pagePadding, bottom: UKPlayerBandsViewController.rowGap, trailing: UKProfileMetrics.pagePadding
            )
            return section
        }
    }

    // MARK: Load

    private func go(to destination: Int) {
        guard destination != page else { return }
        page = destination
        load()
    }

    /// Load the current page, rejecting late responses from a previous selection.
    private func load() {
        loadTask?.cancel()
        let requested = requestKey
        state = .loading
        staggerSettled = false
        settleTask?.cancel()
        render()
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let payload = try await self.context.session.playerBands(
                    accountId: self.accountId, group: requested.group, page: requested.page, pageSize: Self.pageSize
                )
                try Task.checkCancellation()
                guard requested == self.requestKey else { return }
                let corrected = min(max(1, requested.page), payload.list.pageCount(pageSize: Self.pageSize))
                if corrected != requested.page {
                    self.page = corrected
                    self.load()
                    return
                }
                self.state = .loaded(payload)
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                guard requested == self.requestKey else { return }
                self.state = .failed(ServiceIssue(error))
            }
            self.render()
        }
    }

    // MARK: Render

    private func render() {
        let content = gate.contentView
        content.subviews.forEach { $0.removeFromSuperview() }
        pager.isHidden = true
        switch state {
        case .loading:
            break
        case let .failed(issue):
            let status = UKServiceStatusView(issue, title: "Bands unavailable") { [weak self] in self?.load() }
            content.ukPin(status)
        case let .loaded(payload):
            if payload.list.entries.isEmpty {
                let empty = UKEmptyStateView(
                    "No Bands Yet", systemImage: "person.3", subtitle: "No \(group.label.lowercased()) bands were found.",
                    identifier: "fst.player-bands.empty"
                )
                empty.hingeProvider = { [weak self] in self?.ukLayout.splitHinge }
                content.ukPin(empty)
            } else {
                content.ukPin(collection)
                apply(payload.list.entries)
                pager.show(page: page, totalPages: payload.list.pageCount(pageSize: Self.pageSize))
                pager.isHidden = false
                startSettle(count: payload.list.entries.count)
            }
        }
        gate.update(key: requestKey, isLoading: state.isLoading)
        view.setNeedsLayout()
    }

    private func apply(_ rows: [PlayerBandEntry]) {
        entries = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
        snapshot.appendSections([.bands])
        snapshot.appendItems(rows.map(\.id))
        dataSource?.apply(snapshot, animatingDifferences: false)
        collection.setContentOffset(CGPoint(x: 0, y: -collection.adjustedContentInset.top), animated: false)
    }

    /// The first stagger is over once the last shown card has faded in; cards rebuilt after
    /// that (scrolled away and back) appear without a fade (issue #30).
    private func startSettle(count: Int) {
        settleTask = Task { @MainActor [weak self] in
            await FadeStagger.settle(afterRevealing: count) { self?.staggerSettled = true }
        }
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard !staggerSettled, let cell = cell as? UKPlayerBandCell else { return }
        UKFadeIn.fadeIn(cell.contentView, staggerIndex: indexPath.item)
    }
}

// MARK: - Cell

/// A Player Bands list cell: one ``UKPlayerBandRowView`` on its own card.
final class UKPlayerBandCell: UKSelfSizingCell {
    private var row: UKPlayerBandRowView?

    /// Shows a band.
    ///
    /// - Parameters:
    ///   - entry: The band.
    ///   - onOpen: Opens the band's page.
    func configure(entry: PlayerBandEntry, onOpen: @escaping (AppRoute) -> Void) {
        row?.removeFromSuperview()
        let next = UKPlayerBandRowView(entry: entry, grouped: false, onOpen: onOpen)
        contentView.ukPin(next)
        row = next
        backgroundColor = .clear
        contentView.backgroundColor = .clear
    }
}
#endif
