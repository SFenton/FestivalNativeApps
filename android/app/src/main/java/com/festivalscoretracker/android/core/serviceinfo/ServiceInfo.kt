package com.festivalscoretracker.android.core.serviceinfo

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.service.ServiceFreezeReason
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.util.Locale
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToLong
import kotlinx.serialization.Serializable

// region Wire model

/**
 * The subset of `GET /api/service-info` natives read (contract version 2; Apple `ServiceInfo`).
 *
 * Source: `FSTService/Api/HealthEndpoints.cs` `MapGet("/api/service-info")`. The response also
 * carries infrastructure detail (`postgresConnectionTarget`, `serviceInstance`, worker instance
 * IDs); this model deliberately has no fields for them, and the tolerant decoder skips them, so
 * they are never decoded, stored or logged. Every number is a [Double] so a server-side widening
 * never fails the whole read.
 *
 * @property contractVersion Response contract version.
 * @property phasePlan Ordered phase plan used to label the current phase.
 * @property lastCompletedUpdate The last scrape that reached publication.
 * @property currentUpdate The running (or last failed) update.
 * @property activeScrapeId Scrape ID of the active update.
 * @property publication Publication pointers and the public-read freeze.
 * @property workerStatus Scraper worker heartbeat summary.
 * @property nextScheduledUpdateAt Next scheduled update (not shown, like the web card).
 */
@Serializable
data class ServiceInfo(
    val contractVersion: Double? = null,
    val phasePlan: PhasePlan? = null,
    val lastCompletedUpdate: CompletedUpdate? = null,
    val currentUpdate: CurrentUpdate,
    val activeScrapeId: Double? = null,
    val publication: PublicationState? = null,
    val workerStatus: WorkerStatus? = null,
    val nextScheduledUpdateAt: String? = null,
) {
    /**
     * One phase in the published phase plan.
     *
     * @property id Stable phase ID.
     * @property label Server label.
     */
    @Serializable
    data class PhaseDescriptor(val id: String, val label: String? = null)

    /**
     * Ordered phase plan.
     *
     * @property version Plan version.
     * @property phases Phases in order.
     */
    @Serializable
    data class PhasePlan(val version: String? = null, val phases: List<PhaseDescriptor>? = null)

    /**
     * The last scrape that reached publication.
     *
     * @property publishedAt Publication time (ISO-8601).
     * @property completedAt Completion time (ISO-8601).
     */
    @Serializable
    data class CompletedUpdate(val publishedAt: String? = null, val completedAt: String? = null)

    /**
     * Subphase progress (`schemaVersion` 1).
     *
     * @property schemaVersion Only 1 is understood.
     * @property id Subphase ID.
     * @property epoch Progress epoch (a new epoch resets sequencing).
     * @property sequence Monotonic sequence within an epoch.
     * @property kind `exact`, `indeterminate` or `not_applicable`.
     * @property unitsKind Unit label key.
     * @property unitsCompleted Completed units.
     * @property unitsTotal Total units.
     * @property unitsTotalFinal Whether the total is final.
     * @property percent 0–100.
     */
    @Serializable
    data class SubphaseProgress(
        val schemaVersion: Double? = null,
        val id: String? = null,
        val epoch: Double? = null,
        val sequence: Double? = null,
        val kind: String? = null,
        val unitsKind: String? = null,
        val unitsCompleted: Double? = null,
        val unitsTotal: Double? = null,
        val unitsTotalFinal: Boolean? = null,
        val percent: Double? = null,
    )

    /**
     * The running (or last failed) update.
     *
     * @property status `idle`, `updating`, `failed` or `stalled` (unknown values kept verbatim).
     */
    @Serializable
    data class CurrentUpdate(
        val status: String,
        val scrapeId: Double? = null,
        val startedAt: String? = null,
        val phase: String? = null,
        val subOperation: String? = null,
        val contractVersion: Double? = null,
        val operationId: String? = null,
        val phaseId: String? = null,
        val phaseStatus: String? = null,
        val subphaseId: String? = null,
        val phasePlanVersion: String? = null,
        val phaseOrdinal: Double? = null,
        val phaseAttempt: Double? = null,
        val unitsKind: String? = null,
        val unitsCompleted: Double? = null,
        val unitsTotal: Double? = null,
        val unitsTotalFinal: Boolean? = null,
        val phasePercent: Double? = null,
        val subphaseProgress: SubphaseProgress? = null,
        val lastProgressAt: String? = null,
        val updatedAt: String? = null,
        val heartbeatAt: String? = null,
    )

    /**
     * Publication pointers and the public-read freeze.
     *
     * @property publishedAt Current publication time.
     * @property publicReadsFrozen Whether public reads are frozen.
     * @property freezeReason Freeze reason.
     */
    @Serializable
    data class PublicationState(val publishedAt: String? = null, val publicReadsFrozen: Boolean? = null, val freezeReason: String? = null)

    /**
     * Scraper worker heartbeat summary.
     *
     * @property status `online`, `offline`, `stale`, `starting`, `stopping` or `unknown`.
     */
    @Serializable
    data class WorkerStatus(val status: String? = null)
}

