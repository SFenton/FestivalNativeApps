import Foundation

// MARK: - Presentation model

/// A notification flag's kind, mirroring the web's `NotificationFlagKind`
/// (`FortniteFestivalWeb/src/components/notifications/notificationText.ts`).
public enum NotificationFlagKind: String, Sendable, CaseIterable, Hashable {
    case improvement, firstPlay, newHighScore, fullCombo, rankUp, goldStars, starsUp, difficultyUp, progress

    /// The web's `notifications.flags.*` label (`en.json`).
    public var label: String {
        switch self {
        case .improvement: "Improvement"
        case .firstPlay: "First Play"
        case .newHighScore: "New High Score"
        case .fullCombo: "Full Combo"
        case .rankUp: "Rank Up"
        case .goldStars: "Gold Stars"
        case .starsUp: "Stars Up"
        case .difficultyUp: "Difficulty Up"
        case .progress: "Progress"
        }
    }

    /// Port of `flagKind(eventKind)`.
    ///
    /// - Parameter eventKind: Notification or coalesced sub-event kind.
    /// - Returns: The flag the web shows for that kind; `.improvement` when unknown.
    public static func forEventKind(_ eventKind: String) -> NotificationFlagKind {
        switch eventKind {
        case "player_first_score", "band_first_score": return .firstPlay
        case "player_score_pb", "band_score_pb", "band_combo_score_pb": return .newHighScore
        case "player_fc_achieved", "band_fc_achieved": return .fullCombo
        default: break
        }
        if eventKind.contains("rank_improved") { return .rankUp }
        switch eventKind {
        case "player_gold_stars_achieved", "band_gold_stars_achieved": return .goldStars
        case "player_stars_improved", "band_stars_improved": return .starsUp
        case "player_difficulty_bumped", "band_member_difficulty_bumped": return .difficultyUp
        case "player_total_score_improved", "player_fc_count_improved",
             "band_total_score_improved", "band_fc_count_improved": return .progress
        default: return .improvement
        }
    }
}

/// One instrument's flags in a row that touched several charts (web `NotificationFlagGroup`).
public struct NotificationFlagGroup: Sendable, Equatable, Identifiable {
    public let instrument: Instrument
    public let label: String
    public let flags: [NotificationFlagKind]

    public var id: Instrument { instrument }

    /// Spoken summary, as the web's `aria-label` (`"Lead: First Play, Full Combo"`).
    public var accessibilityLabel: String {
        "\(label): \(flags.map(\.label).joined(separator: ", "))"
    }
}

/// A run of message text; emphasized runs render bold (web `NotificationMessagePart`).
public struct NotificationMessagePart: Sendable, Equatable {
    public let text: String
    public let emphasis: Bool

    /// - Parameters:
    ///   - text: Run text.
    ///   - emphasis: Whether the run is bold.
    public init(_ text: String, emphasis: Bool = false) {
        self.text = text
        self.emphasis = emphasis
    }
}

/// The row's leading media rail (web `NotificationMedia`, player-scoped kinds only).
public enum NotificationMedia: Sendable, Equatable {
    /// Album art alone.
    case song(albumArt: String)
    /// Album art above a grid of every chart the row touched.
    case songInstrumentGrid(albumArt: String, instruments: [Instrument])
    /// One instrument icon (no art available, or a non-song row).
    case soloInstrument(Instrument)
}

/// One notification rendered for display, independent of the UI layer.
public struct AppNotification: Identifiable, Sendable, Equatable {
    public let id: String
    public let eventId: Int
    public let eventKind: String
    public let detectedAt: Date?
    public let title: String
    /// Plain message; statement-style rows separate clauses with blank lines.
    public let message: String
    /// `message` split into plain and bold runs.
    public let messageParts: [NotificationMessagePart]
    /// Unique flags across the row's events, in event priority order.
    public let flags: [NotificationFlagKind]
    /// Per-instrument flags for rows touching several charts; when non-empty the row
    /// shows these instead of `flags`.
    public let flagGroups: [NotificationFlagGroup]
    /// `"title. message"` (web `presentation.accessibilityLabel`).
    public let accessibilityLabel: String
    public let media: NotificationMedia
    public let songId: String?
    public let instrument: Instrument?
    public let destination: AppNotificationDestination?
}

/// Catalogue facts about a notification's song, resolved by the caller.
public struct NotificationSongInfo: Sendable, Equatable {
    public let title: String
    public let artist: String?
    public let albumArt: String?

    /// - Parameters:
    ///   - title: Catalogue title.
    ///   - artist: Catalogue artist.
    ///   - albumArt: Catalogue artwork path or URL.
    public init(title: String, artist: String? = nil, albumArt: String? = nil) {
        self.title = title
        self.artist = artist
        self.albumArt = albumArt
    }
}

// MARK: - Formatter

