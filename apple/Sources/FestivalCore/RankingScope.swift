import Foundation

// MARK: - RankingCombo

/// A within-group multi-instrument ranking board (web `RankingScope` `kind: 'combo'`), e.g.
/// Lead + Bass + Drums + Vocals, read from `/api/rankings/combo?combo=`.
///
/// Only the OG band (Lead, Bass, Drums, Vocals) and Pro Strings (Pro Lead, Pro Bass)
/// families have combo boards; the service answers 404 for a cross-group combo.
public struct RankingCombo: Hashable, Sendable, Identifiable {
    /// The service's hex bitmask (``RivalCombo/comboId(for:)``), e.g. `"0f"`.
    public let comboId: String
    /// The combo's instruments, in canonical (`Instrument.allCases`) order.
    public let instruments: [Instrument]

    public var id: String { comboId }

    /// Build a combo from two or more instruments of one family.
    ///
    /// - Parameter instruments: The instruments to combine, in any order.
    /// - Returns: Nil for fewer than two instruments or a cross-group selection.
    public init?(instruments: [Instrument]) {
        let set = Set(instruments)
        guard set.count >= 2,
              let family = RankingScope.families.first(where: { $0.supportsCombo && $0.instruments.isSuperset(of: set) })
        else { return nil }
        let ordered = Instrument.allCases.filter { set.contains($0) && family.instruments.contains($0) }
        self.instruments = ordered
        comboId = RivalCombo.comboId(for: ordered)
    }

    /// Instrument names joined with " + " (web `rankingScopeLabel`), e.g. "Lead + Bass".
    public var label: String {
        instruments.map(\.label).joined(separator: " + ")
    }
}

// MARK: - RankingScope

/// One leaderboard on Compete: a single instrument's board or a within-group combo board
/// (web `utils/rankingScopes.ts` `RankingScope`).
public enum RankingScope: Hashable, Sendable, Identifiable {
    case instrument(Instrument)
    case combo(RankingCombo)

    /// Stable key (web `scopeKey`): the instrument's raw value or the combo's hex id.
    public var id: String {
        switch self {
        case let .instrument(instrument): instrument.rawValue
        case let .combo(combo): combo.comboId
        }
    }

    /// The scope's instruments, in canonical order.
    public var instruments: [Instrument] {
        switch self {
        case let .instrument(instrument): [instrument]
        case let .combo(combo): combo.instruments
        }
    }

    /// User-facing name (web `rankingScopeLabel`): "Lead", or "Lead + Bass" for a combo.
    public var label: String {
        switch self {
        case let .instrument(instrument): instrument.label
        case let .combo(combo): combo.label
        }
    }

    /// One instrument family of the web's `SCOPE_FAMILIES`.
    struct Family {
        let instruments: Set<Instrument>
        let supportsCombo: Bool
    }

    /// The web's `SCOPE_FAMILIES`, in page order: the OG band and Pro Strings support
    /// combos; the peripherals (Karaoke, Pro Cymbals, Pro Drums) do not.
    static let families: [Family] = [
        Family(instruments: [.lead, .bass, .drums, .vocals], supportsCombo: true),
        Family(instruments: [.proLead, .proBass], supportsCombo: true),
        Family(instruments: [.karaoke, .proCymbals, .proDrums], supportsCombo: false),
    ]

    /// The leaderboards Compete shows for the Settings-visible instruments (web
    /// `resolveSupportedRankingScopes`): per family, its combo first when two or more of
    /// its instruments are visible and the family supports combos, then each instrument.
    ///
    /// - Parameter visible: Settings-visible instruments.
    /// - Returns: Scopes in page order.
    public static func supported(visible: [Instrument]) -> [RankingScope] {
        let selected = Set(visible)
        return families.flatMap { family -> [RankingScope] in
            let picks = Instrument.allCases.filter { selected.contains($0) && family.instruments.contains($0) }
            let singles = picks.map(RankingScope.instrument)
            guard family.supportsCombo, let combo = RankingCombo(instruments: picks) else { return singles }
            return [.combo(combo)] + singles
        }
    }
}
