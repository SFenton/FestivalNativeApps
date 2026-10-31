#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Song board base

/// What the Solo and band song leaderboards share (ports the common structure of
/// ``SoloLeaderboardScreen`` and ``SongBandLeaderboardContent``): the song's cover as the
/// backdrop, a scrolling song header (or the board's own title beside Song Detail in a
/// split), rows in the one group-card cell, the player's pinned footer and the pager over
/// the bottom edge, and the pinned bar title once the header scrolls away.
@MainActor
class UKSongBoardViewController: UIViewController, UKPageToolsProviding {
    /// The screen's context.
    let context: UKContext
    /// The board's song.
    let song: Song
    /// Identifier prefix (`fst.song-leaderboard`).
    let idPrefix: String
    /// The list scaffold; the gate retains its frame while a page reloads.
    let boardView: UKBoardView
    private lazy var backgroundRegistration = UKBackgroundRegistration(session: context.session, mode: .song(song.albumArt))
    private var titleSlot: UKPinnedTitleSlot!
    private var pinnedKey: String?
    /// The header has scrolled under the bar.
    private(set) var headerHidden = false
    /// Whether the gate shows its result (rows) rather than the spinner.
    var showsResult = true
    private var pager: UKRankingsPagerView?
    /// The pinned footer's measured height at the last render.
    private(set) var selectedRowHeight: CGFloat = 0
    /// Space between two rows and above the pinned chrome.
    var rowGap: CGFloat { 8 }
    /// Inset above the first and below the last row of the group card.
    var rowInset: CGFloat { 4 }
    /// Space between the bar and the song header.
    let headerTopInset: CGFloat = 20
    /// The session.
    var session: FestivalSession { context.session }
    private let observations = UKObservationBag()
    nonisolated(unsafe) private var settingsObserver: NSObjectProtocol?