/// Port of the player-scoped part of the web's `formatNotificationPresentation`
/// (`notificationText.ts`) and the feed mapping in `useProfileNotificationsFeed.tsx`,
/// using the English copy in `FortniteFestivalWeb/src/i18n/en.json` verbatim.
///
/// Coalesced events, derived Full Combo / gold-star results, statement-style rows
/// (instrument aggregates, several rank updates, several charts), emphasis runs and
/// flags are ported. Band and combo copy is not: this app reads one player's feed.
public enum NotificationText {
    /// Compose a display row from one feed item.
    ///
    /// - Parameters:
    ///   - dto: Decoded notification.
    ///   - song: Catalogue facts for `dto.songId`, when it is in the catalogue.
    ///   - playerName: Selected player's display name, the last-resort title.
    ///   - locale: Number formatting locale (web `toLocaleString()`).
    /// - Returns: Display-ready title, message runs, flags and media.
    public static func format(
        _ dto: ImprovementNotificationDto, song: NotificationSongInfo?,
        playerName: String? = nil, locale: Locale = .current
    ) -> AppNotification {
        let instrument = dto.instrument.flatMap(Instrument.init(rawValue:))
        let presentation: NotificationTextResult
        let media: NotificationMedia
        if dto.eventKind == shopSongKind {
            let title = dto.payload?.songTitle ?? song?.title ?? dto.songId ?? "New Song"
            let artist = dto.payload?.artist ?? song?.artist?.nonEmptyTrimmed ?? "Unknown Artist"
            presentation = shopSongPresentation(songTitle: title, artist: artist)
            let art = song?.albumArt?.nonEmptyTrimmed ?? dto.payload?.albumArt
            media = art.map { .song(albumArt: $0) } ?? .soloInstrument(.lead)
        } else {
            let events = normalizedEvents(dto, instrument: instrument)
            let surface = surfaceInstruments(dto, events: events)
            let input = NotificationTextInput(
                dto: dto, instrument: instrument, songTitle: song?.title,
                title: song?.title ?? dto.songId ?? instrument?.label ?? playerName,
                events: events
            )
            presentation = NotificationTextEngine(locale: locale).present(input)
            let art = song?.albumArt?.nonEmptyTrimmed
            if let art, surface.count > 1 {
                media = .songInstrumentGrid(albumArt: art, instruments: surface)
            } else if let art {
                media = .song(albumArt: art)
            } else {
                media = .soloInstrument(instrument ?? .lead)
            }
        }
        return AppNotification(
            id: dto.notificationGuid, eventId: dto.eventId, eventKind: dto.eventKind,
            detectedAt: ISO8601Parsing.wholeSecondsDate(dto.detectedAt),
            title: presentation.title, message: presentation.message,
            messageParts: presentation.messageParts, flags: presentation.flags,
            flagGroups: presentation.flagGroups,
            accessibilityLabel: "\(presentation.title). \(presentation.message)",
            media: media, songId: dto.songId, instrument: instrument,
            destination: NotificationDestinationResolver.destination(for: dto)
        )
    }

    // MARK: - Shop song

    private static let shopSongKind = "service_new_shop_song"

    /// Port of `formatServiceNewShopSongPresentation`.
    private static func shopSongPresentation(songTitle: String, artist: String) -> NotificationTextResult {
        NotificationTextResult(
            title: "New Song · \(songTitle) - \(artist)",
            message: "\(songTitle) by \(artist) has been added to the Item Shop.",
            messageParts: [
                .init(songTitle, emphasis: true), .init(" by "),
                .init(artist, emphasis: true), .init(" has been added to the Item Shop."),
            ],
            flags: [], flagGroups: []
        )
    }

    // MARK: - Feed mapping

    /// Port of `normalizedNotificationEvents`: coalesced payload events (each falling back
    /// to the row's instrument), else the row itself.
    private static func normalizedEvents(
        _ dto: ImprovementNotificationDto, instrument: Instrument?
    ) -> [NotificationTextEvent] {
        let payloadEvents = (dto.payload?.coalescedEvents ?? []).compactMap { event -> NotificationTextEvent? in
            guard let kind = event.eventKind else { return nil }
            return NotificationTextEvent(
                eventKind: kind,
                instrument: event.instrument.flatMap(Instrument.init(rawValue:)) ?? instrument,
                metric: event.metric, oldNumeric: event.oldNumeric, newNumeric: event.newNumeric,
                oldRank: event.oldRank, newRank: event.newRank,
                oldLabel: event.oldLabel, newLabel: event.newLabel,
                state: NotificationScoreResult(
                    oldFullCombo: event.oldFullCombo, newFullCombo: event.newFullCombo,
                    oldStars: event.oldStars, newStars: event.newStars
                )
            )
        }
        if !payloadEvents.isEmpty { return payloadEvents }
        return [NotificationTextEvent(
            eventKind: dto.eventKind, instrument: instrument, metric: dto.metric,
            oldNumeric: dto.oldNumeric, newNumeric: dto.newNumeric,
            oldRank: dto.oldRank.map(Double.init), newRank: dto.newRank.map(Double.init),
            oldLabel: nil, newLabel: nil, state: NotificationScoreResult(payload: dto.payload)
        )]
    }

    /// Port of `notificationSurfaceInstruments`: every chart the row touched, in canonical order.
    private static func surfaceInstruments(
        _ dto: ImprovementNotificationDto, events: [NotificationTextEvent]
    ) -> [Instrument] {
        var present = Set((dto.payload?.coalescedInstruments ?? []).compactMap(Instrument.init(rawValue:)))
        present.formUnion(events.compactMap(\.instrument))
        if let instrument = dto.instrument.flatMap(Instrument.init(rawValue:)) { present.insert(instrument) }
        return Instrument.allCases.filter(present.contains)
    }
}

