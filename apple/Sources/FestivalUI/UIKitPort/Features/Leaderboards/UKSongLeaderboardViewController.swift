#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Solo song leaderboard

/// `/songs/:songId/:instrument` (ports ``SoloLeaderboardScreen``): one 25-row page of a
/// song's Solo board under the song header, the selected player's footer and the pager
/// pinned over the bottom edge, one-based paging that updates the route.
@MainActor
final class UKSongLeaderboardViewController: UKSongBoardViewController {
    private struct RequestKey: Hashable {
        let page: Int
        let publicationRevision: Int
        let leeway: Double?
    }

    private let instrument: Instrument
    private var page: Int
    private var state: SoloLeaderboardScreen.LoadState = .loading
    private var shownPayload: LeaderboardPayload?
    private var focusPending: Bool
    private var loadTask: Task<Void, Never>?
    private var lastRequest: RequestKey?
    private let observations = UKObservationBag()
    private var lastRevision: Int?

    /// Creates the screen.
    ///
    /// - Parameters:
    ///   - context: The screen's context.
    ///   - song: The board's song.
    ///   - instrument: The chart.
    ///   - page: One-based page to open.
    ///   - focusSelected: Bring the selected player's row into view once the page loads.
    init(context: UKContext, song: Song, instrument: Instrument, page: Int, focusSelected: Bool) {
        self.instrument = instrument
        self.page = max(1, page)
        focusPending = focusSelected
        super.init(
            context: context, song: song, idPrefix: "fst.song-leaderboard", spinnerLabel: "Loading leaderboard",
            spinnerIdentifier: "fst.song-leaderboard.loading"
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Derived

    private var filterInvalidScores: Bool { UKSettings.bool("fst.settings.filterInvalidScores", default: false) }
    private var leeway: Double { UserDefaults.standard.object(forKey: "fst.settings.leeway") as? Double ?? 1.0 }

    private var requestKey: RequestKey {
        RequestKey(
            page: page, publicationRevision: session.publicationRevision,
            leeway: filterInvalidScores ? (leeway * 10).rounded() / 10 : nil
        )
    }

    override var boardTitle: String { instrument.label }
    override var captionText: String? { instrument.label }
    override var captionInstrument: Instrument? { instrument }

    private var loadedPayload: LeaderboardPayload? {
        if case let .loaded(payload) = state { return payload }
        return nil
    }

    private var failedIssue: ServiceIssue? {
        if case let .failed(issue) = state { return issue }
        return nil
    }

    private func isSelectedAccount(_ accountId: String) -> Bool {
        guard let selected = session.selectedPlayer?.accountId else { return false }
        return selected.caseInsensitiveCompare(accountId) == .orderedSame
    }

    // MARK: Lifecycle

    override func boardDidLoad() {
        updatePinnedTitle()
        observations.observe { [weak self] in
            guard let self else { return }
            _ = session.selectedPlayer?.accountId
            _ = session.selectedPlayerScores.count
            let revision = session.publicationRevision
            if lastRevision != nil, lastRevision != revision { startLoad() }
            lastRevision = revision
            if isViewLoaded { render() }
        }
        startLoad()
    }

    override func settingsChanged() {
        if requestKey != lastRequest { startLoad() }
    }

    override func revealChanged() { render() }

    override func layoutKeyChanged() { render() }

    // MARK: Loading

    private func startLoad() {
        loadTask?.cancel()
        let requested = requestKey
        lastRequest = requested
        state = .loading
        boardView.gate.update(key: requested, isLoading: true)
        render()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let payload = try await session.leaderboard(
                    songId: song.songId, instrument: instrument, page: requested.page, leeway: requested.leeway
                )
                try Task.checkCancellation()
                guard requested == requestKey else { return }
                let corrected = LeaderboardPaging.corrected(requested: requested.page, totalPages: payload.leaderboard.pageCount)
                if corrected != requested.page {
                    move(to: corrected)
                    return
                }
                shownPayload = payload
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

    /// Changes the visible page and the route's page.
    ///
    /// - Parameters:
    ///   - destination: One-based page.
    ///   - focusSelected: Bring the selected player's row into view once it loads.
    private func move(to destination: Int, focusSelected: Bool = false) {
        focusPending = focusSelected
        page = destination
        ukRoute = .songLeaderboard(song, instrument, destination, focusSelected: focusSelected)
        startLoad()
    }

    // MARK: Selected player

    private func selectedPlayerEntry() -> LeaderboardEntry? {
        guard let selected = session.selectedPlayer,
              let score = session.selectedPlayerScores[song.songId]?[instrument],
              let rank = score.rank else { return nil }
        return LeaderboardEntry(
            accountId: selected.accountId, displayName: selected.displayName, score: score.score, rank: rank, localRank: nil,
            accuracy: score.accuracy, isFullCombo: score.isFullCombo, stars: score.stars, season: score.season,
            difficulty: score.difficulty
        )
    }

    private func sectionColumns(_ payload: LeaderboardPayload?) -> LeaderboardRowColumns {
        let rows = (payload?.leaderboard.entries ?? []) + [selectedPlayerEntry()].compactMap { $0 }
        return LeaderboardRowColumns.fit(
            .songLeaderboard, width: Double(WideColumns.columnPageWidth(boardView.bounds.width, columns: boardView.columns)),
            ranks: rows.map(\.rank), scores: rows.map(\.score)
        )
    }

    private func playerRoute(for entry: LeaderboardEntry) -> AppRoute {
        if let selected = session.selectedPlayer, selected.accountId == entry.accountId { return .statistics }
        return .player(accountId: entry.accountId, displayName: entry.displayName)
    }

    // MARK: Render

    private func render() {
        guard isViewLoaded else { return }
        updatePinnedTitle()
        guard let shown = shownPayload else {
            // The first page has not loaded: failure shows alone.
            if case let .failed(issue) = state, showsResult {
                showStatus(UKServiceStatusView(issue, title: "Leaderboard unavailable") { [weak self] in self?.startLoad() })
            } else {
                showStatus(nil)
            }
            boardView.setContent(headViews: [], rowItems: [])
            applyChrome(footer: nil, pinned: true, pagerState: nil) { _ in }
            return
        }
        showStatus(nil)
        let rowsPayload = showsResult ? loadedPayload : nil
        let columns = sectionColumns(shown)
        var heads: [(id: String, view: UIView)] = []
        var rows: [(id: String, row: UKLeaderboardRow)] = []
        var tails: [(id: String, view: UIView)] = []
        if shown.isStale {
            heads.append(("banner", UKFreshnessDisclosureView(
                message: OfflineDisclosure.label(.scores, publicationId: shown.publicationId), symbol: "wifi.slash"
            )))
        } else if shown.publicationId == nil {
            heads.append(("banner", UKFreshnessDisclosureView(
                message: "Showing live scores without publication verification", symbol: "info.circle"
            )))
        }
        let total = shown.leaderboard.totalEntries
        let totals = shown.leaderboard.showLeaderboardEntryTotals
        heads.append(("header", makeHeader(
            instrument: instrument,
            text: SongLeaderboardBoardLine.text(name: instrument.label, totalEntries: total, showsTotals: totals),
            identifier: "fst.song-leaderboard.header", boardIdentifier: "fst.song-leaderboard.board-title",
            subtitle: SongLeaderboardBoardLine.totalText(totalEntries: total, showsTotals: totals)
        )))
        if rowsPayload == nil {
            let status = (showsResult ? failedIssue : nil).map { issue in
                UKServiceStatusView(issue, title: "Leaderboard unavailable") { [weak self] in self?.startLoad() } as UIView
            }
            heads.append(("result", resultArea(status)))
        }
        for entry in rowsPayload?.leaderboard.entries ?? [] {
            let model = UKSongScoreRowView.Model(
                entry: entry, isPlayer: isSelectedAccount(entry.accountId), currentSeason: session.catalogCurrentSeason,
                columns: columns, identifier: "fst.song-leaderboard.row.\(entry.accountId)"
            )
            let route = playerRoute(for: entry)
            rows.append((entry.id, UKLeaderboardRow(
                kind: .song, make: { UKSongScoreRowView() }, apply: { ($0 as? UKSongScoreRowView)?.apply(model) },
                isSelectedBand: model.isPlayer, onTap: { [weak self] in self?.context.navigator?.push(route) }
            )))
        }
        let footer = makeFooter(columns: columns)
        let pinned = footer.map { pins($0) } ?? true
        if let footer, !pinned, rowsPayload != nil { tails.append(("footer", footer)) }
        boardView.setContent(headViews: heads, rowItems: rows, tailViews: tails)
        applyChrome(
            footer: footer, pinned: pinned, pagerState: RankingsPagerState(page: page, totalPages: shown.leaderboard.pageCount)
        ) { [weak self] destination in self?.move(to: destination) }
        if let rowsPayload, showsResult { rowsRevealed(rowsPayload) }
    }

    private var lastRevealedKey: String?

    private func rowsRevealed(_ payload: LeaderboardPayload) {
        let key = "\(page):\(payload.leaderboard.entries.first?.accountId ?? "")"
        guard key != lastRevealedKey else { return }
        lastRevealedKey = key
        boardView.fadeInRows()
        if focusPending {
            let entries = payload.leaderboard.entries
            guard let index = entries.firstIndex(where: { isSelectedAccount($0.accountId) }) else {
                focusPending = false
                return
            }
            reveal(rowID: entries[WideColumns.rowStart(of: index, columns: boardView.columns)].id) { [weak self] in
                self?.focusPending = false
            }
        } else {
            let target = LeaderboardPaging.reloadScroll(headerUnderBar: headerHidden, boardChanged: false)
            if target == .top { boardView.scrollToTop(animated: false) } else if let first = payload.leaderboard.entries.first {
                boardView.scrollToRow(first.id, animated: false)
            }
        }
    }

    // MARK: Footer

    private func makeFooter(columns: LeaderboardRowColumns) -> UIView? {
        guard let selected = session.selectedPlayer, let entry = selectedPlayerEntry() else { return nil }
        let rank = entry.rank
        let isVisible = LeaderboardPaging.isSelectedOnPage(
            accountId: selected.accountId, rank: rank, page: page, pageSize: 25,
            entries: loadedPayload?.leaderboard.entries.map(\.accountId)
        )
        let action = SelectedRowAction.footer(rank: rank, isVisible: isVisible, pageSize: 25)
        let row = UKSongScoreRowView()
        row.apply(UKSongScoreRowView.Model(
            entry: entry, isPlayer: true, currentSeason: session.catalogCurrentSeason, columns: columns,
            identifier: "fst.song-leaderboard.footer-row.\(entry.accountId)"
        ))
        let footer = UKPinnedFooterView()
        switch action {
        case .openProfile:
            footer.setButton(
                row: row, containerIdentifier: "fst.song-leaderboard.spotlight-footer",
                buttonIdentifier: "fst.song-leaderboard.spotlight-open", label: action.footerLabel(for: .player, rank: rank)
            )
            footer.onTap = { [weak self] in self?.context.navigator?.push(.statistics) }
        case let .jump(destination):
            footer.setButton(
                row: row, containerIdentifier: "fst.song-leaderboard.spotlight-footer",
                buttonIdentifier: "fst.song-leaderboard.spotlight-jump", label: action.footerLabel(for: .player, rank: rank)
            )
            footer.onTap = { [weak self] in self?.move(to: destination, focusSelected: true) }
        }
        return footer
    }
}
#endif
