import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - PlayerProfileTiles

/// The player profile's stat tiles, link rules and load sequence as pure values, shared by
/// the SwiftUI page (``PlayerProfileContent``) and the UIKit port so both draw the same
/// tiles, follow the same links and read the same endpoints in the same order.
///
/// Nothing here reads the environment: the page passes in the rules it owns (which links may
/// be drawn, who is selected) and gets tiles, decisions or finished reads back.
enum PlayerProfileTiles {
    // MARK: Overview

    /// The Global Statistics tiles (web `buildOverallSummaryItems`): Songs Played and Full
    /// Combos filter Songs, Best Rank opens its song; Gold Stars and Avg Accuracy are plain.
    ///
    /// - Parameters:
    ///   - stats: The overall aggregate.
    ///   - visible: Settings-visible charts.
    ///   - link: The page's rule for which links may be drawn (``tileLink(_:hasNavigator:isSelected:hasIdentity:)``).
    /// - Returns: Five tiles in display order.
    static func overall(
        _ stats: PlayerOverallStats, visible: Set<Instrument>, link: (PlayerStatLink?) -> PlayerStatLink?
    ) -> [StatTile] {
        [
            StatTile(
                id: "songs-played", label: "Songs Played", value: stats.songsPlayed.formatted(),
                link: link(PlayerStatLinks.overallSongsPlayed(visible: visible))
            ),
            StatTile(
                id: "full-combos", label: "Full Combos",
                value: fullComboText(count: stats.fullComboCount, percent: stats.fullComboPercent),
                tint: stats.fullComboPercent >= 100 ? BrandTokens.gold : nil,
                link: link(PlayerStatLinks.overallFullCombos(visible: visible))
            ),
            StatTile(
                id: "gold-stars", label: "Gold Stars", value: stats.goldStarCount.formatted(),
                tint: BrandTokens.gold
            ),
            StatTile(id: "avg-accuracy", label: "Avg Accuracy", value: accuracyText(stats.averageAccuracy)),
            StatTile(
                id: "best-rank", label: "Best Rank", value: rankText(stats.bestRank),
                link: link(PlayerStatLinks.overallBestRank(stats))
            ),
        ]
    }

    // MARK: Per instrument

    /// The web `buildInstrumentStatsItems` tiles before its rank cards, in its order:
    /// Songs Played and FCs (filter Songs), star counts (non-zero only; Songs stars filter
    /// plus Stars sort), Avg Accuracy, Avg Stars, Best Rank (song).
    ///
    /// - Parameters:
    ///   - profile: The validated profile read.
    ///   - stats: That instrument's aggregate.
    ///   - link: The page's rule for which links may be drawn.
    /// - Returns: Tiles; the card appends its global-rank tiles (``rank(_:instrument:link:)``).
    static func instrument(
        _ profile: PlayerProfileResponse, stats: PlayerInstrumentStats, link: (PlayerStatLink?) -> PlayerStatLink?
    ) -> [StatTile] {
        let instrument = stats.instrument
        let stars = profile.starBreakdown(instrument)
        var tiles = [
            StatTile(
                id: "songs-played", label: "Songs Played", value: stats.songsPlayed.formatted(),
                link: link(PlayerStatLinks.instrumentSongsPlayed(instrument))
            ),
        ]
        if stats.fullComboCount > 0 {
            tiles.append(StatTile(
                id: "full-combos", label: "Full Combos",
                value: fullComboText(count: stats.fullComboCount, percent: stats.fullComboPercent),
                tint: stats.fullComboPercent >= 100 ? BrandTokens.gold : nil,
                link: link(PlayerStatLinks.instrumentFullCombos(instrument))
            ))
        }
        tiles += stars.countCards.map { card in
            StatTile(
                id: "stars-\(card.stars)", label: card.label, value: card.count.formatted(),
                tint: card.stars == 6 ? BrandTokens.gold : nil,
                link: link(PlayerStatLinks.instrumentStars(instrument, starKey: card.stars))
            )
        }
        tiles += [
            StatTile(id: "avg-accuracy", label: "Avg Accuracy", value: accuracyText(stats.averageAccuracy)),
            StatTile(id: "avg-stars", label: "Avg Stars", value: stars.averageText, goldStars: stars.isAllGold),
            StatTile(
                id: "best-rank", label: "Best Rank", value: rankText(stats.bestRank),
                link: link(PlayerStatLinks.instrumentBestRank(stats))
            ),
        ]
        return tiles
    }