// MARK: - Engine types

/// Full Combo / star state attached to a score event or the row's payload.
struct NotificationScoreResult: Equatable {
    var oldFullCombo: Bool?
    var newFullCombo: Bool?
    var oldStars: Double?
    var newStars: Double?

    var hasResult: Bool { newFullCombo != nil || newStars != nil }

    init(oldFullCombo: Bool? = nil, newFullCombo: Bool? = nil, oldStars: Double? = nil, newStars: Double? = nil) {
        self.oldFullCombo = oldFullCombo
        self.newFullCombo = newFullCombo
        self.oldStars = oldStars
        self.newStars = newStars
    }

    init(payload: NotificationPayloadFields?) {
        self.init(
            oldFullCombo: payload?.oldFullCombo, newFullCombo: payload?.newFullCombo,
            oldStars: payload?.oldStars, newStars: payload?.newStars
        )
    }
}

/// One normalized event (web `NotificationTextEvent`, player fields only).
struct NotificationTextEvent: Equatable {
    var eventKind: String
    var instrument: Instrument?
    var metric: String?
    var oldNumeric: Double?
    var newNumeric: Double?
    var oldRank: Double?
    var newRank: Double?
    var oldLabel: String?
    var newLabel: String?
    var state: NotificationScoreResult

    var instrumentLabel: String? { instrument?.label }
}

/// The formatter input (web `NotificationTextInput`, player fields only).
struct NotificationTextInput {
    var eventKind: String
    var instrument: Instrument?
    var instrumentLabel: String?
    /// Web `scopeLabel`: the row's own instrument for a player feed, kept when a
    /// multi-chart clause rescopes `instrumentLabel`.
    var scopeLabel: String?
    var metric: String?
    var oldNumeric: Double?
    var newNumeric: Double?
    var oldRank: Double?
    var newRank: Double?
    var songTitle: String?
    var title: String?
    var payloadState: NotificationScoreResult
    var events: [NotificationTextEvent]

    init(dto: ImprovementNotificationDto, instrument: Instrument?, songTitle: String?, title: String?, events: [NotificationTextEvent]) {
        eventKind = dto.eventKind
        self.instrument = instrument
        instrumentLabel = instrument?.label
        scopeLabel = instrument?.label
        metric = dto.metric
        oldNumeric = dto.oldNumeric
        newNumeric = dto.newNumeric
        oldRank = dto.oldRank.map(Double.init)
        newRank = dto.newRank.map(Double.init)
        self.songTitle = songTitle
        self.title = title
        payloadState = NotificationScoreResult(payload: dto.payload)
        self.events = events
    }

    /// The bare `{ eventKind }` input the web's aggregate fallback formats with.
    init(bare eventKind: String) {
        self.eventKind = eventKind
        payloadState = NotificationScoreResult()
        events = []
    }
}

/// Display output before row metadata is attached.
struct NotificationTextResult: Equatable {
    var title: String
    var message: String
    var messageParts: [NotificationMessagePart]
    var flags: [NotificationFlagKind]
    var flagGroups: [NotificationFlagGroup]
}

/// A message clause and the terms to bold within it.
private struct NotificationClause {
    var text: String
    var emphasisTerms: [String]
}

/// Interpolation values for one event (web `buildValues`, player fields only).
private struct NotificationTextValues {
    var song: String
    var newScore: String
    var oldScore: String
    var oldRank: String
    var newRank: String
    var oldStars: String
    var newStars: String
    var oldDifficulty: String
    var newDifficulty: String
    var oldCount: String
    var newCount: String
    var instrument: String
    var scope: String
}

// MARK: - Engine

/// The ported `notificationText.ts` engine.
struct NotificationTextEngine {
    let locale: Locale

    /// Port of `formatNotificationPresentation` for non-shop rows.
    ///
    /// - Parameter input: Normalized row.
    /// - Returns: Title, message, emphasis runs, flags and flag groups.
    func present(_ input: NotificationTextInput) -> NotificationTextResult {
        let events = displayEvents(input)
        let title = self.title(input, events: events)
        let statementStyle = Self.isPlayerInstrumentAggregate(events)
            || Self.isMultiAggregateRank(events) || Self.isMultiInstrumentPlayerSong(events)
        let clauses = self.clauses(input, events: events).filter { !$0.text.isEmpty }
        let texts = clauses.map(\.text)
        let message = texts.isEmpty
            ? Copy.unknown
            : statementStyle ? texts.joined(separator: "\n\n") : Copy.sentence(texts)
        let parts = clauses.isEmpty
            ? [NotificationMessagePart(message)]
            : Self.emphasize(message, terms: clauses.flatMap(\.emphasisTerms))
        return NotificationTextResult(
            title: title, message: message, messageParts: parts,
            flags: Self.uniqueFlags(events.map(\.eventKind)),
            flagGroups: Self.flagGroups(events)
        )
    }

    // MARK: Events

    /// Port of `getDisplayEvents`: derive score results, drop redundant stars, sort by priority.
    func displayEvents(_ input: NotificationTextInput) -> [NotificationTextEvent] {
        let derived = Self.withDerivedScoreResultEvents(input, events: input.events)
        return Self.stableSorted(Self.removeRedundantStarEvents(derived))
    }