/**
 * A service-info read plus the freeze header observed on it.
 *
 * @property info Decoded body.
 * @property freezeReasonHeader `X-FST-Public-Read-Freeze-Reason`, when stamped.
 */
data class ServiceInfoSnapshot(val info: ServiceInfo, val freezeReasonHeader: String? = null)

// endregion

// region Progress reduction

/**
 * Monotonic progress bar state (web `ServiceBarProgress`).
 *
 * @property identity Operation/phase/attempt/subphase/epoch identity.
 * @property id Subphase ID.
 * @property sequence Sequence within the identity.
 * @property kind Exact, indeterminate or not applicable.
 * @property percent 0–100, only when [kind] is [Kind.Exact].
 * @property unitsKind Unit label key.
 * @property unitsCompleted Completed units.
 * @property unitsTotal Total units.
 */
data class ServiceBarProgress(
    val identity: String,
    val id: String?,
    val sequence: Double,
    val kind: Kind,
    val percent: Double?,
    val unitsKind: String?,
    val unitsCompleted: Double?,
    val unitsTotal: Double?,
) {
    /** Bar kind (`exact`, `indeterminate`, `not_applicable`). */
    enum class Kind { Exact, Indeterminate, NotApplicable }
}

/**
 * What the card renders for one poll (web `ServiceProgressDisplay`; ETA, overall percent and
 * discovery-attempt counts are not shown by the natives).
 */
data class ServiceProgressDisplay(
    val phasePercent: Double? = null,
    val phaseId: String? = null,
    val subphaseId: String? = null,
    val phaseAttempt: Double? = null,
    val phaseOrdinal: Double? = null,
    val restarted: Boolean = false,
    val stalePayloadIgnored: Boolean = false,
    val barProgress: ServiceBarProgress? = null,
)

/** Memory carried between polls so progress never moves backwards within one phase attempt. */
data class ServiceProgressMemory(
    val operationIdentity: String?,
    val phaseId: String?,
    val phaseAttempt: Double?,
    val phaseOrdinal: Double?,
    val lastProgressTimestamp: Instant?,
    val display: ServiceProgressDisplay,
)

/**
 * Port of the web's `reduceServiceProgress` (`pages/settings/serviceProgress.ts`, Apple
 * `ServiceProgressReducer`): percentages are clamped and monotonic within an
 * operation/phase/attempt, stale out-of-order payloads are ignored, and a restarted attempt
 * resets the bar.
 */
