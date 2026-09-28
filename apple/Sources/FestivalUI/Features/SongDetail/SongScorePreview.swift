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
                        .foregroundStyle(BrandTokens.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Retry \(instrument.label) scores") {
                        Task { await load() }
                    }
                    .frame(minHeight: 44)
                case let .loaded(payload):
                    previewRows(payload)
                }
                viewFullLink
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
            await load()
        }
    }

    // MARK: - Card chrome

    /// Large instrument icon and name above the card, like the web `InstrumentHeader` (MD).
    private var instrumentHeader: some View {
        HStack(spacing: 12) {
            InstrumentIcon(
                instrument,
                keyboard: song.usesKeyboardIcon
                    && (instrument == .lead || instrument == .proLead),
                size: headerIconSize
            )
            .accessibilityHidden(true)
            Text(instrument.label)
                .font(.title3.bold())
                .foregroundStyle(BrandTokens.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
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
                .foregroundStyle(BrandTokens.textPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 12)
                .background(
                    BrandTokens.appBackground,
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10))
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
            .foregroundStyle(BrandTokens.textPrimary)
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
        if payload.leaderboard.showLeaderboardEntryTotals == true {
            Text("\(payload.leaderboard.totalEntries) \(instrument.label) entries")
                .font(.subheadline)
                .foregroundStyle(BrandTokens.textPrimary)
        }
        if payload.leaderboard.entries.isEmpty {
            Text("No \(instrument.label) scores yet")
                .foregroundStyle(BrandTokens.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        } else {
            let displayed = Array(payload.leaderboard.entries.prefix(10))
            ForEach(Array(displayed.enumerated()), id: \.offset) { index, entry in
                SongLeaderboardEntryRow(entry: entry)
                    .padding(.vertical, 6)
                    .accessibilityIdentifier(
                        "fst.song-detail.preview-row.\(instrument.rawValue).\(entry.accountId)"
                    )
                if index < displayed.count - 1 {
                    Divider()
                }
            }
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