    private static func stableSorted(_ events: [NotificationTextEvent]) -> [NotificationTextEvent] {
        events.enumerated()
            .sorted { left, right in
                let lp = priority(left.element.eventKind), rp = priority(right.element.eventKind)
                return lp != rp ? lp < rp : left.offset < right.offset
            }
            .map(\.element)
    }

    private static func withDerivedScoreResultEvents(_ input: NotificationTextInput, events: [NotificationTextEvent]) -> [NotificationTextEvent] {
        var fullComboKeys = Set(events.filter { $0.eventKind == "player_fc_achieved" }
            .map { statusKey(input, $0) })
        var goldKeys = Set(events.filter { $0.eventKind == "player_gold_stars_achieved" }
            .map { statusKey(input, $0) })
        let multiInstrument = isMultiInstrumentPlayerSong(events)
        var derived: [NotificationTextEvent] = []
        for event in events where Kinds.scoreResult.contains(event.eventKind) {
            guard let state = scoreResultState(input, events: events, event: event, multiInstrument: multiInstrument)
            else { continue }
            let key = statusKey(input, event)
            if state.newFullCombo == true, !fullComboKeys.contains(key) {
                derived.append(derivedEvent(input, source: event, kind: "player_fc_achieved", metric: "full_combo", state: state))
                fullComboKeys.insert(key)
            }
            if let stars = state.newStars, stars >= 6, !goldKeys.contains(key) {
                derived.append(derivedEvent(input, source: event, kind: "player_gold_stars_achieved", metric: "stars", state: state))
                goldKeys.insert(key)
            }
        }
        return events + derived
    }

    private static func scoreResultState(
        _ input: NotificationTextInput, events: [NotificationTextEvent], event: NotificationTextEvent, multiInstrument: Bool
    ) -> NotificationScoreResult? {
        if event.state.hasResult { return event.state }
        if multiInstrument && !eventMatchesTopLevel(input, event) { return nil }
        guard topLevelPayloadBelongs(input, events: events, event: event) else { return nil }
        return input.payloadState.hasResult ? input.payloadState : nil
    }

    private static func topLevelPayloadBelongs(_ input: NotificationTextInput, events: [NotificationTextEvent], event: NotificationTextEvent) -> Bool {
        let scoreEvents = events.filter { Kinds.scoreResult.contains($0.eventKind) }
        if scoreEvents.count != 1 && !eventMatchesTopLevel(input, event) { return false }
        guard let eventInstrument = event.instrument, let inputInstrument = input.instrument else { return true }
        return eventInstrument == inputInstrument
    }

    private static func eventMatchesTopLevel(_ input: NotificationTextInput, _ event: NotificationTextEvent) -> Bool {
        guard event.eventKind == input.eventKind,
              let inputInstrument = input.instrument, let eventInstrument = event.instrument,
              inputInstrument == eventInstrument
        else { return false }
        return matches(input.metric, event.metric) && matches(input.oldNumeric, event.oldNumeric)
            && matches(input.newNumeric, event.newNumeric) && matches(input.oldRank, event.oldRank)
            && matches(input.newRank, event.newRank)
    }

    private static func matches<T: Equatable>(_ lhs: T?, _ rhs: T?) -> Bool {
        guard let lhs, let rhs else { return true }
        return lhs == rhs
    }

    private static func derivedEvent(
        _ input: NotificationTextInput, source: NotificationTextEvent, kind: String, metric: String, state: NotificationScoreResult
    ) -> NotificationTextEvent {
        NotificationTextEvent(
            eventKind: kind, instrument: source.instrument ?? input.instrument, metric: metric,
            oldNumeric: metric == "stars" ? state.oldStars : nil,
            newNumeric: metric == "stars" ? state.newStars : nil,
            oldRank: nil, newRank: nil, oldLabel: nil, newLabel: nil, state: NotificationScoreResult()
        )
    }

    private static func statusKey(_ input: NotificationTextInput, _ event: NotificationTextEvent) -> String {
        (event.instrument ?? input.instrument)?.rawValue ?? ""
    }

    private static func removeRedundantStarEvents(_ events: [NotificationTextEvent]) -> [NotificationTextEvent] {
        let goldKeys = Set(events.filter { $0.eventKind == "player_gold_stars_achieved" }
            .map { $0.instrument?.rawValue ?? "" })
        return events.filter {
            !($0.eventKind == "player_stars_improved" && goldKeys.contains($0.instrument?.rawValue ?? ""))
        }
    }

    // MARK: Classification

    static func isPlayerInstrumentAggregate(_ events: [NotificationTextEvent]) -> Bool {
        let aggregate = events.filter { Kinds.instrumentAggregate.contains($0.eventKind) }
        return aggregate.count > 1 && aggregate.count == events.count
            && aggregate.contains { Kinds.instrumentAggregateProgress.contains($0.eventKind) }
    }

    static func isMultiAggregateRank(_ events: [NotificationTextEvent]) -> Bool {
        events.filter { Copy.rankNames[$0.eventKind] != nil }.count > 1
    }

