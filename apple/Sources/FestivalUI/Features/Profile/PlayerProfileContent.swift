import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - PlayerProfileContent

/// Loading, syncing, error and available states for one player-profile read.
private enum PlayerProfilePhase {
    case loading
    case syncing
    case available(PlayerProfilePayload)
    case failed(String)
}

/// Shared body for the pushed `/player/:accountId` route (`PlayerProfileScreen`) and
/// the Statistics tab root for the selected player (`StatisticsScreen`) — the web
/// renders both from the same `PlayerPage` component (`App.tsx:95-105`).
///
/// Only the keyless, side-effect-free `GET /api/player/{accountId}` compact-score
/// read is used (`FestivalSession.viewPlayer(accountId:)`). Per-instrument global
/// ranks, the percentile table and the rank-history chart all require the
/// player-stats GET, which `.agents/controls/profile-selection.md` documents as
/// **not** unconditionally read-only (it can compute and store missing tiers), so
/// this screen never calls it; those sections are left out rather than faked.
struct PlayerProfileContent: View {
    let session: FestivalSession
    let accountId: String
    let routeDisplayName: String?

    @State private var phase = PlayerProfilePhase.loading
    @State private var retryRevision = 0
    @State private var switchPending = false
    @State private var deselectPending = false
    @State private var actionError: String?
    @AppStorage("fst.settings.showLead") private var showLead = true
    @AppStorage("fst.settings.showBass") private var showBass = true
    @AppStorage("fst.settings.showDrums") private var showDrums = true
    @AppStorage("fst.settings.showVocals") private var showVocals = true
    @AppStorage("fst.settings.showProLead") private var showProLead = true
    @AppStorage("fst.settings.showProBass") private var showProBass = true
    @AppStorage("fst.settings.showKaraoke") private var showKaraoke = true
    @AppStorage("fst.settings.showProCymbals") private var showProCymbals = true
    @AppStorage("fst.settings.showProDrums") private var showProDrums = true

    private struct LoadKey: Hashable {
        let accountId: String
        let retry: Int
        let publicationRevision: Int
    }

    /// Create the shared player-profile content.
    ///
    /// - Parameters:
    ///   - session: Shared app session (client, selected profile, publication).
    ///   - accountId: Public account being viewed (may or may not be selected).
    ///   - routeDisplayName: Name known before the response arrives, if any.
    init(session: FestivalSession, accountId: String, routeDisplayName: String?) {
        self.session = session
        self.accountId = accountId
        self.routeDisplayName = routeDisplayName
    }

    /// Settings-visible solo charts, matching the Songs tab's own policy.
    private var visibleInstruments: [Instrument] {
        let preferences: [(Instrument, Bool)] = [
            (.lead, showLead), (.bass, showBass), (.drums, showDrums),
            (.vocals, showVocals), (.proLead, showProLead), (.proBass, showProBass),
            (.karaoke, showKaraoke), (.proCymbals, showProCymbals),
            (.proDrums, showProDrums),
        ]
        return preferences.compactMap { $0.1 ? $0.0 : nil }
    }

    private var isSelected: Bool { session.selectedPlayer?.accountId == accountId }

    private var displayName: String {
        if case let .available(payload) = phase, let name = payload.profile.displayName {
            return name
        }
        return routeDisplayName ?? accountId
    }

