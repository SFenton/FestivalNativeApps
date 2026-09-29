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
    private let usesLiveClient: Bool

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
    init(
        song: Song, instrument: Instrument, session: FestivalSession,
        initialState: LoadState? = nil
    ) {
        self.song = song
        self.instrument = instrument
        self.session = session
        _state = State(initialValue: initialState ?? .loading)
        usesLiveClient = initialState == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            instrumentHeader
            VStack(alignment: .leading, spacing: 12) {
                switch state {
                case .loading:
                    FestivalLoadingView(accessibilityLabel: "Loading \(instrument.label) scores")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                case let .failed(message):
                    Text("Scores unavailable: \(message)")
                        .font(.body)
                        .foregroundStyle(FestivalText.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Retry \(instrument.label) scores") {
                        Task { await load() }
                    }
                    .frame(minHeight: 44)
                case let .loaded(payload):
                    previewRows(payload)
                }
                if showsViewFull {
                    viewFullLink
                }
                if session.selectedPlayer != nil {
                    historyLink
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .festivalGlass(.card, cornerRadius: 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: requestKey) {
            guard usesLiveClient else { return }
            // `.task` re-runs every time the card reappears (e.g. popping back from the
            // full chart). Reloading then flashed a spinner and collapsed the card,
            // which read as jitter on Back; keep rows already loaded for this key.
            if case .loaded = state, loadedKey == requestKey { return }
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
            Text("View full leaderboard")
                .font(.body.weight(.semibold))
                .foregroundStyle(FestivalText.primary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 12)
                .modifier(PurpleGlassButtonSurface())
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View full \(instrument.label) leaderboard")
        .accessibilityIdentifier(
            "fst.song-detail.leaderboard.\(instrument.rawValue)"
        )
    }

    /// Selected-player entry point to `/history`.
    ///
    /// Web's only route to `/history` is a "View all scores" action under the
    /// selected player's own score-history chart on this page
    /// (`ScoreHistoryChart.tsx`); that chart is not yet ported, so this is the
    /// equivalent entry point until it is.
    private var historyLink: some View {
        NavigationLink(value: AppRoute.playerHistory(song, instrument)) {
            Label(
                "View \(instrument.label) score history",
                systemImage: "chart.line.uptrend.xyaxis"
            )
            .font(.body)
            .foregroundStyle(FestivalText.primary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12)
            .background(
                BrandTokens.appBackground,
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            "fst.song-detail.history.\(instrument.rawValue)"
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
            .festivalFadeInOnAppear()
        } else {
            VStack(alignment: .leading, spacing: 0) {
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
                    if index < displayed.count - 1 {
                        Divider()
                    }
                }
                // Web `InstrumentCard` spotlight footer: the selected player's own row
                // (rank 11+) sits after the top ten, before View full leaderboard.
                if let spotlight {
                    previewRow(spotlight, highlighted: true)
                        .padding(.top, 8)
                        .accessibilityIdentifier(
                            "fst.song-detail.spotlight.\(instrument.rawValue)"
                        )
                }
            }
            .festivalFadeInOnAppear()
        }
    }

    /// One preview score row; the selected player's row gets the web's purple highlight.
    ///
    /// - Parameters:
    ///   - entry: Score row to draw.
    ///   - highlighted: Whether this row belongs to the selected player.
    /// - Returns: Row view.
    @ViewBuilder
    private func previewRow(_ entry: LeaderboardEntry, highlighted: Bool) -> some View {
        if highlighted {
            SongLeaderboardEntryRow(entry: entry)
                .padding(.vertical, 11)
                .padding(.horizontal, 8)
                .background(
                    BrandTokens.accentPurple.opacity(0.18),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(BrandTokens.accentPurple, lineWidth: 1)
                )
        } else {
            // ~44pt rows, close to the web's 48px `entryRowHeight`.
            SongLeaderboardEntryRow(entry: entry)
                .padding(.vertical, 11)
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

// MARK: - Purple glass button

/// Purple Liquid Glass surface for the card's View full leaderboard button, with an
/// opaque purple fallback under Reduce Transparency / the app's contrast overrides.
private struct PurpleGlassButtonSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false
    @AppStorage("fst.accessibility.lessTransparency") private var lessTransparency = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if reduceTransparency || lessTransparency || moreContrast {
            content.background(BrandTokens.accentPurple, in: shape)
        } else if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(
                .regular.tint(BrandTokens.accentPurple.opacity(0.7)).interactive(), in: shape
            )
        } else {
            content
                .background(BrandTokens.accentPurple.opacity(0.75), in: shape)
                .background(.ultraThinMaterial, in: shape)
        }
    }
}