    static func isMultiInstrumentPlayerSong(_ events: [NotificationTextEvent]) -> Bool {
        Set(events.filter { Kinds.playerSong.contains($0.eventKind) }.compactMap(\.instrumentLabel)).count > 1
    }

    // MARK: Title

    private func title(_ input: NotificationTextInput, events: [NotificationTextEvent]) -> String {
        let baseTitle = input.songTitle ?? input.title
        let instrumentLabel = input.instrumentLabel?.nonEmptyTrimmed
        if let baseTitle, Self.isMultiInstrumentPlayerSong(events) { return baseTitle }
        if let baseTitle, let instrumentLabel,
           events.contains(where: { Kinds.playerSong.contains($0.eventKind) }) {
            return "\(baseTitle) · \(instrumentLabel)"
        }
        if Self.isPlayerInstrumentAggregate(events) {
            let scope = instrumentLabel ?? input.scopeLabel
            return scope.map { "\($0) · Improvements" } ?? "Instrument Updates"
        }
        let rankEvents = events.filter { Copy.rankNames[$0.eventKind] != nil }
        if rankEvents.count > 1 {
            let scope = instrumentLabel ?? input.scopeLabel
            return scope.map { "Rank Updates · \($0)" } ?? "Rank Updates"
        }
        if let rankEvent = rankEvents.first, let name = Copy.rankNames[rankEvent.eventKind] {
            return "\(name) Improved"
        }
        if let progress = events.lazy.compactMap({ Copy.progressTitles[$0.eventKind] }).first {
            return progress
        }
        return input.title ?? input.songTitle ?? "Notification"
    }

    // MARK: Clauses

    private func clauses(_ input: NotificationTextInput, events: [NotificationTextEvent]) -> [NotificationClause] {
        if Self.isPlayerInstrumentAggregate(events) { return instrumentAggregateClauses(events) }
        if Self.isMultiAggregateRank(events) { return rankUpdateClauses(events) }
        if Self.isMultiInstrumentPlayerSong(events) { return multiInstrumentSongClauses(input, events: events) }
        return events.enumerated().flatMap { eventClauses(input, $0.element, primary: $0.offset == 0) }
    }

    private func rankUpdateClauses(_ events: [NotificationTextEvent]) -> [NotificationClause] {
        events.compactMap { event in
            guard let rank = Copy.rankNames[event.eventKind] else { return nil }
            let oldRank = formatRank(event.oldRank), newRank = formatRank(event.newRank)
            return NotificationClause(
                text: "For \(rank), moved from \(oldRank) to \(newRank).",
                emphasisTerms: Self.filterEmphasis([rank, oldRank, newRank])
            )
        }
    }

    private func instrumentAggregateClauses(_ events: [NotificationTextEvent]) -> [NotificationClause] {
        var byKind: [String: NotificationTextEvent] = [:]
        for event in events { byKind[event.eventKind] = event }
        let clauses = [
            totalScoreAggregateClause(byKind),
            fullComboAggregateClause(byKind),
            aggregateRankClause(byKind["player_skill_rank_improved"], .skill),
            aggregateRankClause(byKind["player_weighted_rank_improved"], .weighted),
            aggregateRankClause(byKind["player_max_score_rank_improved"], .maxScore),
        ].compactMap { $0 }
        if !clauses.isEmpty { return clauses }
        return events.enumerated().flatMap {
            eventClauses(NotificationTextInput(bare: $0.element.eventKind), $0.element, primary: $0.offset == 0)
        }
    }

    private func totalScoreAggregateClause(_ byKind: [String: NotificationTextEvent]) -> NotificationClause? {
        let valueEvent = byKind["player_total_score_improved"]
        let rankEvent = byKind["player_total_score_rank_improved"]
        let newScore = formatNumber(valueEvent?.newNumeric, fallback: Copy.Fallback.score)
        let oldRank = formatRank(rankEvent?.oldRank), newRank = formatRank(rankEvent?.newRank)
        if valueEvent != nil, rankEvent != nil {
            return NotificationClause(
                text: "Your total score increased to \(newScore) points and your total score rank "
                    + "moved up from \(oldRank) to \(newRank).",
                emphasisTerms: Self.filterEmphasis([newScore, "total score rank", oldRank, newRank])
            )
        }
        if valueEvent != nil {
            return NotificationClause(
                text: "Your total score increased to \(newScore) points.",
                emphasisTerms: Self.filterEmphasis([newScore])
            )
        }
        return aggregateRankClause(rankEvent, .totalScore)
    }

    private func fullComboAggregateClause(_ byKind: [String: NotificationTextEvent]) -> NotificationClause? {
        let countEvent = byKind["player_fc_count_improved"]
        let rankEvent = byKind["player_fc_rate_rank_improved"]
        let newCount = formatNumber(countEvent?.newNumeric, fallback: Copy.Fallback.count)
        let oldRank = formatRank(rankEvent?.oldRank), newRank = formatRank(rankEvent?.newRank)
        if countEvent != nil, rankEvent != nil {
            return NotificationClause(
                text: "Your Full Combo count increased to \(newCount) and your Full Combo percentage "
                    + "rank moved up from \(oldRank) to \(newRank).",
                emphasisTerms: Self.filterEmphasis([newCount, "Full Combo percentage rank", oldRank, newRank])
            )
        }
        if countEvent != nil {
            return NotificationClause(
                text: "Your Full Combo count increased to \(newCount).",
                emphasisTerms: Self.filterEmphasis([newCount])
            )
        }
        return aggregateRankClause(rankEvent, .fullCombo)
    }

