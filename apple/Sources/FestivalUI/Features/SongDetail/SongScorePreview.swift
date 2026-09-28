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
        VStack(alignment: .leading, spacing: 12) {
            FestivalSectionHeader(instrument.label)
            NavigationLink(value: AppRoute.songLeaderboard(song, instrument, 1)) {
                Label("View full \(instrument.label) leaderboard", systemImage: "arrow.right")
                    .font(.body)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 12)
                    .background(
                        BrandTokens.appBackground,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(
                "fst.song-detail.leaderboard.\(instrument.rawValue)"
            )
            switch state {
            case .loading:
                ProgressView("Loading \(instrument.label) scores")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            case let .failed(message):
                Text("Scores unavailable: \(message)")
                    .font(.body)
                    .foregroundStyle(BrandTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retry \(instrument.label) scores") {
                    Task { await load() }
                }
                .frame(minHeight: 44)
            case let .loaded(payload):
                previewRows(payload)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .festivalGlass(.card, cornerRadius: 16)
        .task(id: requestKey) {
            guard usesLiveClient else { return }
            await load()
        }
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
                .foregroundStyle(BrandTokens.textSecondary)
        }
        if payload.leaderboard.entries.isEmpty {
            Text("No \(instrument.label) scores yet")
                .foregroundStyle(BrandTokens.textSecondary)
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