    var body: some View {
        content
            .navigationTitle(displayName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .task(id: LoadKey(
                accountId: accountId, retry: retryRevision,
                publicationRevision: session.publicationRevision
            )) {
                await load()
            }
            .confirmationDialog(
                "Switch selected profile?", isPresented: $switchPending,
                titleVisibility: .visible
            ) {
                Button("Switch Profile", role: .destructive) { select() }
            } message: {
                Text("Scores and profile-dependent pages will update to \(displayName).")
            }
            .confirmationDialog(
                "Deselect profile?", isPresented: $deselectPending,
                titleVisibility: .visible
            ) {
                Button("Deselect Profile", role: .destructive) { session.deselectPlayer() }
            } message: {
                Text("Scores and profile-only content will be hidden; app Settings stay saved.")
            }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            ProgressView("Loading Profile")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("fst.player.loading")
        case .syncing:
            ServiceUnavailableView(
                title: "Scores Are Syncing",
                message: "\(displayName)'s public scores are still syncing. Try again shortly.",
                retry: { retryRevision += 1 }
            )
            .accessibilityIdentifier("fst.player.syncing")
        case let .failed(message):
            ServiceUnavailableView(
                title: "Profile Unavailable", message: message,
                retry: { retryRevision += 1 }
            )
            .accessibilityIdentifier("fst.player.error")
        case let .available(payload):
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(payload)
                    overallSection(payload)
                    ForEach(visibleInstruments) { instrument in
                        instrumentSection(payload, instrument: instrument)
                    }
                    bandsLink
                }
                .padding(16)
            }
            .accessibilityIdentifier("fst.player.available")
        }
    }

    // MARK: Header

    @ViewBuilder
    private func header(_ payload: PlayerProfilePayload) -> some View {
        FestivalGlassSection {
            HStack(spacing: 12) {
                ProfileAvatar(name: displayName, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.title3.bold())
                        .foregroundStyle(BrandTokens.textPrimary)
                        .accessibilityIdentifier("fst.player.name")
                    Text(isSelected ? "This Is Me" : "Public Profile")
                        .font(.subheadline)
                        .foregroundStyle(isSelected ? BrandTokens.accentBlue : BrandTokens.textSecondary)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(BrandTokens.accentBlue)
                        .accessibilityHidden(true)
                }
            }
            identityAction(payload)
            if let actionError {
                Text(actionError)
                    .font(.footnote)
                    .foregroundStyle(BrandTokens.gold)
                    .accessibilityIdentifier("fst.player.action-error")
            }
        }
    }

    /// Select/switch when viewing someone else, or deselect when this is "me".
    ///
    /// - Parameter payload: Current validated read backing this action.
    @ViewBuilder
    private func identityAction(_ payload: PlayerProfilePayload) -> some View {
        if isSelected {
            Button("Deselect Profile", role: .destructive) { deselectPending = true }
                .buttonStyle(.bordered)
                .tint(BrandTokens.textPrimary)
                .accessibilityIdentifier("fst.player.deselect")
        } else if payload.publicationId == nil {
            Text("These scores have no verified publication. Selection is paused.")
                .font(.footnote)
                .foregroundStyle(BrandTokens.gold)
                .accessibilityIdentifier("fst.player.unverified")
        } else if payload.publicationId != session.publicationId {
            Text("Published scores changed. Reload this page before selecting.")
                .font(.footnote)
                .foregroundStyle(BrandTokens.gold)
                .accessibilityIdentifier("fst.player.preview-changed")
        } else {
            Button(session.selectedPlayer == nil ? "Select Profile" : "Switch To This Profile") {
                if session.selectedPlayer == nil {
                    select()
                } else {
                    switchPending = true
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(BrandTokens.accentBlue)
            .accessibilityIdentifier("fst.player.select")
        }
    }

    /// Promote the current viewed, response-proven read to the selected profile.
    private func select() {
        guard case let .available(payload) = phase else { return }
        let result = PlayerSearchResult(accountId: payload.profile.accountId, displayName: displayName)
        do {
            try session.selectPlayer(result, from: payload)
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: Overview

    @ViewBuilder
    private func overallSection(_ payload: PlayerProfilePayload) -> some View {
        let stats = payload.profile.overallStats(visibleInstruments: Set(visibleInstruments))
        FestivalGlassSection("Overview") {
            statGrid(items: [
                ("Songs Played", "\(stats.songsPlayed)", nil),
                (
                    "Full Combos",
                    stats.fullComboCount == 0 ? "0" : "\(stats.fullComboCount) (\(percentText(stats.fullComboPercent))%)",
                    nil
                ),
                ("Gold Stars", "\(stats.goldStarCount)", BrandTokens.gold),
                ("Avg Accuracy", accuracyText(stats.averageAccuracy), nil),
                ("Best Rank", stats.bestRank.map { "#\($0)" } ?? "—", nil),
            ])
        }
        .accessibilityIdentifier("fst.player.overview")
    }

    // MARK: Per-instrument

    @ViewBuilder
    private func instrumentSection(_ payload: PlayerProfilePayload, instrument: Instrument) -> some View {
        let stats = payload.profile.instrumentStats(instrument)
        FestivalGlassSection {
            HStack(spacing: 8) {
                InstrumentIcon(instrument, size: 22)
                Text(instrument.label)
                    .font(.headline)
                    .foregroundStyle(BrandTokens.textPrimary)
            }
            if stats.songsPlayed == 0 {
                FestivalFootnote("No \(instrument.label) scores recorded yet.")
                    .accessibilityIdentifier("fst.player.instrument-empty.\(instrument.rawValue)")
            } else {
                statGrid(items: [
                    ("Songs Played", "\(stats.songsPlayed)", nil),
                    (
                        "Full Combos",
                        stats.fullComboCount == 0 ? "0" : "\(stats.fullComboCount) (\(percentText(stats.fullComboPercent))%)",
                        stats.fullComboCount > 0 ? BrandTokens.gold : nil
                    ),
                    ("Gold Stars", "\(stats.goldStarCount)", BrandTokens.gold),
                    ("5 Stars", "\(stats.fiveStarCount)", nil),
                    ("Avg Accuracy", accuracyText(stats.averageAccuracy), nil),
                    ("Best Rank", stats.bestRank.map { "#\($0)" } ?? "—", nil),
                ])
            }
        }
        .accessibilityIdentifier("fst.player.instrument.\(instrument.rawValue)")
    }

    // MARK: Bands

    private var bandsLink: some View {
        NavigationLink(
            value: AppRoute.playerBands(accountId: accountId, displayName: routeDisplayName ?? displayName)
        ) {
            HStack {
                Image(systemName: "person.3")
                    .accessibilityHidden(true)
                Text("View \(displayName)'s Bands")
                    .foregroundStyle(BrandTokens.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(BrandTokens.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
        }
        .accessibilityIdentifier("fst.player.bands-link")
    }

    // MARK: Formatting

    /// One decimal only when the percent is not a whole number, matching `ScoreFormatting`.
    private func percentText(_ value: Double) -> String {
        let fractionDigits = value == value.rounded() ? 0 : 1
        return value.formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    /// `PlayerScore.accuracy` already decodes into the same ten-thousandths-of-a-percent
    /// scale `ScoreFormatting.accuracy(_:)` expects (compact wire `acc` multiplied by
    /// 1,000; e.g. wire `979` becomes `979_000`, i.e. 97.9%) — no further rescale needed.
    private func accuracyText(_ playerProfileAccuracy: Double?) -> String {
        guard let playerProfileAccuracy else { return "—" }
        return "\(ScoreFormatting.accuracy(playerProfileAccuracy))%"
    }

    // MARK: Load

    /// Read the public profile without selecting or persisting it.
    private func load() async {
        phase = .loading
        do {
            let payload = try await session.viewPlayer(accountId: accountId)
            try Task.checkCancellation()
            phase = payload.state == .syncing ? .syncing : .available(payload)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }
}

/// A row of small, flat (non-glass) value/label tiles inside one glass section.
///
/// Kept flat per `.agents/design/apple/liquid-glass.md` ("never glass-on-glass").
private struct StatTile: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let tint: Color?
}

/// Lay out stat tiles as an adaptive grid, matching the web's `StatBox` grid.
private func statGrid(items: [(label: String, value: String, tint: Color?)]) -> some View {
    let tiles = items.map { StatTile(label: $0.label, value: $0.value, tint: $0.tint) }
    return LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8
    ) {
        ForEach(tiles) { tile in
            VStack(spacing: 2) {
                Text(tile.value)
                    .font(.title3.bold())
                    .foregroundStyle(tile.tint ?? BrandTokens.accentBlue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(tile.label)
                    .font(.caption2)
                    .foregroundStyle(BrandTokens.textSecondary)
                    .textCase(.uppercase)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }
}
