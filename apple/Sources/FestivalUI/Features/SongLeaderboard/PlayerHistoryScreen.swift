import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - PlayerHistoryScreen

/// `/songs/:songId/:instrument/history` — the selected player's tracked score
/// history for one song and instrument. Native port of `PlayerHistoryPage`
/// (`FortniteFestivalWeb/src/pages/leaderboard/player/PlayerHistoryPage.tsx`).
struct PlayerHistoryScreen: View {
    let session: FestivalSession
    let song: Song
    let instrument: Instrument
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var state: LoadState = .loading
    @State private var sortMode: PlayerScoreSortMode = .score
    @State private var sortAscending = false
    /// First staggered reveal finished; recycled rows then appear instantly.
    @State private var staggerSettled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Scroll target at the top of the history list (the chart row).
    private static let topAnchor = "fst.history.top"
    @State private var sortSheetPresented = false
    @State private var lastRequest: RequestKey?

    enum LoadState {
        case loading
        case loaded(PlayerHistoryPayload)
        case failed(ServiceIssue)
    }

    private struct RequestKey: Hashable {
        let accountId: String
        let publicationRevision: Int
    }

    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (API client, selected profile, caches).
    ///   - song: Song whose history to show.
    ///   - instrument: Chart whose history to show.
    init(session: FestivalSession, song: Song, instrument: Instrument) {
        self.session = session
        self.song = song
        self.instrument = instrument
    }