object ServiceProgressReducer {
    /**
     * Reduce one poll against the previous memory.
     *
     * @param previous Memory from the last poll, or null.
     * @param info New body.
     * @return Display for this poll and memory for the next.
     */
    fun reduce(previous: ServiceProgressMemory?, info: ServiceInfo): Pair<ServiceProgressDisplay, ServiceProgressMemory> {
        val current = info.currentUpdate
        val identity = operationIdentity(info)
        if (current.status != "updating") {
            return ServiceProgressDisplay() to ServiceProgressMemory(null, null, null, null, null, ServiceProgressDisplay())
        }
        val isV2 = info.contractVersion == 2.0 || current.contractVersion == 2.0 || current.phaseId != null
        val timestamp = ServiceInfoText.parseDate(current.lastProgressAt ?: current.updatedAt ?: current.heartbeatAt)
        val sameOperation = previous?.operationIdentity != null && previous.operationIdentity == identity
        val phaseId = current.phaseId
        val phaseAttempt = finite(current.phaseAttempt)
        val phaseOrdinal = finite(current.phaseOrdinal)
        val samePhase = sameOperation && previous?.phaseId != null && previous.phaseId == phaseId
        val attemptChanged = samePhase && previous?.phaseAttempt != null && phaseAttempt != null && previous.phaseAttempt != phaseAttempt
        val previousOrdinal = previous?.phaseOrdinal
        val ordinalRestart = sameOperation && previousOrdinal != null && phaseOrdinal != null && phaseOrdinal < previousOrdinal
        val restarted = attemptChanged || ordinalRestart

        val last = previous?.lastProgressTimestamp
        if (previous != null && sameOperation && !restarted && timestamp != null && last != null && timestamp < last) {
            val display = previous.display.copy(stalePayloadIgnored = true, restarted = false)
            return display to previous.copy(display = display)
        }

        val unitsTotalFinal = isV2 && current.unitsTotalFinal == true
        val rawPhasePercent = if (unitsTotalFinal) clamp(finite(current.phasePercent)) else null
        val previousPhasePercent = if (samePhase && !restarted) previous?.display?.phasePercent else null
        val phasePercent = rawPhasePercent?.let { max(it, previousPhasePercent ?: it) }

        val display = ServiceProgressDisplay(
            phasePercent = phasePercent,
            phaseId = phaseId,
            subphaseId = current.subphaseId,
            phaseAttempt = phaseAttempt,
            phaseOrdinal = phaseOrdinal,
            restarted = restarted,
            barProgress = reduceBar(previous?.display?.barProgress, info, identity, phaseId, phaseAttempt, phasePercent),
        )
        val memory = ServiceProgressMemory(identity, phaseId, phaseAttempt, phaseOrdinal, timestamp ?: previous?.lastProgressTimestamp, display)
        return display to memory
    }

    /**
     * Stable identity of the running operation (`scrapeId:operationId:planVersion`).
     *
     * @param info Body.
     * @return Identity, or null when neither a scrape nor an operation ID is known.
     */
    fun operationIdentity(info: ServiceInfo): String? {
        val current = info.currentUpdate
        val scrapeId = current.scrapeId ?: info.activeScrapeId
        if (scrapeId == null && current.operationId == null) return null
        return listOf(
            scrapeId?.let(::format) ?: current.startedAt ?: "none",
            current.operationId ?: "legacy",
            current.phasePlanVersion ?: info.phasePlan?.version ?: "unversioned",
        ).joinToString(":")
    }

