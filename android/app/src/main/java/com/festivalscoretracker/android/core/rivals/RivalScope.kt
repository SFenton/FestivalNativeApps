package com.festivalscoretracker.android.core.rivals

import com.festivalscoretracker.android.core.model.Instrument

// region Combos

/**
 * Cross-instrument combo scopes (web `comboUtils.ts` / `@festival/core` `combos.ts`):
 * lowercase hex bitmasks over the service instrument order ([Instrument] order),
 * plus the non-bitmask Pro Drums family token.
 */
object RivalCombo {
    /** The Pro Drums family token (`PRO_DRUMS_RIVAL_SCOPE`). */
    const val PRO_DRUMS_TOKEN = "pro_drums"

    /** Bitmask groups a combo may be drawn from: OG band (0x0f) and Pro Strings (0x30). */
    private val GROUP_MASKS = intArrayOf(0x0f, 0x30)

    private val PAD = listOf(Instrument.Lead, Instrument.Bass, Instrument.Drums, Instrument.Vocals)
    private val PRO_STRINGS = listOf(Instrument.ProLead, Instrument.ProBass)
    private val PRO_DRUMS_FAMILY = listOf(Instrument.ProCymbals, Instrument.ProDrums)

    /**
     * Bitmask of a set of charts.
     *
     * @param instruments Charts.
     * @return Mask with bit = service order index.
     */
    fun mask(instruments: Collection<Instrument>): Int = instruments.fold(0) { mask, instrument -> mask or (1 shl instrument.ordinal) }

    /**
     * Charts of a mask, in service order.
     *
     * @param mask Bitmask.
     * @return Charts.
     */
    fun fromMask(mask: Int): List<Instrument> = Instrument.entries.filter { mask and (1 shl it.ordinal) != 0 }

    /**
     * Hex combo ID (web `comboIdFromInstruments`): lowercase, at least two digits.
     *
     * @param instruments Charts.
     * @return ID such as `03`.
     */
    fun comboId(instruments: Collection<Instrument>): String = mask(instruments).toString(16).padStart(2, '0')

    /**
     * Whether a mask is a supported within-group combo (2+ charts from one group).
     *
     * @param mask Bitmask.
     * @return True for a combo the service computes.
     */
    fun isWithinGroup(mask: Int): Boolean = Integer.bitCount(mask) >= 2 && GROUP_MASKS.any { mask and it.inv() == 0 }

    /**
     * The single Settings-derived scope (web `deriveRivalScopeFromSettings`): the
     * Pro Drums family when exactly those two charts are visible, else a within-group combo.
     *
     * @param visible Settings-visible charts.
     * @return Token, or null when the visible set is not a supported combo.
     */
    fun deriveToken(visible: Collection<Instrument>): String? {
        val mask = mask(visible)
        if (mask == mask(PRO_DRUMS_FAMILY)) return PRO_DRUMS_TOKEN
        return if (isWithinGroup(mask)) comboId(fromMask(mask)) else null
    }

    /**
     * Every Settings-derived detail scope (web `deriveRivalScopesFromSettings`, used for
     * Find Rival): the pad combo, the Pro Strings combo and the Pro Drums family when
     * enabled, else the first visible chart.
     *
     * @param visible Settings-visible charts.
     * @return Scope tokens (empty with nothing visible).
     */
    fun deriveTokens(visible: Collection<Instrument>): List<String> {
        val scopes = buildList {
            PAD.filter { it in visible }.takeIf { it.size >= 2 }?.let { add(comboId(it)) }
            PRO_STRINGS.filter { it in visible }.takeIf { it.size >= 2 }?.let { add(comboId(it)) }
            if (visible.containsAll(PRO_DRUMS_FAMILY)) add(PRO_DRUMS_TOKEN)
        }
        if (scopes.isNotEmpty()) return scopes
        return Instrument.entries.firstOrNull { it in visible }?.let { listOf(it.wireId) } ?: emptyList()
    }

    /**
     * Charts named by a combo token.
     *
     * @param token [PRO_DRUMS_TOKEN] or a 1–4 digit hex ID over the nine charts.
     * @return Charts, or null for an invalid token.
     */
    fun instrumentsFor(token: String?): List<Instrument>? {
        if (token == PRO_DRUMS_TOKEN) return PRO_DRUMS_FAMILY
        if (token == null || token.length !in 1..4 || !token.all { it in '0'..'9' || it.lowercaseChar() in 'a'..'f' }) return null
        val mask = token.toInt(16)
        if (mask == 0 || mask >= 1 shl Instrument.entries.size) return null
        return fromMask(mask)
    }