    init(
        context: UKContext, song: Song, idPrefix: String, spinnerLabel: String, spinnerIdentifier: String,
        initiallyLoading: Bool = true
    ) {
        self.context = context
        self.song = song
        self.idPrefix = idPrefix
        boardView = UKBoardView(
            gateKey: 0, isLoading: initiallyLoading, spinnerLabel: spinnerLabel, spinnerIdentifier: spinnerIdentifier, retainsFrame: true
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
    }

    // MARK: Subclass hooks

    /// The board's navigation title when the song header is shown.
    var boardTitle: String { "" }
    /// The caption under the pinned title (instrument label or band size).
    var captionText: String? { nil }
    /// The instrument whose artwork leads the caption.
    var captionInstrument: Instrument? { nil }
    /// Called when the gate's reveal state changes.
    func revealChanged() {}
    /// Called when a setting the page follows changes.
    func settingsChanged() {}
    /// Called when the view first loads.
    func boardDidLoad() {}
    /// Called after layout when width or columns changed.
    func layoutKeyChanged() {}
    /// Tools of the page.
    var ukPageTools: [UKPageTool] { [] }

    // MARK: Lifecycle

    override func loadView() { view = boardView }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        ukInstallAccountItems()
        ukSetPageTitle(showsSongHeader ? song.title : boardTitle, mode: .inline)
        titleSlot = UKPinnedTitleSlot(item: navigationItem)
        boardView.columnsProvider = { [weak self] width in
            guard let self else { return 1 }
            return WideColumns.count(layout: ukLayout, size: CGSize(width: width, height: boardView.bounds.height), subPage: ukIsSplitSubPage)
        }
        boardView.rowsInsets = NSDirectionalEdgeInsets(top: rowInset, leading: 16, bottom: rowInset, trailing: 16)
        boardView.headInsets = NSDirectionalEdgeInsets(top: headerTopInset, leading: 16, bottom: 8, trailing: 16)
        boardView.tailInsets = NSDirectionalEdgeInsets(top: rowInset, leading: 16, bottom: rowInset, trailing: 16)
        boardView.onScroll = { [weak self] scroll in self?.scrolled(scroll) }
        boardView.onLayout = { [weak self] in self?.layoutChanged() }
        boardView.gate.onRevealChange = { [weak self] reveal in
            guard let self else { return }
            showsResult = reveal.showsResult
            revealChanged()
        }
        settingsObserver = NotificationCenter.default.addObserver(forName: UKSettings.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
        boardDidLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        backgroundRegistration.viewWillAppear()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        backgroundRegistration.viewDidDisappear()
    }

    // MARK: Header

    /// Whether the song header leads the board: not in a split beside Song Detail.
    var showsSongHeader: Bool {
        guard ukSplitPane == .trailing, let stack = ukSectionStack,
              let leading = (stack.leading as? UINavigationController)?.topViewController?.ukRoute,
              case .songDetail = leading else { return true }
        return false
    }

    /// The in-page header view for the board's line.
    ///
    /// - Parameters:
    ///   - instrument: The board line's instrument, nil for a band size.
    ///   - text: The board line.
    ///   - identifier: Header identifier.
    ///   - boardIdentifier: Identifier of the board's own title beside Song Detail.
    ///   - subtitle: The entry total shown under the board title beside Song Detail.
    func makeHeader(instrument: Instrument?, text: String, identifier: String, boardIdentifier: String, subtitle: String?) -> UIView {
        if showsSongHeader {
            return UKSongBoardSeam.makeHeader(song, session, instrument, text, identifier)
        }
        return UKInstrumentPageTitleView(
            instrument: instrument, title: captionTitle, subtitle: subtitle, style: .header, identifier: boardIdentifier
        )
    }

    /// The board's own title beside Song Detail (instrument label or band size).
    var captionTitle: String { captionText ?? "" }

    // MARK: Scrolling

    private func scrolled(_ scroll: UIScrollView) {
        guard let frame = boardView.headFrame("header") else { return }
        let offset = scroll.contentOffset.y + scroll.adjustedContentInset.top
        let hidden = SongHeaderScrollAway.isHidden(offset: offset, headerBottom: frame.maxY)
        if hidden != headerHidden {
            headerHidden = hidden
            updatePinnedTitle()
        }
    }

    /// Refreshes the bar title for the current header-hidden state.
    func updatePinnedTitle() {
        let key = "\(showsSongHeader)|\(song.songId)|\(captionText ?? "")|\(boardTitle)"
        if key != pinnedKey {
            pinnedKey = key
            if showsSongHeader {
                titleSlot.setTitle(UKSongBoardSeam.makePinnedTitle(song, session, captionText, captionInstrument, "\(idPrefix).pinned-title"))
            } else if !ukWindowLayout.sectionChrome.isVerticalBar {
                titleSlot.setTitle(UKInstrumentPageTitleView(
                    instrument: captionInstrument, title: captionTitle, style: .pinned, identifier: "\(idPrefix).pinned-title"
                ))
            } else {
                titleSlot.setTitle(nil)
            }
        }
        ukSetPageTitle(showsSongHeader ? song.title : boardTitle, mode: .inline)
        titleSlot.setShown(headerHidden, animated: true)
    }

    private var lastLayoutKey = ""

    private func layoutChanged() {
        let key = "\(Int(boardView.bounds.width))|\(boardView.columns)|\(traitCollection.preferredContentSizeCategory.rawValue)"
        guard key != lastLayoutKey else { return }
        lastLayoutKey = key
        if boardView.bounds.width > 0 { layoutKeyChanged() }
    }

    // MARK: Chrome

    /// Installs the pinned footer and pager.
    ///
    /// - Parameters:
    ///   - footer: The player's footer view, nil without one.
    ///   - pinned: Whether the footer is pinned above the pager (else it follows the rows).
    ///   - pagerState: The pager state, nil while the first page loads.
    ///   - onPage: Receives the destination page.
    func applyChrome(footer: UIView?, pinned: Bool, pagerState: RankingsPagerState?, onPage: @escaping (Int) -> Void) {
        let chrome = boardView.chrome
        chrome.arrangedSubviews.forEach { chrome.removeArrangedSubview($0); $0.removeFromSuperview() }
        let spacing = PinnedChromeSpacing.resolve(
            rowGap: Double(rowGap), rowBottomInset: Double(rowInset), edgePadding: 8,
            hasFooter: pinned && footer != nil, hasPager: pagerState != nil
        )
        if let footer, pinned {
            chrome.addArrangedSubview(ukPadded(footer, UIEdgeInsets(top: spacing.footerTop, left: 16, bottom: spacing.footerBottom, right: 16)))
        }
        if let pagerState {
            let pager = self.pager ?? UKRankingsPagerView(idPrefix: idPrefix)
            self.pager = pager
            pager.onChange = onPage
            pager.show(pagerState)
            chrome.addArrangedSubview(ukPadded(pager, UIEdgeInsets(top: spacing.pagerTop, left: 16, bottom: 8, right: 16)))
        }
        chrome.accessibilityElements = chrome.arrangedSubviews
    }

    /// Whether a footer pins above the pager at this text size (leaderboard-row R12).
    ///
    /// - Parameter footer: The built footer view.
    func pins(_ footer: UIView) -> Bool {
        let height = UKSelfSizing.fittingHeight(of: footer, width: max(1, boardView.bounds.width - 32))
        selectedRowHeight = height
        return SelectedRowPinning.pins(
            isAccessibilitySize: UKFont.isAccessibilitySize(traitCollection),
            rowHeight: Double(height), boardHeight: Double(boardView.bounds.height)
        )
    }

    /// A status view filling the list area (a failed first page).
    ///
    /// - Parameter status: The status view, or nil to clear it.
    func showStatus(_ status: UIView?) {
        statusHost?.removeFromSuperview()
        statusHost = status
        guard let status else { return }
        status.translatesAutoresizingMaskIntoConstraints = false
        boardView.gate.contentView.addSubview(status)
        NSLayoutConstraint.activate([
            status.leadingAnchor.constraint(equalTo: boardView.gate.contentView.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: boardView.gate.contentView.trailingAnchor),
            status.topAnchor.constraint(equalTo: boardView.gate.contentView.safeAreaLayoutGuide.topAnchor),
            status.bottomAnchor.constraint(equalTo: boardView.gate.contentView.bottomAnchor),
        ])
    }

    private var statusHost: UIView?

    /// Scrolls the selected row into view once its entrance has finished (web `navToPlayer`).
    ///
    /// - Parameter id: The row's id.
    func reveal(rowID id: String, done: @escaping @MainActor () -> Void) {
        Task { [weak self] in
            let animates = SelectedRowReveal.loadFadesPlay && !UKAccessibility.reduceMotion
            try? await Task.sleep(for: SelectedRowReveal.wait(staggerIndex: BoardCardEntrance.index, animates: animates))
            guard let self, !Task.isCancelled else { return }
            boardView.scrollToRow(id, animated: !UKAccessibility.reduceMotion)
            done()
        }
    }

    /// A tall clear/status row standing in for the rows while a page loads or after it failed.
    ///
    /// - Parameter status: The failure to show, nil while loading.
    func resultArea(_ status: UIView?) -> UIView {
        let holder = UIView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        let height = max(1, boardView.bounds.height - 160)
        holder.heightAnchor.constraint(equalToConstant: height).isActive = true
        if let status {
            status.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(status)
            NSLayoutConstraint.activate([
                status.leadingAnchor.constraint(equalTo: holder.leadingAnchor), status.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
                status.topAnchor.constraint(equalTo: holder.topAnchor), status.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
            ])
        } else {
            holder.isAccessibilityElement = false
            holder.accessibilityElementsHidden = true
        }
        return holder
    }
}
#endif
