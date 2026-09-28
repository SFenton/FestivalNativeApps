package com.festivalscoretracker.android.core.firstrun

import java.time.Instant

// region Gate context

/**
 * Runtime facts a slide gate may depend on (web `FirstRunGateContext`, `firstRun/types.ts`).
 *
 * @property hasPlayer A player profile is selected.
 * @property shopHighlightEnabled Item Shop highlighting is active (Shop visible, highlighting on).
 * @property experimentalRanksEnabled Experimental leaderboard ranks are on.
 * @property ready When false nothing shows: dependent facts are still resolving.
 * @property alwaysShow Bypass seen-state (debug force) while still respecting gates.
 */
data class FirstRunGateContext(
    val hasPlayer: Boolean = false,
    val shopHighlightEnabled: Boolean = false,
    val experimentalRanksEnabled: Boolean = false,
    val ready: Boolean = true,
    val alwaysShow: Boolean = false,
)

/** A named slide gate (an enum rather than a lambda so slides stay comparable data). */
enum class FirstRunGate {
    /** Always eligible. */
    Always,

    /** Only with a selected player. */
    HasPlayer,

    /** Only while Shop highlighting is active. */
    ShopHighlightEnabled,

    /** Only while experimental ranks are on. */
    ExperimentalRanksEnabled,
    ;

    /**
     * Evaluate the gate.
     *
     * @param context Runtime facts.
     * @return Whether a slide using this gate may show.
     */
    fun passes(context: FirstRunGateContext): Boolean = when (this) {
        Always -> true
        HasPlayer -> context.hasPlayer
        ShopHighlightEnabled -> context.shopHighlightEnabled
        ExperimentalRanksEnabled -> context.experimentalRanksEnabled
    }
}

// endregion

// region Slide

/**
 * One slide definition (web `FirstRunSlideDef` without `render`; the UI maps [id] to a demo).
 *
 * @property id Stable web slide ID, e.g. `songs-song-list`.
 * @property version Replay-contract version; bumped only when dismissed users should see it again.
 * @property title Title Case title.
 * @property description Sentence-case description.
 * @property contentKey Overrides the hashed text so copy variants share one seen record.
 * @property gate Eligibility predicate.
 */
data class FirstRunSlide(
    val id: String,
    val version: Int,
    val title: String,
    val description: String,
    val contentKey: String? = null,
    val gate: FirstRunGate = FirstRunGate.Always,
) {
    /** Text hashed to detect copy changes: `contentKey ?: title + description`. */
    val hashedContent: String get() = contentKey ?: (title + description)
}

// endregion

// region Hashing and records

/** The web's djb2 `contentHash`, bit for bit. */
object FirstRunHashing {
    /**
     * Hash UTF-16 code units exactly like JavaScript's `charCodeAt` loop with
     * 32-bit wraparound, returned as unsigned lowercase hex.
     *
     * @param text Slide content.
     * @return Lowercase hex digest.
     */
    fun contentHash(text: String): String {
        var hash = 5381
        for (unit in text) hash = (hash shl 5) + hash + unit.code
        return Integer.toUnsignedString(hash, 16)
    }
}

/**
 * Evidence that a slide was shown (web `FirstRunSeenRecord`).
 *
 * @property version Slide version when shown.
 * @property hash Content hash when shown.
 * @property seenAt When it was marked seen.
 */
data class FirstRunSeenRecord(val version: Int, val hash: String, val seenAt: Instant) {
    /** Whether the record has a shape [FirstRunSlideEvaluator.seenRecord] could have written. */
    val isValid: Boolean get() = version >= 0 && hash.length in 1..32
}

// endregion

// region Evaluator

/** Pure unseen/eligibility rules (web `isSlideUnseen`, `getUnseenSlides`, `getAllSlides`). */
object FirstRunSlideEvaluator {
    /**
     * Unseen: no record, a strictly higher slide version, or changed content.
     *
     * @param slide Slide.
     * @param seen Seen-state.
     * @return True when the slide should show.
     */
    fun isUnseen(slide: FirstRunSlide, seen: Map<String, FirstRunSeenRecord>): Boolean {
        val record = seen[slide.id] ?: return true
        if (slide.version > record.version) return true
        return FirstRunHashing.contentHash(slide.hashedContent) != record.hash
    }

    /**
     * Gate-passing unseen slides in catalogue order (every gate-passing one
     * under `alwaysShow`); none until `ready`.
     *
     * @param slides A page's catalogue.
     * @param context Runtime facts.
     * @param seen Seen-state.
     * @return Slides to show.
     */
    fun unseenSlides(slides: List<FirstRunSlide>, context: FirstRunGateContext, seen: Map<String, FirstRunSeenRecord>): List<FirstRunSlide> {
        if (!context.ready) return emptyList()
        val passing = gatePassingSlides(slides, context)
        return if (context.alwaysShow) passing else passing.filter { isUnseen(it, seen) }
    }

    /**
     * Every slide whose gate passes, ignoring seen-state.
     *
     * @param slides A page's catalogue.
     * @param context Runtime facts.
     * @return Gate-passing slides.
     */
    fun gatePassingSlides(slides: List<FirstRunSlide>, context: FirstRunGateContext): List<FirstRunSlide> =
        slides.filter { it.gate.passes(context) }

    /**
     * Every slide, ignoring gates and seen-state (Settings replay, web `getAllSlides`).
     *
     * @param slides A page's catalogue.
     * @return The same slides.
     */
    fun allSlides(slides: List<FirstRunSlide>): List<FirstRunSlide> = slides.toList()

    /**
     * The record to persist once a slide was shown.
     *
     * @param slide Slide.
     * @param now Timestamp.
     * @return Record with the current version and hash.
     */
    fun seenRecord(slide: FirstRunSlide, now: Instant): FirstRunSeenRecord =
        FirstRunSeenRecord(slide.version, FirstRunHashing.contentHash(slide.hashedContent), now)
}

// endregion

// region Debug mode

/** First-run behaviour for this launch. */
enum class FirstRunMode {
    /** Real seen-state behaviour (release default, `on`). */
    Normal,

    /** Never show automatically (debug default so automation is not blocked; replay still works). */
    Off,

    /** Show every gate-passing slide on every page visit (`force`). */
    Force,
    ;

    companion object {
        /**
         * Resolve `FST_DEBUG_FIRST_RUN` (`off|on|force`); unset is [Off] in debug builds.
         *
         * @param raw Extra value, or null.
         * @param debugBuild Whether this is a debug build (release always uses [Normal]).
         * @return Mode.
         */
        fun parse(raw: String?, debugBuild: Boolean): FirstRunMode {
            if (!debugBuild) return Normal
            return when (raw?.trim()?.lowercase()) {
                "force" -> Force
                "on" -> Normal
                else -> Off
            }
        }
    }
}

// endregion