    /// Global Rank (links to the full Total Score rankings), Total Score and a rank-derived
    /// percentile; placeholders while loading and em dashes when unranked or failed, so the
    /// grid keeps its shape in every state.
    ///
    /// - Parameters:
    ///   - phase: The ranking read's state.
    ///   - instrument: Chart.
    ///   - link: The page's rule for which links may be drawn.
    /// - Returns: The three rank tiles.
    static func rank(
        _ phase: InstrumentStatsCard.Phase, instrument: Instrument, link: (PlayerStatLink?) -> PlayerStatLink?
    ) -> [StatTile] {
        switch phase {
        case .loading:
            return [
                StatTile(id: "global-rank", label: "Global Rank", value: "#0,000", isPlaceholder: true),
                StatTile(id: "total-score", label: "Total Score", value: "000,000,000", isPlaceholder: true),
                StatTile(id: "percentile", label: "Percentile", value: "Top 00%", isPlaceholder: true),
            ]
        case .unranked:
            return [
                StatTile(id: "global-rank", label: "Global Rank", value: "Unranked"),
                StatTile(id: "total-score", label: "Total Score", value: "\u{2014}"),
                StatTile(id: "percentile", label: "Percentile", value: "\u{2014}"),
            ]
        case .failed:
            return [
                StatTile(id: "global-rank", label: "Global Rank", value: "\u{2014}"),
                StatTile(id: "total-score", label: "Total Score", value: "\u{2014}"),
                StatTile(id: "percentile", label: "Percentile", value: "\u{2014}"),
            ]
        case let .available(ranking):
            let rank = ranking.entry.rank(for: .totalscore)
            let percentile = ranking.percentile(for: .totalscore)
            return [
                StatTile(
                    id: "global-rank", label: "Global Rank", value: "#\(rank.formatted())",
                    link: link(PlayerStatLinks.globalRank(instrument, rank: rank))
                ),
                StatTile(
                    id: "total-score", label: "Total Score",
                    value: RankingFormatting.wholeNumber(ranking.entry.ratingValue(for: .totalscore))
                ),
                // "Top N%" from rank/field size: Total Score has no Bayesian percentile on
                // the wire. Gold for a top-5% placement.
                StatTile(
                    id: "percentile", label: "Percentile",
                    value: percentile.map(RankingFormatting.percentile) ?? "\u{2014}",
                    tint: (percentile ?? 1) * 100 <= 5 ? BrandTokens.gold : nil
                ),
            ]
        }
    }

    /// The identifier phase suffix of a ranking read (`fst.player.global-rank.<instrument>.<phase>`).
    ///
    /// - Parameter phase: The ranking read's state.
    /// - Returns: `loading`, `unranked`, `available` or `failed`.
    static func rankPhaseIdentifier(_ phase: InstrumentStatsCard.Phase) -> String {
        switch phase {
        case .loading: "loading"
        case .unranked: "unranked"
        case .available: "available"
        case .failed: "failed"
        }
    }

    // MARK: Formatting

