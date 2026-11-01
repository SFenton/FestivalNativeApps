#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Song band leaderboard

/// `/songs/:songId/bands/:bandType` (ports ``SongBandLeaderboardContent``): a song's band
/// leaderboard as band score cards, the selected player's band pinned above the pager
/// (jump to its page when off-page, open the band when on it), and a Band Size page tool.
@MainActor
final class UKSongBandLeaderboardViewController: UKSongBoardViewController {
    private struct RequestKey: Hashable {
        let bandType: BandType
        let page: Int
        let accountId: String?
    }

    private struct Shown {
        let key: RequestKey
        let payload: SongBandLeaderboardPayload
    }

    private var bandType: BandType
    private var page: Int
    private var state: RankLoadState<SongBandLeaderboardPayload> = .loading
    private var shown: Shown?
    private var focus: SongBandRowFocus?
    private var focusPending: Bool
    private var loadTask: Task<Void, Never>?
    private let observations = UKObservationBag()
    private var lastAccount: String??
    private var lastRevealedKey: String?

    /// Creates the screen.
    ///
    /// - Parameters:
    ///   - context: The screen's context.
    ///   - song: The board's song.
    ///   - bandType: Band size key.
    ///   - page: One-based page to open.
    ///   - focus: Band row to highlight and bring into view, if any.
    init(context: UKContext, song: Song, bandType: String, page: Int, focus: SongBandRowFocus?) {
        self.bandType = BandType(rawValue: bandType) ?? .duets
        self.page = max(1, page)
        self.focus = focus
        focusPending = focus != nil
        super.init(
            context: context, song: song, idPrefix: "fst.song-band-leaderboard", spinnerLabel: "Loading band scores",
            spinnerIdentifier: "fst.song-band-leaderboard.loading"
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Derived

    private var requestKey: RequestKey {
        RequestKey(bandType: bandType, page: page, accountId: session.selectedPlayer?.accountId)
    }

    override var rowGap: CGFloat { 6 }
    override var rowInset: CGFloat { 0 }
    override var boardTitle: String { bandType.label }
    override var captionText: String? { bandType.label }
    override var captionInstrument: Instrument? { nil }

    private var chromePayload: SongBandLeaderboardPayload? {
        guard let shown, shown.key.bandType == requestKey.bandType, shown.key.accountId == requestKey.accountId else { return nil }
        return shown.payload
    }

    private var footerEntry: SongBandLeaderboardEntry? {
        guard session.selectedPlayer != nil else { return nil }
        return chromePayload?.leaderboard.selectedEntry
    }

    private func isFocused(_ entry: SongBandLeaderboardEntry) -> Bool { focus?.matches(entry) == true }

    private func isHighlighted(_ entry: SongBandLeaderboardEntry, in leaderboard: SongBandLeaderboardResponse) -> Bool {
        isFocused(entry) || leaderboard.isSelected(entry)
    }

    // MARK: Lifecycle

    override var ukPageTools: [UKPageTool] {
        let item = UIBarButtonItem(
            title: "Band Size", image: UIImage(systemName: "person.3.fill"), primaryAction: nil, menu: bandTypeMenu()
        )
        item.accessibilityIdentifier = "fst.song-band-leaderboard.band-type-menu"
        item.accessibilityLabel = "Band size: \(bandType.label)"
        return [UKPageTool(order: PageToolOrder.primary, item: item)]
    }

    private func bandTypeMenu() -> UIMenu {
        UKBoardMenus.bandTypeMenu(selected: bandType, idPrefix: "fst.song-band-leaderboard.band-type") { [weak self] size in
            self?.select(bandType: size)
        }
    }

    private func select(bandType size: BandType) {
        guard size != bandType else { return }
        bandType = size
        focusPending = false
        page = 1
        ukPageToolsDidChange()
        startLoad()
    }

    override func boardDidLoad() {
        updatePinnedTitle()
        observations.observe { [weak self] in
            guard let self else { return }
            let id = session.selectedPlayer?.accountId
            guard lastAccount != .some(id) else { return }
            let first = lastAccount == nil
            lastAccount = .some(id)
            if !first { startLoad() }
        }
        startLoad()
    }

    override func revealChanged() { render() }
    override func layoutKeyChanged() { render() }

    // MARK: Loading

    private func startLoad() {
        loadTask?.cancel()
        let requested = requestKey
        state = .loading
        boardView.gate.update(key: requested, isLoading: true)
        render()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let payload = try await session.songBandLeaderboard(
                    songId: song.songId, bandType: requested.bandType, page: requested.page, pageSize: 25,
                    accountId: requested.accountId
                )
                try Task.checkCancellation()
                guard requested == requestKey else { return }
                let corrected = min(max(1, requested.page), payload.leaderboard.pageCount)
                if corrected != requested.page {
                    page = corrected
                    startLoad()
                    return
                }
                shown = Shown(key: requested, payload: payload)
                state = .loaded(payload)
                boardView.gate.update(key: requested, isLoading: false)
                render()
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                guard requested == requestKey else { return }
                state = .failed(ServiceIssue(error))
                boardView.gate.update(key: requested, isLoading: false)
                render()
            }
        }
    }

