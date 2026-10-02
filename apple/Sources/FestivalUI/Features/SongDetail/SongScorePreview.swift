import Foundation
import SwiftUI
import FestivalCore
import FestivalDesign

struct SongScorePreview: View {
    let song: Song
    let instrument: Instrument
    let session: FestivalSession
    @AppStorage("fst.settings.filterInvalidScores") private var filterInvalidScores = false
    @AppStorage("fst.settings.leeway") private var leeway = 1.0
    @ScaledMetric(relativeTo: .title3) private var headerIconSize: CGFloat = 48
    @State private var state: LoadState
    @State private var loadedKey: RequestKey?
    @State private var adoptedPreload = false
    /// Width of the rows column (the web card), for the season column (issue #32).
    @State private var cardWidth: CGFloat = 0
    private let usesLiveClient: Bool
    /// The page already read this chart (Song Detail waits for every card before it
    /// appears); the first `.task` adopts it instead of reading again.
    private let hasPreload: Bool

    private struct RequestKey: Equatable {
        let publicationRevision: Int
        let leeway: Double?
    }

    private var requestKey: RequestKey {
        RequestKey(
            publicationRevision: session.publicationRevision,
            leeway: filterInvalidScores ? (leeway * 10).rounded() / 10 : nil
        )
    }

    enum LoadState {
        case loading
        case loaded(LeaderboardPayload)
        case failed(String)
    }