    /**
     * Whether a token is safe as a scope path segment.
     *
     * @param token Candidate.
     * @return True for [PRO_DRUMS_TOKEN] or a valid hex ID.
     */
    fun isValidToken(token: String): Boolean = instrumentsFor(token) != null

    /**
     * Display label: web `rivals.proDrumsFamily`, else the joined chart names
     * (`comboScopeLabel`), else `rivals.combo`.
     *
     * @param token Combo token.
     * @return Label.
     */
    fun label(token: String): String = when {
        token == PRO_DRUMS_TOKEN -> RivalText.PRO_DRUMS_FAMILY
        else -> instrumentsFor(token)?.takeIf { isWithinGroup(mask(it)) }?.joinToString(" + ") { it.label } ?: RivalText.COMBINED
    }

    /**
     * Label for any scope token: a chart name or a combo label.
     *
     * @param token Chart wire ID or combo token.
     * @return Label.
     */
    fun scopeLabel(token: String): String = Instrument.fromWireId(token)?.label ?: label(token)
}

// endregion

// region Scope

/** Which Settings-derived scope a route names without explicit charts. */
enum class RivalSettingsScope {
    /** Every visible chart, intersected (web `category=common`). */
    Common,

    /** The Settings-derived combo (web `category=combo`). */
    Combo,

    /** Every Settings-derived detail scope (web `comboScope: 'settings'`, used by Find Rival). */
    All,
}

/**
 * The typed rival scope a route carries instead of navigation side-channel state
 * (web `location.state`): which list or detail endpoint answers it. Deep links and
 * restored back stacks therefore behave exactly like taps.
 */
sealed interface RivalScope {
    /**
     * Solo "shared songs" rivals. One chart is a per-instrument list; two or more is
     * Common Rivals (the intersection of each chart's list; details merge each chart).
     *
     * @property instruments Charts in service order, distinct.
     */
    data class Song(val instruments: List<Instrument>) : RivalScope {
        /** Whether this is the Common Rivals intersection. */
        val isCommon: Boolean get() = instruments.size > 1
    }

    /**
     * A global per-instrument leaderboard's neighbouring rivals.
     *
     * @property instrument Chart.
     * @property rankBy Metric.
     */
    data class Leaderboard(val instrument: Instrument, val rankBy: RivalRankMetric = RivalRankMetric.TotalScore) : RivalScope

    /**
     * A server-computed combo or Pro Drums family list.
     *
     * @property token Hex combo ID or [RivalCombo.PRO_DRUMS_TOKEN].
     */
    data class Combo(val token: String) : RivalScope {
        /** Constituent charts (empty for an invalid token). */
        val instruments: List<Instrument> get() = RivalCombo.instrumentsFor(token).orEmpty()
    }

    /**
     * A scope resolved against Settings-visible charts when the screen loads.
     *
     * @property kind Which Settings scope.
     */
    data class FromSettings(val kind: RivalSettingsScope) : RivalScope

    /** Compact route token (see [RivalScopes.fromToken]). */
    val routeToken: String
        get() = when (this) {
            is Song -> "song:" + instruments.joinToString(",") { it.wireId }
            is Leaderboard -> "leaderboard:${instrument.wireId}:${rankBy.wireId}"
            is Combo -> "combo:$token"
            is FromSettings -> "settings:" + kind.name.lowercase()
        }
}

/**
 * What a rival detail read needs: a leaderboard detail, or one or more song-scope
 * tokens merged client-side.
 */
sealed interface RivalDetailRequest {
    /**
     * `GET …/leaderboard-rivals/{instrument}/{rivalId}`.
     *
     * @property instrument Chart.
     * @property rankBy Metric.
     */
    data class Leaderboard(val instrument: Instrument, val rankBy: RivalRankMetric) : RivalDetailRequest

    /**
     * `GET …/rivals/{scope}/{rivalId}` per token, merged (web `fetchCombinedRivalDetail`).
     *
     * @property scopes Chart wire IDs or combo tokens, distinct, non-empty.
     */
    data class Scopes(val scopes: List<String>) : RivalDetailRequest
}

/** Scope construction, parsing and resolution. */
object RivalScopes {
    /**
     * A song scope normalized to service order without duplicates.
     *
     * @param instruments Charts in any order.
     * @return Scope.
     */
    fun song(instruments: Collection<Instrument>): RivalScope.Song =
        RivalScope.Song(Instrument.entries.filter { it in instruments })

