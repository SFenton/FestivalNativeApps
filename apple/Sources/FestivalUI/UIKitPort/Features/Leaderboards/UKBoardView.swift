#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Host cell

/// A self-sizing cell that hosts one arbitrary view (a board's title, count, status or
/// song header), pinned to the cell's content with optional insets.
final class UKBoardHostCell: UKSelfSizingCell {
    /// Reuse identifier.
    static let reuseIdentifier = "UKBoardHostCell"
    private var hosted: UIView?

    /// Hosts a view, replacing the previous one.
    ///
    /// - Parameter view: The view to show.
    func host(_ view: UIView) {
        guard hosted !== view else { return }
        hosted?.removeFromSuperview()
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            view.topAnchor.constraint(equalTo: contentView.topAnchor), view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        hosted = view
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        hosted?.removeFromSuperview()
        hosted = nil
    }
}

// MARK: - Board view

/// The scaffold of a paginated board (Full Rankings, Band Rankings, the song boards, Score
/// History): a list of header views and group-card rows in a collection view under a
/// ``UKReloadGate``, with bottom chrome (the player's footer and the pager) pinned over
/// the bottom edge that the rows fade out beneath (``UKBottomChromeFade``).
///
/// Rows are one ``UKLeaderboardRowCell`` for every board, laid out in `columns` columns
/// (row-major pairs in wide landscape, pattern `wide-columns`), each column one group
/// card (leaderboard-row R10). Headers scroll with the rows.
@MainActor
final class UKBoardView: UIView, UICollectionViewDelegate {
    private enum Section: Hashable { case head, rows, tail }
    private struct Item: Hashable {
        let id: String
        let isRow: Bool
    }
    private static let tailPrefix = "tail:"


    /// The reload gate around the list.
    let gate: UKReloadGate
    /// The list.
    let collectionView: UICollectionView
    /// The bottom chrome: the player's footer, then the pager. Empty hides the fade.
    let chrome = UIStackView()
    private let listHost = UIView()
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var bottomFade: UKBottomChromeFade!
    private var heads: [String: UIView] = [:]
    private var headOrder: [String] = []
    private var rows: [String: UKLeaderboardRow] = [:]
    private var rowOrder: [String] = []
    private var rowIndex: [String: Int] = [:]
    private var chromeHeightConstraint: NSLayoutConstraint?
    private var lastChromeHeight: CGFloat = -1