    /// `notifications.copy.instrumentAggregate.*Rank` statements and their bold rank names.
    private enum AggregateRank {
        case totalScore, fullCombo, skill, weighted, maxScore

        var subject: String {
            switch self {
            case .totalScore: "total score rank"
            case .fullCombo: "Full Combo percentage rank"
            case .skill: "adjusted percentile rank"
            case .weighted: "percentile rank, weighted by number of entries,"
            case .maxScore: "max score rank"
            }
        }

        var emphasis: String {
            self == .weighted ? "percentile rank, weighted by number of entries" : subject
        }
    }

    private func aggregateRankClause(_ event: NotificationTextEvent?, _ rank: AggregateRank) -> NotificationClause? {
        guard let event else { return nil }
        let oldRank = formatRank(event.oldRank), newRank = formatRank(event.newRank)
        return NotificationClause(
            text: "Your \(rank.subject) moved up from \(oldRank) to \(newRank).",
            emphasisTerms: Self.filterEmphasis([rank.emphasis, oldRank, newRank])
        )
    }

    private func multiInstrumentSongClauses(_ input: NotificationTextInput, events: [NotificationTextEvent]) -> [NotificationClause] {
        Self.groupedInstrumentEvents(events).map { group in
            var scoped = input
            scoped.instrumentLabel = group.label
            let details = group.events.flatMap { eventClauses(scoped, $0, primary: false) }
            let updates = Copy.fragment(details.map(\.text))
            return NotificationClause(
                text: "For \(group.label), \(updates).",
                emphasisTerms: Self.filterEmphasis([group.label] + details.flatMap(\.emphasisTerms))
            )
        }
    }

    private static func groupedInstrumentEvents(_ events: [NotificationTextEvent]) -> [(label: String, events: [NotificationTextEvent])] {
        var order: [String] = []
        var groups: [String: [NotificationTextEvent]] = [:]
        for event in events where Kinds.playerSong.contains(event.eventKind) {
            guard let label = event.instrumentLabel else { continue }
            if groups[label] == nil { order.append(label) }
            groups[label, default: []].append(event)
        }
        return order
            .map { (label: $0, events: stableSorted(groups[$0] ?? [])) }
            .enumerated()
            .sorted { left, right in
                let lo = labelOrder(left.element.label), ro = labelOrder(right.element.label)
                return lo != ro ? lo < ro : left.offset < right.offset
            }
            .map(\.element)
    }

    private static func labelOrder(_ label: String) -> Int {
        Instrument.allCases.firstIndex { $0.label == label } ?? 1000
    }

    private func eventClauses(_ input: NotificationTextInput, _ event: NotificationTextEvent, primary: Bool) -> [NotificationClause] {
        let values = buildValues(input, event)
        let text = primary ? Copy.primary(event.eventKind, values) : Copy.detail(event.eventKind, values)
        guard let text else { return [] }
        let clause = NotificationClause(text: text, emphasisTerms: emphasisTerms(event, values))
        if primary && event.eventKind == "player_first_score" {
            return [clause, NotificationClause(
                text: "started at \(values.newRank)", emphasisTerms: Self.filterEmphasis([values.newRank])
            )]
        }
        return [clause]
    }

    private func buildValues(_ input: NotificationTextInput, _ event: NotificationTextEvent) -> NotificationTextValues {
        NotificationTextValues(
            song: input.songTitle ?? input.title ?? Copy.Fallback.song,
            newScore: formatNumber(event.newNumeric, fallback: Copy.Fallback.score),
            oldScore: formatNumber(event.oldNumeric, fallback: Copy.Fallback.score),
            oldRank: formatRank(event.oldRank),
            newRank: formatRank(event.newRank),
            oldStars: formatNumber(event.oldNumeric, fallback: Copy.Fallback.stars),
            newStars: formatNumber(event.newNumeric, fallback: Copy.Fallback.stars),
            oldDifficulty: event.oldLabel ?? formatNumber(event.oldNumeric, fallback: Copy.Fallback.difficulty),
            newDifficulty: event.newLabel ?? formatNumber(event.newNumeric, fallback: Copy.Fallback.difficulty),
            oldCount: formatNumber(event.oldNumeric, fallback: Copy.Fallback.count),
            newCount: formatNumber(event.newNumeric, fallback: Copy.Fallback.count),
            instrument: event.instrumentLabel ?? input.instrumentLabel ?? Copy.Fallback.instrument,
            scope: input.scopeLabel ?? input.instrumentLabel ?? Copy.Fallback.rankings
        )
    }

    private func emphasisTerms(_ event: NotificationTextEvent, _ values: NotificationTextValues) -> [String] {
        var terms = [
            values.newScore, values.oldScore, values.oldRank, values.newRank,
            values.oldDifficulty, values.newDifficulty, values.oldCount, values.newCount,
            values.instrument, Copy.Fallback.combo, values.scope,
        ]
        if Kinds.playerSong.contains(event.eventKind) { terms.append(values.song) }
        switch event.eventKind {
        case "player_gold_stars_achieved": terms += ["Gold Stars", "gold stars"]
        case "player_fc_achieved": terms.append("Full Combo")
        case "player_stars_improved": terms.append("\(values.oldStars) to \(values.newStars) stars")
        default: break
        }
        return Self.filterEmphasis(terms)
    }

