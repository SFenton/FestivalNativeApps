import Foundation
import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Solo leaderboard

/// Loads one 25-row page and owns the native, one-based pagination controls.
struct SoloLeaderboardScreen: View {
    let song: Song
    let instrument: Instrument
    let session: FestivalSession
    @AppStorage("fst.settings.filterInvalidScores") private var filterInvalidScores = false
    @AppStorage("fst.settings.leeway") private var leeway = 1.0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var path: [AppRoute]
    @State private var page: Int
    @State private var state: LoadState
    @State private var lastRequest: RequestKey?

    enum LoadState {
        case loading
        case loaded(LeaderboardPayload)
        case failed(String)
    }

    private struct RequestKey: Hashable {
        let page: Int
        let publicationRevision: Int
        let leeway: Double?
    }

    private var requestKey: RequestKey {
        RequestKey(
            page: page, publicationRevision: session.publicationRevision,
            leeway: filterInvalidScores ? (leeway * 10).rounded() / 10 : nil
        )
    }

    /// Carry an explicit deep-link page into this screen before cached history.
    ///
    /// - Parameters:
    ///   - song: Current catalog song.
    ///   - instrument: Requested solo chart.
    ///   - session: Shared process-lifetime API and artwork session.
    ///   - initialPage: One-based page from navigation/deep link.
    ///   - path: Native tab's route descriptor to update on paging.
    ///   - initialState: Loading in production, fixture state in hosted UI tests.
    init(
        song: Song, instrument: Instrument, session: FestivalSession,
        initialPage: Int, path: Binding<[AppRoute]>, initialState: LoadState = .loading
    ) {
        self.song = song
        self.instrument = instrument
        self.session = session
        _page = State(initialValue: max(1, initialPage))
        _path = path
        _state = State(initialValue: initialState)
    }

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView("Loading leaderboard")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ServiceUnavailableView(title: "Leaderboard unavailable", message: message) {
                    Task { await loadPage() }
                }
            case let .loaded(payload):
                VStack(spacing: 0) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        scoreBanner(payload)
                        scoreHeader(payload)
                    }
                    List {
                        if dynamicTypeSize.isAccessibilitySize {
                            scoreBanner(payload)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                            scoreHeader(payload)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }
                        ForEach(payload.leaderboard.entries) { entry in
                            SongLeaderboardEntryRow(entry: entry)
                            .listRowBackground(BrandTokens.cardBackground)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier(
                                "fst.song-leaderboard.row.\(entry.accountId)"
                            )
                        }
                    }
                    .scrollContentBackground(.hidden)
                    pagination(totalPages: payload.leaderboard.pageCount)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .festivalBackground(.song(song.albumArt), session: session)
        .navigationTitle("\(song.title) - \(instrument.label)")
        .task(id: requestKey) {
            if case .loading = state {
                await loadPage()
            } else if let lastRequest, lastRequest != requestKey {
                await loadPage()
            }
        }
    }

    /// Keep score provenance in both the fixed and accessibility-scrolling layouts.
    ///
    /// - Parameter payload: Current chart response with freshness provenance.
    /// - Returns: A native disclosure when the chart is stale or unverified.
    @ViewBuilder
    private func scoreBanner(_ payload: LeaderboardPayload) -> some View {
        if payload.isStale {
            FreshnessDisclosure(
                message: OfflineDisclosure.label(
                    .scores, publicationId: payload.publicationId
                ),
                symbol: "wifi.slash"
            )
            .padding(.horizontal, 16)
        } else if payload.publicationId == nil {
            FreshnessDisclosure(
                message: "Showing live scores without publication verification",
                symbol: "info.circle"
            )
            .padding(.horizontal, 16)
        }
    }

    /// Let the source-chart title and totals scroll above rows at large text sizes.
    ///
    /// - Parameter payload: Current chart, including its optional totals disclosure.
    /// - Returns: A wrapping, opaque native song summary.
    private func scoreHeader(_ payload: LeaderboardPayload) -> some View {
        HStack(spacing: 12) {
            ArtworkTile(raw: song.albumArt, session: session, size: 80)
                .id(song.albumArt)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.title3.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text(song.artist)
                    .foregroundStyle(BrandTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if payload.leaderboard.showLeaderboardEntryTotals == true {
                    Text("\(payload.leaderboard.totalEntries) \(instrument.label) entries")
                        .foregroundStyle(BrandTokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(
            BrandTokens.cardBackground,
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    /// Load a specific page and reject late responses from a previous selection.
    private func loadPage() async {
        let requested = requestKey
        lastRequest = requested
        state = .loading
        do {
            let payload = try await session.leaderboard(
                songId: song.songId, instrument: instrument,
                page: requested.page, leeway: requested.leeway
            )
            try Task.checkCancellation()
            guard requested == requestKey else { return }
            let corrected = LeaderboardPaging.corrected(
                requested: requested.page, totalPages: payload.leaderboard.pageCount
            )
            if corrected != requested.page {
                move(to: corrected)
                return
            }
            state = .loaded(payload)
        } catch is CancellationError {
            if requested == requestKey { state = .loading }
        } catch let error as URLError where error.code == .cancelled {
            if requested == requestKey { state = .loading }
        } catch {
            if requested == requestKey {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Change both the visible page and its native navigation descriptor.
    ///
    /// - Parameter destination: One-based page inside the loaded chart's bounds.
    private func move(to destination: Int) {
        state = .loading
        page = destination
        if !path.isEmpty {
            path[path.count - 1] = .songLeaderboard(song, instrument, destination)
        }
    }

    /// Render discoverable first/previous/next/last actions with an announced page.
    ///
    /// - Parameter totalPages: Number of pages computed from local entries.
    /// - Returns: Accessible native pagination control row.
    private func pagination(totalPages: Int) -> some View {
        let first = pagerButton("First", enabled: page > 1) { move(to: 1) }
            .accessibilityIdentifier("fst.song-leaderboard.page-first")
        let previous = pagerButton("Previous", enabled: page > 1) {
            move(to: page - 1)
        }
            .accessibilityIdentifier("fst.song-leaderboard.page-previous")
        let indicator = Text("\(page) / \(totalPages)")
            .monospacedDigit()
            .accessibilityIdentifier("fst.song-leaderboard.page-info")
        let next = pagerButton("Next", enabled: page < totalPages) {
            move(to: page + 1)
        }
            .accessibilityIdentifier("fst.song-leaderboard.page-next")
        let last = pagerButton("Last", enabled: page < totalPages) {
            move(to: totalPages)
        }
            .accessibilityIdentifier("fst.song-leaderboard.page-last")
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                first
                previous
                Spacer(minLength: 0)
            }
            indicator
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                next
                last
            }
        }
        .padding(12)
        .background(BrandTokens.cardBackground)
    }

    /// Keep native pager actions scalable and large enough to touch on every row.
    ///
    /// - Parameters:
    ///   - title: Visible First, Previous, Next or Last action name.
    ///   - enabled: Whether the current page can move in that direction.
    ///   - action: Page transition to run when activated.
    /// - Returns: A native Button with a Fluent opaque plate and Dynamic Type text.
    private func pagerButton(
        _ title: String, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body)
                .foregroundStyle(
                    enabled ? BrandTokens.textPrimary : BrandTokens.textSecondary
                )
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
                .background(
                    BrandTokens.cardBackground,
                    in: RoundedRectangle(cornerRadius: 12)
                )
        }
        .buttonStyle(HighContrastPagerStyle())
        .disabled(!enabled)
    }
}

/// Preserve readable control labels even when their native action is disabled.