    /// `.topBarTrailing` is iOS/iPadOS-only; macOS toolbars use `.automatic`.
    private var sortButtonPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .automatic
        #endif
    }

    private var requestKey: RequestKey? {
        guard let accountId = session.selectedPlayer?.accountId else { return nil }
        return RequestKey(accountId: accountId, publicationRevision: session.publicationRevision)
    }

    var body: some View {
        Group {
            if session.selectedPlayer == nil {
                ContentUnavailableView(
                    "Choose a Profile", systemImage: "person.crop.circle",
                    description: Text("Select a player to view score history.")
                )
            } else {
                switch state {
                case .loading:
                    FestivalLoadingView(accessibilityLabel: "Loading Score History")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .failed(issue):
                    ServiceStatusView(issue, title: "History unavailable") {
                        Task { await load() }
                    }
                case let .loaded(payload):
                    loadedBody(payload)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .detailFadeTestSafe()
        .festivalBackground(.song(song.albumArt), session: session)
        .navigationTitle(song.title)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    InstrumentIcon(instrument, size: 20)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(song.title).font(.headline).lineLimit(1)
                        Text("Score History").font(.caption)
                            .foregroundStyle(BrandTokens.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            ToolbarItem(placement: sortButtonPlacement) {
                Button {
                    sortSheetPresented = true
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .tint(sortMode != .score || sortAscending
                    ? BrandTokens.gold : BrandTokens.textPrimary)
                .accessibilityIdentifier("fst.history.sort.open")
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $sortSheetPresented) {
            PlayerHistorySortSheet(mode: sortMode, ascending: sortAscending) { mode, ascending in
                sortMode = mode
                sortAscending = ascending
            }
            .festivalSheet(.compact)
        }
        .task(id: requestKey) {
            guard requestKey != nil else { return }
            if case .loading = state {
                await load()
            } else if let lastRequest, lastRequest != requestKey {
                await load()
            }
        }
    }

    @ViewBuilder
    private func loadedBody(_ payload: PlayerHistoryPayload) -> some View {
        switch payload.state {
        case .unregistered:
            ContentUnavailableView(
                "History Unavailable", systemImage: "clock.badge.xmark",
                description: Text("Score history is only available for registered users.")
            )
        case .syncing:
            VStack(spacing: 16) {
                FestivalLoadingView(accessibilityLabel: "Score history syncing")
                Text("Score history is still syncing for this player. Check back soon.")
                    .foregroundStyle(BrandTokens.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .available:
            let entries = payload.entries(songId: song.songId, instrument: instrument)
            let sorted = PlayerScoreHistorySort.sorted(entries, mode: sortMode, ascending: sortAscending)
            let highScoreIndex = PlayerScoreHistorySort.highScoreIndex(in: sorted)
            if sorted.isEmpty {
                ContentUnavailableView(
                    "No Score History", systemImage: "clock.arrow.circlepath",
                    description: Text("No score history for this instrument.")
                )
            } else {
                ScrollViewReader { proxy in
                List {
                    if payload.isStale {
                        FreshnessDisclosure(
                            message: OfflineDisclosure.label(
                                .scores, publicationId: payload.publicationId
                            ),
                            symbol: "wifi.slash"
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                    PlayerHistoryChart(entries: sorted, highScoreIndex: highScoreIndex)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .id(Self.topAnchor)
                    ForEach(Array(sorted.enumerated()), id: \.element.changedAt) { index, entry in
                        PlayerHistoryRow(entry: entry, isHighScore: index == highScoreIndex)
                            .padding(12)
                            .background(
                                index == highScoreIndex
                                    ? BrandTokens.accentPurple.opacity(0.18)
                                    : BrandTokens.cardBackground,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .detailStaggeredFadeIn(index: index, settled: staggerSettled)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("fst.history.row.\(index)")
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                // Operator rule: changing the sort scrolls back to the top of the
                // re-sorted list.
                .onChange(of: PlayerHistorySortKey(mode: sortMode, ascending: sortAscending)) { _, _ in
                    if reduceMotion {
                        proxy.scrollTo(Self.topAnchor, anchor: .top)
                    } else {
                        withAnimation { proxy.scrollTo(Self.topAnchor, anchor: .top) }
                    }
                }
                .task(id: entries.count) {
                    staggerSettled = false
                    await FadeStagger.settle(afterRevealing: entries.count) {
                        staggerSettled = true
                    }
                }
                }
            }
        }
    }

    /// Load the selected player's history for this song/instrument.
    private func load() async {
        guard let accountId = session.selectedPlayer?.accountId else { return }
        let requested = requestKey
        lastRequest = requested
        state = .loading
        do {
            let payload = try await session.playerHistory(
                accountId: accountId, songId: song.songId, instrument: instrument
            )
            try Task.checkCancellation()
            guard requested == requestKey else { return }
            state = .loaded(payload)
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            if requested == requestKey {
                state = .failed(ServiceIssue(error))
            }
        }
    }
}

// MARK: - Row

/// One score-history entry: date, score, accuracy/FC and season, matching the
/// web's `LeaderboardEntry` row reused for history (label = formatted date).
struct PlayerHistoryRow: View {
    let entry: ScoreHistoryEntry
    let isHighScore: Bool

    private var dateText: String {
        guard let date = entry.displayDate else { return "\u{2014}" }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateText)
                    .font(.subheadline.weight(isHighScore ? .semibold : .regular))
                if let season = entry.season {
                    Text("Season \(season)")
                        .font(.caption2)
                        .foregroundStyle(BrandTokens.textSecondary)
                }
            }
            Spacer(minLength: 8)
            if entry.isFullCombo == true {
                Text("FC")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(BrandTokens.gold, in: Capsule())
                    .foregroundStyle(.black)
            }
            if let accuracy = entry.accuracy {
                Text(ScoreFormatting.accuracy(accuracy) + "%")
                    .font(.caption)
                    .foregroundStyle(BrandTokens.textSecondary)
                    .frame(minWidth: 44, alignment: .trailing)
            }
            Text(entry.newScore.formatted())
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(isHighScore ? BrandTokens.gold : BrandTokens.textPrimary)
                .frame(minWidth: 70, alignment: .trailing)
        }
        .accessibilityLabel(
            "\(dateText), score \(entry.newScore)"
                + (entry.isFullCombo == true ? ", full combo" : "")
                + (isHighScore ? ", personal best" : "")
        )
    }
}

/// Sort state compared as one value, so a mode or direction change scrolls to the top once.
struct PlayerHistorySortKey: Equatable {
    let mode: PlayerScoreSortMode
    let ascending: Bool
}
