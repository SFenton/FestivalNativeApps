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
            Text(instrument.label)
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
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
        .background(
            BrandTokens.cardBackground,
            in: RoundedRectangle(cornerRadius: 12)
        )
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
        if payload.isStale {
            FreshnessDisclosure(
                message: OfflineDisclosure.label(
                    .scores, publicationId: payload.publicationId
                ),
                symbol: "wifi.slash"
            )
        } else if payload.publicationId == nil {
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

/// Scalable score row shared by the native preview and the paginated Solo chart.
struct SongLeaderboardEntryRow: View {
    let entry: LeaderboardEntry
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var accuracyTextWidth: CGFloat = 80
    @ScaledMetric(relativeTo: .body) private var accuracyPillHeight: CGFloat = 24

    var body: some View {
        let rank = Text("#\(entry.rank.formatted())")
            .font(.body)
            .monospacedDigit()
            .foregroundStyle(BrandTokens.textSecondary)
        let name = Text(
            entry.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown User"
        )
        .font(.body)
        .fixedSize(horizontal: false, vertical: true)
        let score = Text(entry.score.formatted())
            .font(.body)
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        let valuesLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            HStack(spacing: 8) {
                rank
                name.frame(maxWidth: .infinity, alignment: .leading)
            }
            valuesLayout {
                score
                if let value = entry.accuracy {
                    let color: Result<ScoreAccuracyTint, Error> = Result {
                        try ScoreFormatting.accuracyTint(value)
                    }
                    switch color {
                    case let .failure(error):
                        Text("Accuracy unavailable: \(error.localizedDescription)")
                            .font(.body)
                            .foregroundStyle(BrandTokens.textPrimary)
                            .accessibilityIdentifier("fst.score.accuracy.\(entry.accountId)")
                    case let .success(tint):
                        let fullCombo = entry.isFullCombo == true
                        let percent = "\(ScoreFormatting.accuracy(value))%"
                        let spoken = fullCombo
                            ? "Full combo, accuracy \(percent)" : "Accuracy \(percent)"
                        accuracyBadge(
                            text: dynamicTypeSize.isAccessibilitySize
                                ? spoken : fullCombo ? "FC \(percent)" : percent,
                            spoken: spoken,
                            fill: fullCombo ? BrandTokens.cardBackground
                                : Color(
                                    .sRGB,
                                    red: Double(tint.red) / 255,
                                    green: Double(tint.green) / 255,
                                    blue: Double(tint.blue) / 255,
                                    opacity: 0.25
                                ),
                            fullCombo: fullCombo
                        )
                    }
                } else if entry.isFullCombo == true {
                    accuracyBadge(
                        text: dynamicTypeSize.isAccessibilitySize ? "Full combo" : "FC",
                        spoken: "Full combo; accuracy unavailable",
                        fill: BrandTokens.cardBackground, fullCombo: true
                    )
                } else if !dynamicTypeSize.isAccessibilitySize {
                    Color.clear
                        .frame(
                            width: accuracyTextWidth + 16,
                            height: accuracyPillHeight
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
    }

    /// Keep the compact and large-text accuracy states legible and independently spoken.
    ///
    /// - Parameters:
    ///   - text: Visible percentage with a full-combo prefix only when explicitly true.
    ///   - spoken: Expanded VoiceOver label that never infers a missing FC flag.
    ///   - fill: Opaque card for an FC, or graded 25%-opaque accuracy color otherwise.
    ///   - fullCombo: Whether to add the source's gold full-combo outline.
    /// - Returns: One scalable, accessible score-accuracy pill.
    private func accuracyBadge(
        text: String, spoken: String, fill: Color, fullCombo: Bool
    ) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(BrandTokens.textPrimary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
            .frame(
                width: dynamicTypeSize.isAccessibilitySize
                    ? nil : accuracyTextWidth + 16,
                height: dynamicTypeSize.isAccessibilitySize
                    ? nil : accuracyPillHeight
            )
            .background(fill, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if fullCombo {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(BrandTokens.gold, lineWidth: 2)
                }
            }
            .accessibilityLabel(spoken)
            .accessibilityIdentifier("fst.score.accuracy.\(entry.accountId)")
    }
}