    // MARK: Emphasis

    /// Port of `filterEmphasisTerms`: trimmed, non-fallback, unique, longest first.
    static func filterEmphasis(_ terms: [String?]) -> [String] {
        var seen = Set<String>()
        let unique = terms.compactMap { $0?.nonEmptyTrimmed }
            .filter { !Copy.Fallback.all.contains($0) && seen.insert($0).inserted }
        return unique.enumerated()
            .sorted { $0.element.count != $1.element.count ? $0.element.count > $1.element.count : $0.offset < $1.offset }
            .map(\.element)
    }

    /// Port of `emphasizeText`: bold the first (longest) candidate starting at each
    /// position, scanning left to right, and merge adjacent runs of the same weight.
    ///
    /// - Parameters:
    ///   - text: Final message.
    ///   - terms: Candidate terms from every clause.
    /// - Returns: Plain and bold runs that concatenate back to `text`.
    static func emphasize(_ text: String, terms: [String]) -> [NotificationMessagePart] {
        let candidates = filterEmphasis(terms).filter { text.contains($0) }
        guard !candidates.isEmpty else { return [NotificationMessagePart(text)] }
        var parts: [NotificationMessagePart] = []
        func append(_ run: Substring, emphasis: Bool) {
            if let last = parts.last, last.emphasis == emphasis {
                parts[parts.count - 1] = NotificationMessagePart(last.text + run, emphasis: emphasis)
            } else {
                parts.append(NotificationMessagePart(String(run), emphasis: emphasis))
            }
        }
        var index = text.startIndex
        while index < text.endIndex {
            let rest = text[index...]
            if let term = candidates.first(where: { rest.hasPrefix($0) }) {
                let end = text.index(index, offsetBy: term.count)
                append(text[index..<end], emphasis: true)
                index = end
            } else {
                let next = text.index(after: index)
                append(text[index..<next], emphasis: false)
                index = next
            }
        }
        return parts
    }

    // MARK: Flags

    static func uniqueFlags(_ eventKinds: [String]) -> [NotificationFlagKind] {
        var seen = Set<NotificationFlagKind>()
        return eventKinds.map(NotificationFlagKind.forEventKind).filter { seen.insert($0).inserted }
    }

    static func flagGroups(_ events: [NotificationTextEvent]) -> [NotificationFlagGroup] {
        guard isMultiInstrumentPlayerSong(events) else { return [] }
        return groupedInstrumentEvents(events).compactMap { group in
            guard let instrument = group.events.lazy.compactMap(\.instrument).first
                ?? Instrument.allCases.first(where: { $0.label == group.label })
            else { return nil }
            let flags = uniqueFlags(group.events.map(\.eventKind))
            return flags.isEmpty ? nil : NotificationFlagGroup(instrument: instrument, label: group.label, flags: flags)
        }
    }

    // MARK: Values

    /// Web `toLocaleString()`: grouped, up to three fraction digits.
    func formatNumber(_ value: Double?, fallback: String) -> String {
        guard let value else { return fallback }
        return value.formatted(.number.precision(.fractionLength(0...3)).locale(locale))
    }

    /// `#1,234`, or "your new rank" when absent.
    func formatRank(_ rank: Double?) -> String {
        guard let rank else { return Copy.Fallback.rank }
        return "#" + formatNumber(rank, fallback: Copy.Fallback.rank)
    }

    private static func priority(_ eventKind: String) -> Int { Kinds.priority[eventKind] ?? 1000 }
}

// MARK: - Copy (en.json)

/// Player-scoped `notifications.*` copy from `FortniteFestivalWeb/src/i18n/en.json`.
private enum Copy {
    static let unknown = "New improvement detected."

    /// `notifications.values.*` fallbacks; none of them is ever bolded.
    enum Fallback {
        static let song = "this song"
        static let score = "a new score"
        static let rank = "your new rank"
        static let stars = "more"
        static let difficulty = "a higher difficulty"
        static let count = "more"
        static let instrument = "this instrument"
        static let combo = "this combo"
        static let rankings = "these rankings"
        static let all: Set<String> = [
            song, score, rank, stars, difficulty, instrument, combo, rankings,
        ]
    }

    static let rankNames: [String: String] = [
        "player_weighted_rank_improved": "Weighted Percentile Rank",
        "player_skill_rank_improved": "Adjusted Percentile Rank",
        "player_total_score_rank_improved": "Total Score Rank",
        "player_fc_rate_rank_improved": "Full Combo Rank",
        "player_max_score_rank_improved": "Max Score % Rank",
    ]

    static let progressTitles: [String: String] = [
        "player_total_score_improved": "Total Score Improved",
        "player_fc_count_improved": "Full Combo Count Improved",
    ]