    private fun reduceBar(
        previous: ServiceBarProgress?,
        info: ServiceInfo,
        identity: String?,
        phaseId: String?,
        phaseAttempt: Double?,
        phasePercent: Double?,
    ): ServiceBarProgress {
        val current = info.currentUpdate
        val prefix = listOf(identity ?: "none", phaseId ?: "none", phaseAttempt?.let(::format) ?: "none")
        val raw = current.subphaseProgress
        if (raw != null) {
            val epoch = finite(raw.epoch) ?: 0.0
            val sequence = finite(raw.sequence) ?: 0.0
            val expectedId = current.subphaseId
            val id = raw.id ?: expectedId
            val barIdentity = (prefix + listOf(id ?: "none", format(epoch))).joinToString(":")
            val sameIdentity = previous?.identity == barIdentity
            if (previous != null && sameIdentity && sequence < previous.sequence) return previous

            val supported = raw.schemaVersion == 1.0
            val matching = expectedId == null || id == expectedId
            var kind = when {
                supported && matching && raw.kind == "exact" -> ServiceBarProgress.Kind.Exact
                supported && matching && raw.kind == "not_applicable" -> ServiceBarProgress.Kind.NotApplicable
                else -> ServiceBarProgress.Kind.Indeterminate
            }
            val completed = finite(raw.unitsCompleted)
            val total = finite(raw.unitsTotal)
            val exactPercent = if (
                kind == ServiceBarProgress.Kind.Exact && raw.unitsTotalFinal == true &&
                total != null && total > 0 && completed != null && completed >= 0 && completed <= total
            ) {
                clamp(finite(raw.percent))
            } else {
                null
            }
            if (kind == ServiceBarProgress.Kind.Exact && exactPercent == null) kind = ServiceBarProgress.Kind.Indeterminate
            val prior = previous?.percent
            val percent = if (kind == ServiceBarProgress.Kind.Exact && sameIdentity && prior != null && exactPercent != null) max(prior, exactPercent) else exactPercent
            val exact = kind == ServiceBarProgress.Kind.Exact
            return ServiceBarProgress(
                identity = barIdentity, id = id, sequence = sequence, kind = kind, percent = percent,
                unitsKind = if (exact) raw.unitsKind else null,
                unitsCompleted = if (exact) completed else null,
                unitsTotal = if (exact) total else null,
            )
        }
        current.subphaseId?.let { subphaseId ->
            return ServiceBarProgress(
                identity = (prefix + listOf(subphaseId, "legacy")).joinToString(":"), id = subphaseId,
                sequence = 0.0, kind = ServiceBarProgress.Kind.Indeterminate, percent = null,
                unitsKind = null, unitsCompleted = null, unitsTotal = null,
            )
        }
        return ServiceBarProgress(
            identity = (prefix + "phase").joinToString(":"), id = null, sequence = 0.0,
            kind = if (phasePercent != null) ServiceBarProgress.Kind.Exact else ServiceBarProgress.Kind.Indeterminate,
            percent = phasePercent,
            unitsKind = current.unitsKind, unitsCompleted = finite(current.unitsCompleted), unitsTotal = finite(current.unitsTotal),
        )
    }

    private fun finite(value: Double?): Double? = value?.takeIf { it.isFinite() }

    private fun clamp(value: Double?): Double? = value?.let { min(100.0, max(0.0, it)) }

    /**
     * Integral doubles print without a decimal point, as JavaScript would.
     *
     * @param value Number.
     * @return Text.
     */
    fun format(value: Double): String =
        if (value == floor(value) && abs(value) < 1e15) value.toLong().toString() else value.toString()
}

// endregion

// region Presentation

/** Worker/process state shown beside "Leaderboard Service State". */
enum class ServiceProcessState(val label: String) {
    Loading("Loading"),
    Updating("Updating"),
    Idle("Idle"),
    Stopped("Stopped"),
}

/**
 * Copy and label rules for the Service Info card, ported from `SettingsServiceProgress.tsx`
 * and `serviceInfo.en.json` (Apple `ServiceInfoText`).
 */
object ServiceInfoText {
    const val TITLE = "Service Info"
    const val HINT = "Live leaderboard update status, exact phase progress when available, and publication timing."
    const val SERVICE_STATE_TITLE = "Leaderboard Service State"
    const val LAST_PUBLISHED_TITLE = "Last Successful Publication"
    const val PUBLICATION_UNAVAILABLE = "No successful publication yet"
    const val PROGRESS_INDETERMINATE = "In progress — total not yet known"
    const val FREEZE_TITLE = "Public Reads"

    /**
     * Process state: stopped when the worker is missing, offline, stale or stopping.
     *
     * @param info Body.
     * @return Updating, idle or stopped.
     */
    fun processState(info: ServiceInfo): ServiceProcessState = when (info.workerStatus?.status) {
        null, "offline", "stale", "stopping" -> ServiceProcessState.Stopped
        else -> if (info.currentUpdate.status == "updating") ServiceProcessState.Updating else ServiceProcessState.Idle
    }

    private val serviceStates = mapOf(
        "idle" to "Waiting for the Next Update",
        "updating" to "Leaderboard Update in Progress",
        "failed" to "Last Leaderboard Update Failed",
        "stalled" to "Leaderboard Update Stalled",
        "unavailable" to "Leaderboard Updater Unavailable",
    )