    private func jump(to destination: Int, focusing entry: SongBandLeaderboardEntry) {
        focus = SongBandRowFocus(entry)
        focusPending = true
        page = max(1, destination)
        ukRoute = .songBandLeaderboard(song, bandType: bandType.rawValue, page: page, focus: focus)
        startLoad()
    }

    // MARK: Render

    private func footerColumns() -> LeaderboardRowColumns {
        let row = footerEntry.map { [$0] } ?? []
        return LeaderboardRowColumns.fit(
            .songLeaderboard, width: Double(boardView.bounds.width), ranks: row.map(\.rank), scores: row.map(\.score)
        )
    }

    private func render() {
        guard isViewLoaded else { return }
        updatePinnedTitle()
        var heads: [(id: String, view: UIView)] = []
        var rows: [(id: String, row: UKLeaderboardRow)] = []
        var tails: [(id: String, view: UIView)] = []
        let loaded = shown.flatMap { $0.key.bandType == bandType ? $0.payload.leaderboard : nil }
        heads.append(("header", makeHeader(
            instrument: nil,
            text: SongLeaderboardBoardLine.text(
                name: bandType.label, totalEntries: loaded?.totalEntries, showsTotals: loaded?.showLeaderboardEntryTotals
            ),
            identifier: "fst.song-band-leaderboard.header", boardIdentifier: "fst.song-band-leaderboard.board-title",
            subtitle: SongLeaderboardBoardLine.totalText(totalEntries: loaded?.totalEntries, showsTotals: loaded?.showLeaderboardEntryTotals)
        )))
        var shownPayload: SongBandLeaderboardPayload?
        switch state {
        case .loading:
            heads.append(("result", resultArea(nil)))
        case let .failed(issue):
            let status = UKServiceStatusView(issue, title: "Band scores unavailable") { [weak self] in self?.startLoad() }
            heads.append(("result", resultArea(showsResult ? status : nil)))
        case let .loaded(payload):
            if showsResult {
                shownPayload = payload
                if payload.leaderboard.entries.isEmpty {
                    let empty = UKEmptyStateView(
                        "No band scores found",
                        subtitle: "No \(bandType.label.lowercased()) scores have been recorded for this song yet.",
                        placement: .inline, identifier: "fst.song-band-leaderboard.empty"
                    )
                    heads.append(("empty", empty))
                }
                for entry in payload.leaderboard.entries {
                    let highlighted = isHighlighted(entry, in: payload.leaderboard)
                    let route = SongBandRowNavigation.bandRoute(entry)
                    let model = UKSongBandCardView.Model(
                        entry: entry, highlighted: highlighted, identifier: "fst.song-band-leaderboard.row.\(entry.id)", route: route
                    )
                    rows.append((entry.id, UKLeaderboardRow(
                        kind: .songBand, make: { UKSongBandCardView() }, apply: { ($0 as? UKSongBandCardView)?.apply(model) },
                        isSelectedBand: highlighted, onTap: { [weak self] in self?.context.navigator?.push(route) }
                    )))
                }
            }
        }
        let footer = footerEntry.map { makeFooter($0) }
        let pinned = footer.map { pins($0) } ?? true
        if let footer, !pinned, shownPayload != nil { tails.append(("footer", footer)) }
        boardView.setContent(headViews: heads, rowItems: rows, tailViews: tails)
        applyChrome(
            footer: footer, pinned: pinned,
            pagerState: chromePayload.map { RankingsPagerState(page: page, totalPages: $0.leaderboard.pageCount) }
        ) { [weak self] destination in
            self?.focusPending = false
            self?.page = destination
            self?.ukRoute = .songBandLeaderboard(self!.song, bandType: self!.bandType.rawValue, page: destination, focus: nil)
            self?.startLoad()
        }
        if let shownPayload { rowsRevealed(shownPayload) }
    }