    /// `notifications.copy.primary.*` for player event kinds.
    ///
    /// - Parameters:
    ///   - kind: Event kind.
    ///   - v: Interpolation values.
    /// - Returns: The sentence clause, or nil for a kind without primary copy.
    static func primary(_ kind: String, _ v: NotificationTextValues) -> String? {
        switch kind {
        case "player_first_score":
            "Your first \(v.instrument) play on \(v.song) scored \(v.newScore) points"
        case "player_score_pb":
            "You set a new personal best on \(v.instrument) for \(v.song) with \(v.newScore) points"
        case "player_song_rank_improved":
            "You climbed from \(v.oldRank) to \(v.newRank) on \(v.instrument) for \(v.song)"
        case "player_stars_improved":
            "You improved from \(v.oldStars) to \(v.newStars) stars on \(v.instrument) for \(v.song)"
        case "player_gold_stars_achieved":
            "You earned gold stars on \(v.instrument) for \(v.song)"
        case "player_fc_achieved":
            "You got a Full Combo on \(v.instrument) for \(v.song)"
        case "player_difficulty_bumped":
            "You improved your difficulty on \(v.instrument) for \(v.song) from "
                + "\(v.oldDifficulty) to \(v.newDifficulty)"
        case "player_weighted_rank_improved":
            "You moved up from \(v.oldRank) to \(v.newRank) in \(v.instrument) percentile rankings, "
                + "weighted by number of entries"
        case "player_skill_rank_improved":
            "You moved up from \(v.oldRank) to \(v.newRank) in \(v.instrument) adjusted percentile rankings"
        case "player_total_score_rank_improved":
            "You moved up from \(v.oldRank) to \(v.newRank) in \(v.instrument) total score rankings"
        case "player_fc_rate_rank_improved":
            "You moved up from \(v.oldRank) to \(v.newRank) in \(v.instrument) Full Combo rankings"
        case "player_max_score_rank_improved":
            "You moved up from \(v.oldRank) to \(v.newRank) in \(v.instrument) max score rankings"
        case "player_total_score_improved":
            "Your \(v.instrument) total score increased to \(v.newScore) points"
        case "player_fc_count_improved":
            "Your \(v.instrument) Full Combo count increased to \(v.newCount)"
        default:
            nil
        }
    }

    /// `notifications.copy.detail.*` for player song event kinds.
    ///
    /// - Parameters:
    ///   - kind: Event kind.
    ///   - v: Interpolation values.
    /// - Returns: The follow-on clause, or nil for a kind without detail copy.
    static func detail(_ kind: String, _ v: NotificationTextValues) -> String? {
        switch kind {
        case "player_first_score": "your first play scored \(v.newScore) points and started at \(v.newRank)"
        case "player_score_pb": "your play set a new personal best with \(v.newScore) points"
        case "player_song_rank_improved": "climbed from \(v.oldRank) to \(v.newRank)"
        case "player_stars_improved": "improved from \(v.oldStars) to \(v.newStars) stars"
        case "player_gold_stars_achieved": "earned gold stars"
        case "player_fc_achieved": "got a Full Combo"
        case "player_difficulty_bumped": "improved difficulty from \(v.oldDifficulty) to \(v.newDifficulty)"
        default: nil
        }
    }

    /// `notifications.copy.join.*`.
    static func sentence(_ clauses: [String]) -> String {
        switch clauses.count {
        case 1: "\(clauses[0])."
        case 2: "\(clauses[0]) and \(clauses[1])."
        default: "\(clauses.dropLast().joined(separator: ", ")), and \(clauses[clauses.count - 1])."
        }
    }

    /// `notifications.copy.joinFragment.*`.
    static func fragment(_ clauses: [String]) -> String {
        switch clauses.count {
        case 0: unknown
        case 1: clauses[0]
        case 2: "\(clauses[0]) and \(clauses[1])"
        default: "\(clauses.dropLast().joined(separator: ", ")), and \(clauses[clauses.count - 1])"
        }
    }
}

// MARK: - Event kinds

private enum Kinds {
    static let priority: [String: Int] = [
        "service_new_shop_song": 5, "player_first_score": 10, "player_score_pb": 20,
        "player_fc_achieved": 30, "player_gold_stars_achieved": 40, "player_stars_improved": 50,
        "player_song_rank_improved": 60, "player_difficulty_bumped": 70,
        "player_total_score_improved": 75, "player_fc_count_improved": 76,
        "player_total_score_rank_improved": 80, "player_skill_rank_improved": 90,
        "player_weighted_rank_improved": 100, "player_fc_rate_rank_improved": 110,
        "player_max_score_rank_improved": 120,
    ]

    static let scoreResult: Set<String> = ["player_first_score", "player_score_pb"]

    static let playerSong: Set<String> = [
        "player_first_score", "player_score_pb", "player_song_rank_improved", "player_stars_improved",
        "player_gold_stars_achieved", "player_fc_achieved", "player_difficulty_bumped",
    ]

    static let instrumentAggregateProgress: Set<String> = [
        "player_total_score_improved", "player_fc_count_improved",
    ]

    static let instrumentAggregate: Set<String> = [
        "player_total_score_improved", "player_total_score_rank_improved", "player_fc_count_improved",
        "player_fc_rate_rank_improved", "player_skill_rank_improved", "player_weighted_rank_improved",
        "player_max_score_rank_improved",
    ]
}

private extension String {
    /// Trimmed text, or nil when only whitespace.
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