    /**
     * Description of the update status (used when not actively updating).
     *
     * @param info Body.
     * @param state Resolved process state.
     * @return Title Case status sentence.
     */
    fun serviceState(info: ServiceInfo, state: ServiceProcessState): String {
        val status = info.currentUpdate.status
        if (state == ServiceProcessState.Stopped && status != "failed" && status != "stalled") return serviceStates.getValue("unavailable")
        return serviceStates[status] ?: fallbackLabel(status)
    }

    /**
     * Phase label: "Waiting for the next update" when idle, else the phase name.
     *
     * @param info Body.
     * @param display Reduced progress.
     * @return Phase label.
     */
    fun phaseLabel(info: ServiceInfo, display: ServiceProgressDisplay): String {
        val current = info.currentUpdate
        if (current.status == "idle") return "Waiting for the next update"
        val descriptor = info.phasePlan?.phases?.firstOrNull { it.id == display.phaseId }
        return stableLabel(phaseLabels, display.phaseId, descriptor?.label ?: current.phase) ?: "Waiting for progress"
    }

    /**
     * Subphase label, or null when none or it only repeats the status.
     *
     * @param info Body.
     * @param display Reduced progress.
     * @return Label or null.
     */
    fun subphaseLabel(info: ServiceInfo, display: ServiceProgressDisplay): String? {
        val current = info.currentUpdate
        val subphaseId = display.subphaseId ?: current.subOperation ?: return null
        if (subphaseId == current.status) return null
        return dynamicSubphaseLabel(subphaseId) ?: stableLabel(subphaseLabels, subphaseId, fallbackLabel(current.subOperation ?: subphaseId))
    }

    /**
     * "Phase · Subphase", dropping a subphase that repeats the phase.
     *
     * @param phase Phase label.
     * @param subphase Optional subphase label.
     * @return Row title.
     */
    fun phaseTitle(phase: String, subphase: String?): String =
        if (subphase == null || subphase.trim().lowercase() == phase.trim().lowercase()) phase else "$phase · $subphase"

    /**
     * Units line under the bar ("1,234 of 5,000 leaderboards completed").
     *
     * @param progress Bar progress.
     * @param locale Number locale.
     * @return Sentence, or null when no count is known.
     */
    fun unitsText(progress: ServiceBarProgress?, locale: Locale = Locale.getDefault()): String? {
        val completed = progress?.unitsCompleted ?: return null
        val unit = stableLabel(unitLabels, progress.unitsKind, progress.unitsKind?.let(::fallbackLabel)) ?: "items"
        val done = grouped(completed, locale)
        return progress.unitsTotal?.let { "$done of ${grouped(it, locale)} $unit completed" } ?: "$done $unit completed"
    }

    /**
     * Percent text for a determinate bar, or the indeterminate sentence.
     *
     * @param progress Bar progress.
     * @return "42.5%" or [PROGRESS_INDETERMINATE].
     */
    fun progressText(progress: ServiceBarProgress?): String {
        val percent = progress?.percent
        if (progress?.kind != ServiceBarProgress.Kind.Exact || percent == null) return PROGRESS_INDETERMINATE
        return String.format(Locale.US, "%.1f%%", percent)
    }

    /**
     * Last successful publication time (web `formatDateTime`: "Sep 28, 2026, 3:45 PM PDT").
     *
     * @param info Body.
     * @param zone Display time zone.
     * @param locale Display locale.
     * @return Formatted time or [PUBLICATION_UNAVAILABLE].
     */
    fun lastPublished(info: ServiceInfo, zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault()): String {
        val instant = parseDate(info.lastCompletedUpdate?.publishedAt ?: info.publication?.publishedAt) ?: return PUBLICATION_UNAVAILABLE
        return DateTimeFormatter.ofPattern("MMM d, yyyy, h:mm a z", locale).format(instant.atZone(zone))
    }

    /**
     * Freeze explanation, from the response header first and the body second.
     *
     * @param snapshot One read.
     * @return Sentence while public reads are frozen, else null.
     */
    fun freezeNotice(snapshot: ServiceInfoSnapshot): String? {
        val header = snapshot.freezeReasonHeader?.trim()?.takeIf { it.isNotEmpty() }
        val body = snapshot.info.publication
        val reason = header ?: if (body?.publicReadsFrozen == true) body.freezeReason.orEmpty() else return null
        return if (ServiceFreezeReason.isScoreUpdate(reason)) {
            "Paused while new scores publish. Pages show the last publication."
        } else {
            "Paused for service maintenance. Pages show the last publication."
        }
    }