    private func rowsRevealed(_ payload: SongBandLeaderboardPayload) {
        let key = "\(bandType.rawValue):\(page):\(payload.leaderboard.entries.first?.id ?? "")"
        guard key != lastRevealedKey else { return }
        lastRevealedKey = key
        boardView.fadeInRows()
        let entries = payload.leaderboard.entries
        if focusPending {
            guard let index = entries.firstIndex(where: isFocused) else {
                focusPending = false
                return
            }
            reveal(rowID: entries[WideColumns.rowStart(of: index, columns: boardView.columns)].id) { [weak self] in
                self?.focusPending = false
            }
        } else {
            boardView.scrollToTop(animated: false)
        }
    }

    private func footerAction(for entry: SongBandLeaderboardEntry) -> SelectedRowAction {
        if case let .loaded(payload) = state {
            return SongBandRowNavigation.footerAction(for: entry, pageEntries: payload.leaderboard.entries)
        }
        let pageSize = SongBandRowNavigation.pageSize
        return SelectedRowAction.footer(
            rank: entry.rank,
            isVisible: entry.rank > 0 && LeaderboardPaging.page(forRank: entry.rank, pageSize: pageSize) == page,
            pageSize: pageSize
        )
    }

    private func makeFooter(_ entry: SongBandLeaderboardEntry) -> UIView {
        let action = footerAction(for: entry)
        let row = UKSongScoreRowView()
        row.apply(UKSongScoreRowView.Model(
            entry: entry.footerLeaderboardEntry, isPlayer: true, currentSeason: session.catalogCurrentSeason,
            starsAfterScore: true, columns: footerColumns(), identifier: "fst.song-band-leaderboard.footer-row"
        ))
        let footer = UKPinnedFooterView()
        switch action {
        case .openProfile:
            footer.setButton(
                row: row, containerIdentifier: "fst.song-band-leaderboard.spotlight-footer",
                buttonIdentifier: "fst.song-band-leaderboard.spotlight-open", label: action.footerLabel(for: .band, rank: entry.rank)
            )
            footer.onTap = { [weak self] in self?.context.navigator?.push(SongBandRowNavigation.bandRoute(entry)) }
        case let .jump(destination):
            footer.setButton(
                row: row, containerIdentifier: "fst.song-band-leaderboard.spotlight-footer",
                buttonIdentifier: "fst.song-band-leaderboard.spotlight-jump", label: action.footerLabel(for: .band, rank: entry.rank)
            )
            footer.onTap = { [weak self] in self?.jump(to: destination, focusing: entry) }
        }
        return footer
    }
}
#endif