    /// One decimal only when the percent is not a whole number, matching `ScoreFormatting`.
    ///
    /// - Parameter value: A percentage.
    /// - Returns: The text without a percent sign.
    static func percentText(_ value: Double) -> String {
        let fractionDigits = value == value.rounded() ? 0 : 1
        return value.formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    /// Web FC value: the count alone at 0 or 100%, otherwise "count (pct%)".
    ///
    /// - Parameters:
    ///   - count: Full combos.
    ///   - percent: Share of played songs.
    /// - Returns: The tile value.
    static func fullComboText(count: Int, percent: Double) -> String {
        count == 0 || percent >= 100 ? count.formatted() : "\(count.formatted()) (\(percentText(percent))%)"
    }

    /// "#rank", or an em dash with no ranked score.
    ///
    /// - Parameter rank: A rank, if any.
    /// - Returns: The tile value.
    static func rankText(_ rank: Int?) -> String {
        rank.map { "#\($0.formatted())" } ?? "\u{2014}"
    }

    /// `PlayerScore.accuracy` already decodes into the ten-thousandths-of-a-percent scale
    /// `ScoreFormatting.accuracy(_:)` expects (wire `979` becomes `979_000`, i.e. 97.9%).
    ///
    /// - Parameter accuracy: Mean accuracy, if any.
    /// - Returns: For example "97.9%", or an em dash.
    static func accuracyText(_ accuracy: Double?) -> String {
        guard let accuracy else { return "\u{2014}" }
        return "\(ScoreFormatting.accuracy(accuracy))%"
    }

    // MARK: Links

    /// A tile's link as drawn: nil (a plain tile) without the root navigator, or for a
    /// Songs filter while selection is paused (it would filter someone else's scores).
    ///
    /// - Parameters:
    ///   - link: The web's target for the tile.
    ///   - hasNavigator: Whether the page can navigate at all.
    ///   - isSelected: Whether the shown account is the selected player.
    ///   - hasIdentity: Whether the read has proven a Select/Switch/Deselect action.
    /// - Returns: The link to attach, or nil.
    static func tileLink(
        _ link: PlayerStatLink?, hasNavigator: Bool, isSelected: Bool, hasIdentity: Bool
    ) -> PlayerStatLink? {
        guard let link, hasNavigator else { return nil }
        if link.requiresSelection, !isSelected, !hasIdentity { return nil }
        return link
    }

    /// What following a tapped tile does (web `withProfileSwitch`).
    enum LinkDecision: Equatable {
        /// Follow the link now.
        case navigate
        /// Select the viewed player, then follow the link if that worked.
        case selectThenNavigate
        /// Ask to switch profiles first, remembering the link.
        case confirmSwitch
        /// Do nothing (the link needs a selection that is paused).
        case ignore
    }

    /// Decide what a tapped tile does: select a viewed player first, confirming a switch,
    /// and while selection is paused open only links that do not need it.
    ///
    /// - Parameters:
    ///   - link: The tapped tile's link.
    ///   - isSelected: Whether the shown account is the selected player.
    ///   - identity: The page's proven identity action, if any.
    /// - Returns: What to do.
    static func decision(for link: PlayerStatLink, isSelected: Bool, identity: ProfileIdentityAction?) -> LinkDecision {
        if isSelected { return .navigate }
        switch identity {
        case .select: return .selectThenNavigate
        case .switchTo: return .confirmSwitch
        case .deselect: return .navigate
        case nil: return link.requiresSelection ? .ignore : .navigate
        }
    }

    // MARK: Identity

    /// Select, Switch or Deselect for the shown account; nil while paused.
    ///
    /// - Parameters:
    ///   - isSelected: Whether the shown account is the selected player.
    ///   - payloadPublicationId: Publication proven by the profile read.
    ///   - sessionPublicationId: Publication the session currently observes.
    ///   - hasSelectedPlayer: Whether any player is selected.
    /// - Returns: The proven action, or nil.
    static func identity(
        isSelected: Bool, payloadPublicationId: Int?, sessionPublicationId: Int?, hasSelectedPlayer: Bool
    ) -> ProfileIdentityAction? {
        if isSelected { return .deselect }
        guard let payloadPublicationId, payloadPublicationId == sessionPublicationId else { return nil }
        return hasSelectedPlayer ? .switchTo : .select
    }

    /// The identity action the page will offer, known from the session alone, so the toolbar
    /// has its final shape from the first frame of a push.
    ///
    /// - Parameters:
    ///   - isSelected: Whether the shown account is the selected player.
    ///   - hasSelectedPlayer: Whether any player is selected.
    /// - Returns: The planned action.
    static func plannedIdentity(isSelected: Bool, hasSelectedPlayer: Bool) -> ProfileIdentityAction {
        if isSelected { return .deselect }
        return hasSelectedPlayer ? .switchTo : .select
    }

    /// Whether to hold the identity button's place (disabled) instead of hiding it: while
    /// loading, and while selection is paused. A failed or syncing read offers none.
    ///
    /// - Parameter phase: The page's phase.
    /// - Returns: True when the placeholder shows.
    static func showsIdentityPlaceholder(_ phase: PlayerProfilePhase) -> Bool {
        switch phase {
        case .loading, .available: true
        case .syncing, .failed: false
        }
    }
}

// MARK: - Load

/// The player profile's read sequence, shared by both front ends.
@MainActor
enum PlayerProfileLoader {
    /// A finished profile read.
    struct Loaded {
        /// The raw validated read, or nil while the player's scores are still syncing.
        var payload: PlayerProfilePayload?
        /// Catalogue songs by ID (Filter Invalid Scores needs their maximums and tiers).
        var songsById: [String: Song]
        /// Each played instrument's ranking read; empty while syncing.
        var extras = ProfileExtrasLoader.Extras()
    }

    /// Read the public profile without selecting or persisting it, with the catalogue
    /// alongside, then (in parallel) every played visible instrument's ranking and rank
    /// history, so the page shows only once everything has settled (web `PlayerPage`
    /// `dataReady`). Pure GETs only; never the player-stats read.
    ///
    /// - Parameters:
    ///   - session: Shared app session.
    ///   - accountId: Viewed account.
    ///   - instruments: Settings-visible charts, in display order.
    /// - Returns: The finished read.
    /// - Throws: A service error, or `CancellationError`.
    static func load(session: FestivalSession, accountId: String, instruments: [Instrument]) async throws -> Loaded {
        async let catalogue = try? session.catalog()
        let payload = try await session.viewPlayer(accountId: accountId)
        var songsById: [String: Song] = [:]
        if let songs = await catalogue?.catalog.songs {
            songsById = Dictionary(songs.map { ($0.songId, $0) }, uniquingKeysWith: { first, _ in first })
        }
        try Task.checkCancellation()
        guard payload.state != .syncing else { return Loaded(payload: nil, songsById: songsById) }
        let played = instruments.filter { payload.profile.instrumentStats($0).songsPlayed > 0 }
        let extras = await ProfileExtrasLoader.load(session: session, accountId: accountId, instruments: played)
        try Task.checkCancellation()
        return Loaded(payload: payload, songsById: songsById, extras: extras)
    }
}

extension StatTile {
    /// Whether the tile draws its value in gold (the only tint tiles use).
    var isGold: Bool { tint == BrandTokens.gold }
}