    /**
     * Parse an ISO-8601 timestamp, tolerating .NET's seven fractional digits.
     *
     * @param value Timestamp text.
     * @return Instant, or null for missing or unparsable text.
     */
    fun parseDate(value: String?): Instant? {
        val text = value?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        return try {
            Instant.parse(text)
        } catch (_: DateTimeParseException) {
            try {
                java.time.OffsetDateTime.parse(text).toInstant()
            } catch (_: DateTimeParseException) {
                null
            }
        }
    }

    // region Labels

    /**
     * Web `fallbackLabel`: `.`/`_` → space, split camelCase, capitalize word starts.
     *
     * @param id Stable identifier.
     * @return Readable label.
     */
    fun fallbackLabel(id: String): String {
        val spaced = StringBuilder()
        var previous: Char? = null
        for (char in id) {
            val mapped = if (char == '.' || char == '_') ' ' else char
            if (previous != null && mapped.isUpperCase() && (previous.isLowerCase() || previous.isDigit())) spaced.append(' ')
            spaced.append(mapped)
            previous = mapped
        }
        val result = StringBuilder()
        var atWordStart = true
        for (char in spaced) {
            val isWord = char.isLetterOrDigit()
            result.append(if (atWordStart && isWord) char.uppercaseChar() else char)
            atWordStart = !isWord
        }
        return result.toString().trim()
    }

    private fun stableLabel(table: Map<String, String>, id: String?, fallback: String?): String? {
        if (id == null) return fallback
        val key = id.replace('.', '_').replace('-', '_')
        return table[key] ?: fallback?.takeIf { it.isNotEmpty() } ?: fallbackLabel(id)
    }

    /**
     * `cleanup_rank_history_<scope>` / `cleanup_band_rank_history_<scope>` patterns.
     *
     * @param id Subphase ID.
     * @return "Cleaning <scope> Rank History", or null for other IDs.
     */
    fun dynamicSubphaseLabel(id: String): String? {
        val normalized = id.trim()
        val lower = normalized.lowercase()
        val prefix = listOf("cleanup_band_rank_history_", "cleanup_rank_history_").firstOrNull(lower::startsWith) ?: return null
        val suffix = normalized.drop(prefix.length).takeIf { it.isNotEmpty() } ?: return null
        val scope = Instrument.entries.firstOrNull { it.wireId == suffix }?.label ?: fallbackLabel(suffix)
        return "Cleaning $scope Rank History"
    }

    private fun grouped(value: Double, locale: Locale): String = NumberFormat.getIntegerInstance(locale).format(value.roundToLong())

    private val unitLabels = mapOf(
        "leaderboards" to "leaderboards", "songs" to "songs", "batches" to "batches", "steps" to "steps",
        "accounts" to "accounts", "bands" to "bands", "scopes" to "scopes", "instruments" to "instruments",
        "band_types" to "band types", "branches" to "branches", "items" to "items",
        "deep_jobs" to "deep-scrape jobs", "band_pages" to "band pages", "pages" to "pages",
        "chunks" to "chunks", "indexes" to "indexes",
    )