    /**
     * Parse [RivalScope.routeToken]. Also accepts the Apple debug form `combo:<token>:<charts>`.
     *
     * @param token Token or null.
     * @return Scope, or null when absent or malformed.
     */
    fun fromToken(token: String?): RivalScope? {
        if (token.isNullOrEmpty()) return null
        val parts = token.split(':')
        return when (parts[0]) {
            "song" -> {
                if (parts.size != 2) return null
                val charts = parts[1].split(',').map { Instrument.fromWireId(it) ?: return null }
                song(charts).takeIf { it.instruments.isNotEmpty() }
            }
            "leaderboard" -> {
                if (parts.size != 3) return null
                val instrument = Instrument.fromWireId(parts[1]) ?: return null
                RivalScope.Leaderboard(instrument, RivalRankMetric.fromWireId(parts[2]) ?: return null)
            }
            "combo" -> parts.getOrNull(1)?.takeIf { parts.size <= 3 && RivalCombo.isValidToken(it) }?.let(RivalScope::Combo)
            "settings" -> RivalSettingsScope.entries
                .firstOrNull { parts.size == 2 && it.name.equals(parts[1], ignoreCase = true) }
                ?.let(RivalScope::FromSettings)
            else -> null
        }
    }

    /**
     * Resolve a list scope against Settings (web `AllRivalsPage` category handling).
     *
     * @param scope Route scope.
     * @param visible Settings-visible charts.
     * @return A concrete [RivalScope.Song], [RivalScope.Leaderboard] or [RivalScope.Combo],
     *   or null when Settings cannot supply one (an unidentifiable list).
     */
    fun resolveList(scope: RivalScope?, visible: Collection<Instrument>): RivalScope? = when (scope) {
        null -> null
        is RivalScope.Song -> scope.takeIf { it.instruments.isNotEmpty() }
        is RivalScope.Leaderboard -> scope
        is RivalScope.Combo -> scope.takeIf { RivalCombo.isValidToken(it.token) }
        is RivalScope.FromSettings -> when (scope.kind) {
            RivalSettingsScope.Common -> song(visible).takeIf { it.isCommon }
            RivalSettingsScope.Combo -> RivalCombo.deriveToken(visible)?.let(RivalScope::Combo)
            RivalSettingsScope.All -> null
        }
    }

    /**
     * Resolve the detail read for a route scope. A missing scope follows the web's
     * `resolveRivalCombos(null)`: the Settings combo, else the first visible chart,
     * else Lead.
     *
     * @param scope Route scope or null.
     * @param visible Settings-visible charts.
     * @return Request with at least one scope.
     */
    fun resolveDetail(scope: RivalScope?, visible: Collection<Instrument>): RivalDetailRequest {
        val fallback = listOf(
            RivalCombo.deriveToken(visible) ?: Instrument.entries.firstOrNull { it in visible }?.wireId ?: Instrument.Lead.wireId,
        )
        val scopes = when (scope) {
            is RivalScope.Leaderboard -> return RivalDetailRequest.Leaderboard(scope.instrument, scope.rankBy)
            is RivalScope.Song -> scope.instruments.map { it.wireId }
            is RivalScope.Combo -> listOf(scope.token).filter(RivalCombo::isValidToken)
            is RivalScope.FromSettings -> when (scope.kind) {
                RivalSettingsScope.Common -> song(visible).instruments.map { it.wireId }
                RivalSettingsScope.Combo -> fallback
                RivalSettingsScope.All -> RivalCombo.deriveTokens(visible)
            }
            null -> fallback
        }
        return RivalDetailRequest.Scopes(scopes.distinct().ifEmpty { fallback })
    }

    /**
     * Page title for a list scope (web `rivals.commonRivalsShort` / `instrumentRivalsShort`).
     *
     * @param scope Resolved or route scope.
     * @return Title.
     */
    fun listTitle(scope: RivalScope?): String = when (scope) {
        is RivalScope.Song -> if (scope.isCommon) RivalText.COMMON_RIVALS else RivalText.rivalsTitle(scope.instruments.firstOrNull()?.label ?: "")
        is RivalScope.Leaderboard -> RivalText.rivalsTitle(scope.instrument.label)
        is RivalScope.Combo -> RivalText.rivalsTitle(RivalCombo.label(scope.token))
        is RivalScope.FromSettings -> if (scope.kind == RivalSettingsScope.Common) RivalText.COMMON_RIVALS else RivalText.rivalsTitle(RivalText.COMBINED)
        null -> "Rivals"
    }

    /**
     * The single chart a list is about, for its header icon.
     *
     * @param scope Resolved scope.
     * @return Chart, or null for multi-chart scopes.
     */
    fun singleInstrument(scope: RivalScope?): Instrument? = when (scope) {
        is RivalScope.Song -> scope.instruments.singleOrNull()
        is RivalScope.Leaderboard -> scope.instrument
        else -> null
    }
}

// endregion