    /// Use the live client except when hosted tests provide a fixed visual state.
    ///
    /// - Parameters:
    ///   - song: Catalog item whose score preview is requested.
    ///   - instrument: Chart displayed in this card.
    ///   - session: Publication-aware, process-scoped public service client.
    ///   - initialState: Optional fixture state that does not start network work.
    ///   - preloaded: The page's finished read for this card; unlike `initialState`
    ///     the card still reloads on a new publication, leeway or Retry.
    init(
        song: Song, instrument: Instrument, session: FestivalSession,
        initialState: LoadState? = nil, preloaded: LoadState? = nil
    ) {
        self.song = song
        self.instrument = instrument
        self.session = session
        _state = State(initialValue: initialState ?? preloaded ?? .loading)
        usesLiveClient = initialState == nil
        if case .loading? = preloaded { hasPreload = false } else { hasPreload = preloaded != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            instrumentHeader
            VStack(alignment: .leading, spacing: 8) {
                switch state {
                case .loading:
                    FestivalLoadingView(accessibilityLabel: "Loading \(instrument.label) scores")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                case let .failed(message):
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Scores unavailable: \(message)")
                            .font(.body)
                            .foregroundStyle(FestivalText.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Retry \(instrument.label) scores") {
                            Task { await load() }
                        }
                        .frame(minHeight: 44)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .festivalGlass(.card, cornerRadius: 12)
                case let .loaded(payload):
                    previewRows(payload)
                }
                if showsViewFull {
                    viewFullLink
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width.rounded() }) { width in
                cardWidth = width
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: requestKey) {
            guard usesLiveClient else { return }
            // `.task` re-runs every time the card reappears (e.g. popping back from the
            // full chart). Reloading then flashed a spinner and collapsed the card,
            // which read as jitter on Back; keep rows already loaded for this key.
            if case .loaded = state, loadedKey == requestKey { return }
            if hasPreload, loadedKey == nil, !adoptedPreload {
                adoptedPreload = true
                if case .loaded = state { loadedKey = requestKey }
                return
            }
            await load()
        }
    }

    // MARK: - Card chrome

    /// Total entries for the loaded chart, shown as the header subtitle when the
    /// service asks for totals (`showLeaderboardEntryTotals`).
    private var entriesSubtitle: String? {
        guard case let .loaded(payload) = state else { return nil }
        if payload.leaderboard.entries.isEmpty {
            return "No scores recorded yet"
        }
        guard payload.leaderboard.showLeaderboardEntryTotals == true else { return nil }
        let total = payload.leaderboard.totalEntries
        return "\(total.formatted()) \(total == 1 ? "entry" : "entries")"
    }

    /// Whether the card offers View full leaderboard: not while loading and not for a
    /// chart with no scores (web shows View All only with rows); kept on failure so the
    /// full chart stays reachable.
    private var showsViewFull: Bool {
        switch state {
        case .loading: false
        case .failed: true
        case let .loaded(payload): !payload.leaderboard.entries.isEmpty
        }
    }

    /// Large instrument icon, name and optional total-entries subtitle above the card,
    /// like the web `InstrumentHeader` (MD) with a subtitle.
    private var instrumentHeader: some View {
        HStack(spacing: 12) {
            InstrumentIcon(
                instrument,
                keyboard: song.usesKeyboardIcon
                    && (instrument == .lead || instrument == .proLead),
                size: headerIconSize
            )
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(instrument.label)
                    .font(.title3.bold())
                    .foregroundStyle(FestivalText.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let entriesSubtitle {
                    Text(entriesSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(FestivalText.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("fst.song-detail.card-header.\(instrument.rawValue)")
    }

    /// Card-bottom hand-off to the paginated Solo chart (web `ViewFullLeaderboardCta`).
    ///
    /// Shown in every state (not only with rows) so an empty or failed preview still
    /// reaches the full chart; the spoken label names the instrument because nine
    /// otherwise identical actions share the page.
    private var viewFullLink: some View {
        NavigationLink(value: AppRoute.songLeaderboard(song, instrument, 1)) {
            PurpleActionLabel(title: "View full leaderboard")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View full \(instrument.label) leaderboard")
        .accessibilityIdentifier(
            "fst.song-detail.leaderboard.\(instrument.rawValue)"
        )
    }

    /// Keep every response's freshness separate from its visible score rows.
    ///
    /// - Parameter payload: Validated first ten scores and response provenance.
    /// - Returns: Empty, live or offline native row content.
    @ViewBuilder
    private func previewRows(_ payload: LeaderboardPayload) -> some View {
        if payload.publicationId == nil {
            FreshnessDisclosure(
                message: "Showing live scores without publication verification",
                symbol: "info.circle"
            )
        }
        let displayed = Array(payload.leaderboard.entries.prefix(10))
        let spotlight = filterInvalidScores ? nil : SongPreviewSpotlightPolicy.footerEntry(
            selected: session.selectedPlayer,
            score: session.selectedPlayerScores[song.songId]?[instrument],
            displayed: displayed
        )
        if displayed.isEmpty && spotlight == nil {
            // Web `InstrumentEmptyState` subtitle (`songDetail.noScoresSubtitle`); the
            // header subtitle already says "No scores recorded yet".
            Text(
                "When scores are submitted for \(instrument.label), they will show up here "
                    + "on the next leaderboard update."
            )
            .foregroundStyle(FestivalText.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(14)
            .festivalGlass(.card, cornerRadius: 12)
            .festivalFadeInOnAppear()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(displayed.enumerated()), id: \.offset) { index, entry in
                    previewRow(
                        entry,
                        highlighted: SongPreviewSpotlightPolicy.isSelected(
                            entry, selected: session.selectedPlayer
                        )
                    )
                    .accessibilityIdentifier(
                        "fst.song-detail.preview-row.\(instrument.rawValue).\(entry.accountId)"
                    )
                }
                // Web `InstrumentCard` spotlight footer: the selected player's own row
                // (rank 11+) sits after the top ten, before View full leaderboard.
                if let spotlight {
                    previewRow(spotlight, highlighted: true, isFooter: true)
                        .padding(.top, 4)
                        .accessibilityIdentifier(
                            "fst.song-detail.spotlight.\(instrument.rawValue)"
                        )
                }
            }
            // One rank/score width for the top ten and the spotlight row (web
            // `InstrumentCard`'s card-wide `computeRankWidth`), and the season column
            // from the card width (issue #37).
            .leaderboardSectionColumns(LeaderboardRowColumns.fit(
                .topScores, width: Double(cardWidth),
                ranks: (displayed + [spotlight].compactMap { $0 }).map(\.rank),
                scores: (displayed + [spotlight].compactMap { $0 }).map(\.score)
            ))
            .festivalFadeInOnAppear()
        }
    }

    /// One preview score row; the selected player's row gets the web's purple highlight.
    ///
    /// Rows with an account are one navigation button (web `InstrumentCardRowLink`),
    /// so VoiceOver reads rank, name, score and accuracy as a single button and the
    /// whole 48 pt card is the hit target.
    ///
    /// - Parameters:
    ///   - entry: Score row to draw.
    ///   - highlighted: Whether this row belongs to the selected player.
    ///   - isFooter: The selected player's own row appended after the top ten.
    /// - Returns: Row view.
    @ViewBuilder
    private func previewRow(
        _ entry: LeaderboardEntry, highlighted: Bool, isFooter: Bool = false
    ) -> some View {
        let route = SongPreviewSpotlightPolicy.route(
            for: entry, selected: session.selectedPlayer,
            song: song, instrument: instrument, isFooter: isFooter
        )
        // Web `InstrumentCard` `entryRow`: every row its own 48 pt glass card, the
        // player's purple (the one leaderboard row design, operator batch 7.4), with
        // the drill-down chevron inside the card like the Solo chart.
        let content = HStack(spacing: 8) {
            SongLeaderboardEntryRow(
                entry: entry, isPlayer: highlighted,
                currentSeason: session.catalogCurrentSeason
            )
            // Anonymous rows keep the chevron's width so their score column lines up.
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(FestivalText.deemphasized)
                .opacity(route == nil ? 0 : 1)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: LeaderboardRowMetrics.minHeight)
        .modifier(RankingRowSurface(isSelected: highlighted))
        .contentShape(Rectangle())
        if let route {
            NavigationLink(value: route) { content }
                .festivalRowButtonStyle()
                .accessibilityHint(SongPreviewSpotlightPolicy.hint(for: route))
        } else {
            // Anonymous rows have no profile to open.
            content
        }
    }

    /// Refresh one chart only when visible or after an explicit retry.
    private func load() async {
        let requested = requestKey
        state = .loading
        do {
            let payload = try await session.leaderboard(
                songId: song.songId, instrument: instrument,
                page: 1, top: 10, leeway: requested.leeway
            )
            try Task.checkCancellation()
            guard requested == requestKey else { return }
            state = .loaded(payload)
            loadedKey = requested
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled, requested == requestKey else { return }
            state = .failed(error.localizedDescription)
        }
    }
}

// MARK: - Spotlight policy

/// Which preview rows belong to the selected player (web `InstrumentCard` spotlight).
enum SongPreviewSpotlightPolicy {
    /// Whether a top-ten row is the selected player's (case-insensitive account match).
    ///
    /// - Parameters:
    ///   - entry: Preview row.
    ///   - selected: Current selected player, if any.
    /// - Returns: True for the selected player's own row.
    static func isSelected(_ entry: LeaderboardEntry, selected: SelectedPlayerIdentity?) -> Bool {
        guard let selected else { return false }
        return entry.accountId.caseInsensitiveCompare(selected.accountId) == .orderedSame
    }

    /// Where tapping a preview row goes, mirroring the web `InstrumentCard` links:
    /// a top-ten row opens that player's profile (the selected player's own row opens
    /// Statistics, like `getPlayerRoute`); the selected player's footer row opens the
    /// full chart at the page that contains their rank (web `navToPlayer`).
    ///
    /// - Parameters:
    ///   - entry: Tapped preview row.
    ///   - selected: Current selected player, if any.
    ///   - song: Song whose chart is previewed.
    ///   - instrument: Previewed chart.
    ///   - isFooter: The row is the selected player's footer after the top ten.
    /// - Returns: The route to push, or nil for an anonymous row with no account.
    static func route(
        for entry: LeaderboardEntry, selected: SelectedPlayerIdentity?,
        song: Song, instrument: Instrument, isFooter: Bool
    ) -> AppRoute? {
        guard !entry.accountId.isEmpty else { return nil }
        if isFooter {
            return .songLeaderboard(
                song, instrument, LeaderboardPaging.page(forRank: entry.rank, pageSize: 25)
            )
        }
        if isSelected(entry, selected: selected) { return .statistics }
        return .player(accountId: entry.accountId, displayName: entry.displayName)
    }

    /// Spoken hint naming where a preview row's button goes.
    ///
    /// - Parameter route: Route from ``route(for:selected:song:instrument:isFooter:)``.
    /// - Returns: A short VoiceOver hint.
    static func hint(for route: AppRoute) -> String {
        switch route {
        case .statistics: "Opens your statistics"
        case .songLeaderboard: "Opens your page of the full leaderboard"
        default: "Opens player profile"
        }
    }

    /// The selected player's own row to append after the top ten, when they have a
    /// ranked score on this chart that the top ten does not already show.
    ///
    /// - Parameters:
    ///   - selected: Current selected player, if any.
    ///   - score: Their score on this song/instrument from the loaded score index.
    ///   - displayed: Top-ten rows already shown.
    /// - Returns: A synthesized row, or nil.
    static func footerEntry(
        selected: SelectedPlayerIdentity?, score: PlayerScore?, displayed: [LeaderboardEntry]
    ) -> LeaderboardEntry? {
        guard let selected, let score, let rank = score.rank, score.score > 0,
              !displayed.contains(where: { isSelected($0, selected: selected) }) else {
            return nil
        }
        return LeaderboardEntry(
            accountId: selected.accountId, displayName: selected.displayName,
            score: score.score, rank: rank, localRank: nil,
            accuracy: score.accuracy, isFullCombo: score.isFullCombo,
            stars: score.stars, season: score.season, difficulty: score.difficulty
        )
    }
}