    private val phaseLabels = mapOf(
        "scrape_leaderboards" to "Scraping Leaderboard Scores",
        "post_rank_recompute" to "Post-Scrape Enrichment",
        "post_first_seen_season" to "Post-Scrape Enrichment",
        "post_account_name_resolution" to "Resolving Player Names",
        "post_refresh_registered_users" to "Refreshing Registered Users",
        "post_activate_shadow_snapshots_early" to "Snapshot Preparation",
        "post_band_extraction" to "Extracting Band Context",
        "post_legacy_band_scrape" to "Fetching Legacy Band Leaderboards",
        "post_registered_player_band_discovery" to "Registered Player Band Discovery",
        "post_registered_band_targeted_processing" to "Registered Band Processing",
        "post_deferred_registration_sync" to "Deferred Registration Sync",
        "post_band_maintenance" to "Band Maintenance",
        "post_compute_rankings" to "Computing Rankings",
        "post_prepare_solo_current_projection" to "Preparing Current Solo Rankings",
        "post_rivals" to "Computing Player Rivals",
        "post_leaderboard_rivals" to "Calculating Leaderboard Rivals",
        "post_player_stats_tiers" to "Computing Player Statistics",
        "post_checkpoint" to "Checkpoint",
        "post_activate_shadow_snapshots" to "Finalizing Updated Leaderboard Data",
        "post_seal_solo_current_projection" to "Finalizing Solo Ranking Scopes",
        "post_cleanup_solo_current_projection" to "Solo Projection Cleanup",
        "post_cleanup_precompute_all" to "API Precompute Cleanup",
        "post_cleanup_solo_excess_entries" to "Solo Entry Cleanup",
        "post_cleanup_rank_history_retention" to "Solo Rank History Cleanup",
        "post_cleanup_band_rank_history_retention" to "Band Rank History Cleanup",
        "post_cleanup_service_level_retention" to "Retention",
        "publication_commit" to "Publishing Leaderboard Update",
        "post_improvement_notifications" to "Preparing Improvement Notifications",
    )

    private val subphaseLabels = mapOf(
        "fetching_leaderboards" to "Fetching Leaderboards",
        "persisting_scores" to "Saving Retrieved Scores",
        "deep_scraping" to "Fetching Extended Leaderboard Data",
        "cancelling_band_after_solo_failure" to "Stopping Band Leaderboard Fetch",
        "draining_solo_writes" to "Saving Leaderboard Scores",
        "dropping_solo_indexes" to "Preparing Solo Score Storage",
        "flushing_solo" to "Saving Solo Leaderboard Scores",
        "creating_solo_indexes" to "Optimizing Solo Score Storage",
        "detecting_score_changes" to "Detecting Score Changes",
        "checkpointing" to "Saving Scrape Checkpoint",
        "updating_population" to "Updating Leaderboard Totals",
        "awaiting_band" to "Fetching Band Leaderboards",
        "skipping_band_after_timeout" to "Continuing Without Band Leaderboards",
        "dropping_band_indexes" to "Preparing Band Score Storage",
        "flushing_band" to "Saving Band Leaderboard Scores",
        "creating_band_indexes" to "Optimizing Band Score Storage",
        "discovering_season_windows" to "Finding Festival Seasons",
        "building_work_list" to "Preparing Player Sync Work",
        "processing_songs" to "Refreshing Player Scores",
        "completing_user_actions" to "Finalizing Player Sync",
        "per_song_rivals" to "Calculating Player Rivals",
        "population_tiers" to "Calculating Leaderboard Percentiles",
        "parallel_precompute" to "Preparing Published API Data",
        "extracting_band_context" to "Processing Band Score Data",
        "rebuilding_band_membership_summary" to "Refreshing Band Membership",
        "per_instrument_rankings" to "Calculating Instrument Rankings",
        "composite_rankings" to "Calculating Overall Rankings",
        "solo_family_rankings" to "Calculating Solo Rankings",
        "combo_rankings" to "Calculating Combined Rankings",
        "rank_history_and_band_rankings" to "Calculating Rank History and Band Rankings",
        "band_rankings" to "Calculating Band Rankings",
        "rank_history_snapshots" to "Saving Rank History",
        "activating_shadow_snapshots_early" to "Preparing Updated Leaderboard Data",
        "registered_player_band_discovery" to "Finding Registered Player Bands",
        "registered_band_targeted_processing" to "Refreshing Registered Bands",
        "maintaining_band_projection" to "Refreshing Band Data",
        "prune" to "Removing Outdated Band Entries",
        "search_projection_refresh" to "Refreshing Band Search Data",
        "current_projection_refresh" to "Refreshing Current Band Rankings",
        "final_checkpoint" to "Saving Final Checkpoint",
        "publication_cleanup" to "Preparing Data for Publication",
        "deferred_registration_sync" to "Syncing Deferred Registrations",
        "database_cleanup" to "Cleaning Database",
        "cleanup_solo_excess_entries" to "Removing Extra Solo Scores",
        "cleanup_service_level_retention" to "Planning Data Retention",
        "cleanup_api_precompute" to "Preparing API Responses",
        "cleanup_solo_current_projection" to "Refreshing Current Solo Rankings",
        "cleanup_composite_rank_history" to "Cleaning Overall Rank History",
        "enriching_parallel_rank_recompute" to "Recomputing Changed Ranks",
        "enriching_parallel_tail" to "Calculating Seasons and Resolving Names",
    )