    /// Columns of rows; change through ``setColumns(_:)``.
    private(set) var columns = 1
    /// Inset above the first and below the last row of the rows section.
    var rowsInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16) {
        didSet { collectionView.collectionViewLayout.invalidateLayout() }
    }
    /// Inset around the header section.
    var headInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16) {
        didSet { collectionView.collectionViewLayout.invalidateLayout() }
    }
    /// Inset around the tail section (the player's row that follows the rows at accessibility sizes).
    var tailInsets = NSDirectionalEdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16) {
        didSet { collectionView.collectionViewLayout.invalidateLayout() }
    }
    /// Every row is its own card (Score History) instead of a segment of one group card.
    var separateCards = false
    /// Called as the list scrolls.
    var onScroll: ((UIScrollView) -> Void)?
    /// Called after layout so the page can re-measure (width for fitted columns, columns).
    var onLayout: (() -> Void)?
    /// Decides the number of columns for the board's width; nil keeps one.
    var columnsProvider: ((CGFloat) -> Int)?
    /// The last page whose rows were faded in.
    var lastFadedPage: Int?
    /// Called when the chrome's measured height changed.
    var onChromeChange: (() -> Void)?

    /// Creates the scaffold.
    ///
    /// - Parameters:
    ///   - gateKey: The gate's initial key.
    ///   - isLoading: Whether a load is in flight.
    ///   - spinnerLabel: Spoken spinner label.
    ///   - spinnerIdentifier: Spinner identifier.
    ///   - retainsFrame: Keep the list laid out while a page reloads (song boards).
    init(gateKey: AnyHashable, isLoading: Bool, spinnerLabel: String, spinnerIdentifier: String?, retainsFrame: Bool) {
        gate = UKReloadGate(
            key: gateKey, isLoading: isLoading, spinnerLabel: spinnerLabel, spinnerIdentifier: spinnerIdentifier,
            retainsFrame: retainsFrame
        )
        let layoutBox = LayoutBox()
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout { section, environment in
            layoutBox.board?.makeSection(section, environment: environment)
        })
        super.init(frame: .zero)
        layoutBox.board = self
        backgroundColor = .clear
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.showsVerticalScrollIndicator = true
        collectionView.alwaysBounceVertical = true
        collectionView.contentInsetAdjustmentBehavior = .automatic
        collectionView.register(UKLeaderboardRowCell.self, forCellWithReuseIdentifier: UKLeaderboardRowCell.reuseIdentifier)
        collectionView.register(UKBoardHostCell.self, forCellWithReuseIdentifier: UKBoardHostCell.reuseIdentifier)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        listHost.translatesAutoresizingMaskIntoConstraints = false
        listHost.addSubview(collectionView)
        gate.contentView.addSubview(listHost)
        addSubview(gate)
        chrome.axis = .vertical
        chrome.spacing = 0
        chrome.alignment = .fill
        chrome.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chrome)
        let bottom = safeAreaLayoutGuide.bottomAnchor
        NSLayoutConstraint.activate([
            gate.leadingAnchor.constraint(equalTo: leadingAnchor), gate.trailingAnchor.constraint(equalTo: trailingAnchor),
            gate.topAnchor.constraint(equalTo: topAnchor), gate.bottomAnchor.constraint(equalTo: bottomAnchor),
            listHost.leadingAnchor.constraint(equalTo: gate.contentView.leadingAnchor), listHost.trailingAnchor.constraint(equalTo: gate.contentView.trailingAnchor),
            listHost.topAnchor.constraint(equalTo: gate.contentView.topAnchor), listHost.bottomAnchor.constraint(equalTo: gate.contentView.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: listHost.leadingAnchor), collectionView.trailingAnchor.constraint(equalTo: listHost.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: listHost.topAnchor), collectionView.bottomAnchor.constraint(equalTo: listHost.bottomAnchor),
            chrome.leadingAnchor.constraint(equalTo: leadingAnchor), chrome.trailingAnchor.constraint(equalTo: trailingAnchor),
            chrome.bottomAnchor.constraint(equalTo: bottom),
        ])
        bottomFade = UKBottomChromeFade(maskedView: listHost, scrollView: collectionView)
        configureDataSource()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private final class LayoutBox {
        weak var board: UKBoardView?
    }

    // MARK: Data

    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { [weak self] collectionView, indexPath, item in
            guard let self else { return nil }
            if item.isRow {
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: UKLeaderboardRowCell.reuseIdentifier, for: indexPath
                ) as! UKLeaderboardRowCell
                if let row = rows[item.id] {
                    let index = rowIndex[item.id] ?? 0
                    cell.configure(row, segment: separateCards ? FestivalGroupSegment(isFirst: true, isLast: true) : .position(index: index, count: rowOrder.count, columns: columns))
                }
                return cell
            }
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: UKBoardHostCell.reuseIdentifier, for: indexPath
            ) as! UKBoardHostCell
            if let view = heads[item.id] { cell.host(view) }
            return cell
        }
    }

    /// Replaces the list's content.
    ///
    /// - Parameters:
    ///   - headViews: Header views in order, with stable ids.
    ///   - rowItems: Rows in order, with stable ids.
    func setContent(
        headViews: [(id: String, view: UIView)], rowItems: [(id: String, row: UKLeaderboardRow)],
        tailViews: [(id: String, view: UIView)] = []
    ) {
        heads = Dictionary(uniqueKeysWithValues: (headViews + tailViews).map { ($0.id, $0.view) })
        headOrder = headViews.map(\.id)
        let tailIDs = tailViews.map(\.id)
        rows = Dictionary(uniqueKeysWithValues: rowItems.map { ($0.id, $0.row) })
        rowOrder = rowItems.map(\.id)
        rowIndex = Dictionary(uniqueKeysWithValues: rowOrder.enumerated().map { ($1, $0) })
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.head, .rows, .tail])
        let headItems = headOrder.map { Item(id: $0, isRow: false) }
        let rowItemsList = rowOrder.map { Item(id: $0, isRow: true) }
        let tailItems = tailIDs.map { Item(id: $0, isRow: false) }
        snapshot.appendItems(headItems, toSection: .head)
        snapshot.appendItems(rowItemsList, toSection: .rows)
        snapshot.appendItems(tailItems, toSection: .tail)
        let existing = Set(dataSource.snapshot().itemIdentifiers)
        snapshot.reconfigureItems((headItems + rowItemsList + tailItems).filter { existing.contains($0) })
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    /// The row ids in display order.
    var rowIDs: [String] { rowOrder }

    /// Sets the number of columns and re-segments the rows.
    ///
    /// - Parameter count: Columns of rows.
    func setColumns(_ count: Int) {
        let next = max(1, count)
        guard next != columns else { return }
        columns = next
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(snapshot.itemIdentifiers.filter(\.isRow))
        dataSource.apply(snapshot, animatingDifferences: false)
        collectionView.collectionViewLayout.invalidateLayout()
    }

    /// Re-binds every visible row, e.g. after a selection or width change.
    func reconfigureRows() {
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: Layout

    private func makeSection(_ index: Int, environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? {
        let isRows = index == 1
        let count = isRows ? columns : 1
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
        let group: NSCollectionLayoutGroup
        if count > 1 {
            group = .horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(UKLeaderboardMetrics.minHeight)), repeatingSubitem: item, count: count)
            group.interItemSpacing = .fixed(WideColumns.spacing)
        } else {
            let single = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(isRows ? UKLeaderboardMetrics.minHeight : 44)))
            group = .vertical(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(isRows ? UKLeaderboardMetrics.minHeight : 44)), subitems: [single])
        }
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = isRows ? rowsInsets : (index == 2 ? tailInsets : headInsets)
        section.interGroupSpacing = 0
        return section
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let columnsProvider, bounds.width > 0 { setColumns(columnsProvider(bounds.width)) }
        updateChromeInset()
        bottomFade.layout()
        onLayout?()
    }

    private func updateChromeInset() {
        let height = chrome.arrangedSubviews.isEmpty ? 0 : chrome.bounds.height
        if abs(height - lastChromeHeight) > 0.5 {
            lastChromeHeight = height
            var inset = collectionView.contentInset
            inset.bottom = height
            collectionView.contentInset = inset
            var indicator = collectionView.verticalScrollIndicatorInsets
            indicator.bottom = height
            collectionView.verticalScrollIndicatorInsets = indicator
            onChromeChange?()
        }
        if chrome.arrangedSubviews.isEmpty {
            bottomFade.chromeTop = nil
        } else {
            let top = listHost.convert(CGPoint(x: 0, y: chrome.bounds.minY), from: chrome).y
            bottomFade.chromeTop = top
        }
    }

    // MARK: Delegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) { onScroll?(scrollView) }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        guard let item = dataSource.itemIdentifier(for: indexPath), item.isRow else { return false }
        return rows[item.id]?.onTap != nil
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        self.collectionView(collectionView, shouldHighlightItemAt: indexPath)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath), item.isRow else { return }
        rows[item.id]?.onTap?()
    }

    // MARK: Scrolling

    /// Scrolls a row to the vertical centre once its page is shown.
    ///
    /// - Parameters:
    ///   - id: The row's id.
    ///   - animated: Animate the scroll (not under Reduce Motion).
    func scrollToRow(_ id: String, animated: Bool) {
        guard let item = dataSource.snapshot().itemIdentifiers.first(where: { $0.id == id && $0.isRow }),
              let path = dataSource.indexPath(for: item) else { return }
        collectionView.scrollToItem(at: path, at: .centeredVertically, animated: animated)
    }

    /// Scrolls to the top of the content.
    ///
    /// - Parameter animated: Animate the scroll.
    func scrollToTop(animated: Bool) {
        collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: animated)
    }

    /// The frame of a header in the board's coordinates, for scroll-away tests.
    ///
    /// - Parameter id: The header id.
    /// - Returns: The frame in the list's content coordinates, or nil when not laid out.
    func headFrame(_ id: String) -> CGRect? {
        guard let item = dataSource.snapshot().itemIdentifiers.first(where: { $0.id == id && !$0.isRow }),
              let path = dataSource.indexPath(for: item),
              let attributes = collectionView.layoutAttributesForItem(at: path) else { return nil }
        return attributes.frame
    }

    /// The frame of a row in the list's content coordinates, nil when not laid out.
    ///
    /// - Parameter id: The row id.
    func rowFrame(_ id: String) -> CGRect? {
        guard let item = dataSource.snapshot().itemIdentifiers.first(where: { $0.id == id && $0.isRow }),
              let path = dataSource.indexPath(for: item) else { return nil }
        return collectionView.layoutAttributesForItem(at: path)?.frame
    }

    /// Fades the rows in once per revealed page, not on every re-render.
    ///
    /// - Parameter page: A key for the revealed page.
    func fadeInRowsIfNew(page: Int) {
        guard page != lastFadedPage else { return }
        lastFadedPage = page
        fadeInRows()
    }

    /// Fades the visible rows in as one card (``View/festivalCardSegmentFadeIn(cardIndex:)``).
    func fadeInRows() {
        collectionView.layoutIfNeeded()
        for cell in collectionView.visibleCells { UKFadeIn.fadeIn(cell, staggerIndex: 0) }
    }
}
#endif