    // endregion
}

// endregion

// region Rows

/** Load phase of the latest Service Info poll. */
sealed interface ServiceInfoPhase {
    /** First read in flight. */
    data object Loading : ServiceInfoPhase

    /**
     * A read succeeded.
     *
     * @property snapshot The read.
     * @property display Reduced progress.
     */
    data class Loaded(val snapshot: ServiceInfoSnapshot, val display: ServiceProgressDisplay) : ServiceInfoPhase

    /** The latest read failed (shown even after earlier successes, never stale progress). */
    data object Failed : ServiceInfoPhase
}

/**
 * Everything the card shows for one state, derived without Compose (Apple `ServiceInfoRows`).
 *
 * @property stateDescription Description under "Leaderboard Service State".
 * @property processState Trailing process state.
 * @property phaseTitle Phase row title, or null when there is no phase row.
 * @property showBar Whether the phase row has a bar.
 * @property barPercent 0–100 for a determinate bar, null for indeterminate.
 * @property progressText Percent or indeterminate caption under the bar.
 * @property unitsText Units caption under the bar.
 * @property lastPublished Last publication text, or null while loading/failed (web shows only the state row).
 * @property freezeNotice Public-read freeze explanation, when frozen.
 */
data class ServiceInfoRows(
    val stateDescription: String,
    val processState: ServiceProcessState,
    val phaseTitle: String? = null,
    val showBar: Boolean = false,
    val barPercent: Double? = null,
    val progressText: String? = null,
    val unitsText: String? = null,
    val lastPublished: String? = null,
    val freezeNotice: String? = null,
) {
    companion object {
        /**
         * Rows for a load phase.
         *
         * @param phase Poll phase.
         * @param zone Display time zone.
         * @param locale Display locale.
         * @return Row content.
         */
        fun make(phase: ServiceInfoPhase, zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault()): ServiceInfoRows = when (phase) {
            ServiceInfoPhase.Loading -> ServiceInfoRows("Loading", ServiceProcessState.Loading)
            ServiceInfoPhase.Failed -> ServiceInfoRows("Failed to load data", ServiceProcessState.Stopped)
            is ServiceInfoPhase.Loaded -> {
                val info = phase.snapshot.info
                val display = phase.display
                val updating = info.currentUpdate.status == "updating"
                val state = ServiceInfoText.processState(info)
                val phaseLabel = ServiceInfoText.phaseLabel(info, display)
                val showPhase = updating || display.phaseId != null || info.currentUpdate.phase != null
                val bar = display.barProgress
                val showBar = updating && bar?.kind != ServiceBarProgress.Kind.NotApplicable
                val determinate = bar?.kind == ServiceBarProgress.Kind.Exact && bar.percent != null
                ServiceInfoRows(
                    stateDescription = if (updating) phaseLabel else ServiceInfoText.serviceState(info, state),
                    processState = state,
                    phaseTitle = if (showPhase) ServiceInfoText.phaseTitle(phaseLabel, ServiceInfoText.subphaseLabel(info, display)) else null,
                    showBar = showBar,
                    barPercent = if (showBar && determinate) bar?.percent else null,
                    progressText = if (showBar) ServiceInfoText.progressText(bar) else null,
                    unitsText = if (showBar) ServiceInfoText.unitsText(bar, locale) else null,
                    lastPublished = ServiceInfoText.lastPublished(info, zone, locale),
                    freezeNotice = ServiceInfoText.freezeNotice(phase.snapshot),
                )
            }
        }
    }
}

// endregion
