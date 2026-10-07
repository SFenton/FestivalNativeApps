package com.festivalscoretracker.android.presentation

import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.data.CatalogPayload
import kotlin.random.Random
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

// region Background policy

/** How the shared artwork backdrop renders (`.agents/controls/artwork-background/spec.md`). */
enum class BackgroundMode {
    /** Crossfading, slowly zooming covers. */
    Animated,

    /** One still cover (reduced motion or app not visible). */
    Still,

    /** No images and no dim layer (data saver). */
    None,
}

/**
 * Contract state of the backdrop (`contracts/product.json` `artwork-background` states, plus
 * [Covered] from issue #83 and [Song] for Song Detail's static cover). Exposed to tests through
 * the semantics key `ArtworkBackgroundStateKey`, never to accessibility services.
 *
 * @property id Contract state ID.
 */
enum class BackgroundState(val id: String) {
    /** No usable art yet (catalogue loading or failed): the undimmed brand surface. */
    NoArt("no-art"),

    /** Rotating, crossfading and slowly zooming covers. */
    Animated("animated"),

    /** One still cover: system animator scale 0, in-app Reduce Motion or Disable Animated Artwork. */
    ReducedMotion("reduced-motion"),

    /** Data Saver: no images and no dim. */
    SaveData("save-data"),

    /** App not resumed (background, stopped): timer and motion paused on the current frame. */
    NotVisible("not-visible"),

    /** A Festival dialog or sheet covers the page: frame held (issue #83). */
    Covered("covered"),

    /** Song Detail's static, dimmed song cover. */
    Song("song"),
}

/**
 * One slow zoom/pan preset: the web's `MOTION_PRESETS` (`AnimatedBackground.tsx`), drawn like
 * CSS `scale(s) translate(x, y)`, so the visible offset is `s · (x, y)` (scale ≤ 1.18,
 * translation ≤ 18 dp).
 *
 * @property fromScale Start scale.
 * @property toScale End scale.
 * @property fromX Start x translation in dp (before scaling).
 * @property fromY Start y translation in dp (before scaling).
 * @property toX End x translation in dp (before scaling).
 * @property toY End y translation in dp (before scaling).
 */
data class KenBurnsPreset(
    val fromScale: Float,
    val toScale: Float,
    val fromX: Float = 0f,
    val fromY: Float = 0f,
    val toX: Float = 0f,
    val toY: Float = 0f,
) {
    /**
     * Scale at [progress].
     *
     * @param progress Drift progress, 0…1.
     * @return Scale factor.
     */
    fun scaleAt(progress: Float): Float = fromScale + (toScale - fromScale) * progress

    /**
     * Visible x offset in dp at [progress] (CSS translate inside scale).
     *
     * @param progress Drift progress, 0…1.
     * @return Offset in dp.
     */
    fun offsetXAt(progress: Float): Float = (fromX + (toX - fromX) * progress) * scaleAt(progress)

    /**
     * Visible y offset in dp at [progress] (CSS translate inside scale).
     *
     * @param progress Drift progress, 0…1.
     * @return Offset in dp.
     */
    fun offsetYAt(progress: Float): Float = (fromY + (toY - fromY) * progress) * scaleAt(progress)
}

/**
 * Paced failure recovery for one publication pool (spec "Retry pacing"): at most
 * [BackgroundPolicy.IMMEDIATE_ATTEMPTS] covers per five-second deadline, then wait for the next
 * deadline, and stop after [BackgroundPolicy.FAILURE_BUDGET] failures. So three 404s cannot
 * hide a valid fourth cover, and a dead CDN costs five requests, not one per tick forever.
 */
class CoverFailurePacer {
    private var failures = 0
    private var attempts = 1

    /** Total failures recorded in this pool. */
    val failureCount: Int get() = failures

    /** The pool's failure budget is spent: rotation stops. */
    val exhausted: Boolean get() = failures >= BackgroundPolicy.FAILURE_BUDGET

    /**
     * Record a failed cover.
     *
     * @return True to try the next cover now; false to wait for the next deadline (or stop when [exhausted]).
     */
    fun onFailure(): Boolean {
        failures++
        if (exhausted || attempts >= BackgroundPolicy.IMMEDIATE_ATTEMPTS) return false
        attempts++
        return true
    }

    /** A dwell deadline advanced the carousel: the next cover is a fresh first attempt. */
    fun onDeadline() {
        attempts = 1
    }
}

/** Pure timing and selection rules for the backdrop. */
object BackgroundPolicy {
    /** Maximum covers in one shuffled carousel. */
    const val MAX_COVERS = 100

    /** Time each cover is shown. */
    const val DWELL_MS = 5_000L

    /** Crossfade between covers. */
    const val CROSSFADE_MS = 1_000

    /** Zoom/pan duration. */
    const val ZOOM_MS = 6_000

    /** Dim layer alpha over the art (black 0.7, web `AnimatedBackground` overlay). */
    const val DIM_ALPHA = 0.7f

    /**
     * Brightness the art is multiplied by: the same pixels as a black [DIM_ALPHA] layer over
     * opaque art, but the brand surface behind missing or failed art is never dimmed (as on Apple).
     */
    const val ART_LIGHTNESS = 1f - DIM_ALPHA

    /** Failed covers tolerated per publication pool before the carousel stops trying. */
    const val FAILURE_BUDGET = 5

    /** Covers tried per dwell deadline before waiting for the next one. */
    const val IMMEDIATE_ATTEMPTS = 3

    /** The web's ten zoom/pan presets (`AnimatedBackground.tsx` `MOTION_PRESETS`). */
    val PRESETS = listOf(
        KenBurnsPreset(1.00f, 1.12f),
        KenBurnsPreset(1.12f, 1.00f),
        KenBurnsPreset(1.18f, 1.18f, fromX = 18f, toX = -18f),
        KenBurnsPreset(1.18f, 1.18f, fromX = -18f, toX = 18f),
        KenBurnsPreset(1.18f, 1.18f, fromY = 18f, toY = -18f),
        KenBurnsPreset(1.18f, 1.18f, fromY = -18f, toY = 18f),
        KenBurnsPreset(1.18f, 1.18f, -14f, -14f, 14f, 14f),
        KenBurnsPreset(1.18f, 1.18f, 14f, -14f, -14f, 14f),
        KenBurnsPreset(1.18f, 1.18f, -14f, 14f, 14f, -14f),
        KenBurnsPreset(1.18f, 1.18f, 14f, 14f, -14f, -14f),
    )

    /**
     * Decide the render mode; the in-app reduce-motion override only adds to the OS setting.
     *
     * @param systemReduceMotion OS animator scale is zero.
     * @param appReduceMotion In-app override.
     * @param dataSaver OS data saver restricts background data.
     * @param visible App is resumed.
     * @param covered A Festival dialog or sheet covers the page: hold the current frame.
     * @return Render mode.
     */
    fun mode(
        systemReduceMotion: Boolean,
        appReduceMotion: Boolean,
        dataSaver: Boolean,
        visible: Boolean,
        covered: Boolean = false,
    ): BackgroundMode = when {
        dataSaver -> BackgroundMode.None
        systemReduceMotion || appReduceMotion || !visible || covered -> BackgroundMode.Still
        else -> BackgroundMode.Animated
    }

    /**
     * Contract state for tests and evidence; the first matching rule wins, like [mode].
     *
     * @param systemReduceMotion OS animator scale is zero.
     * @param appReduceMotion In-app Reduce Motion or Disable Animated Artwork.
     * @param dataSaver OS data saver restricts background data.
     * @param visible App is resumed.
     * @param covered A Festival dialog or sheet covers the page.
     * @param hasArt Covers are loaded or a song cover is focused.
     * @param focused Song Detail's static cover is shown.
     * @return State.
     */
    fun state(
        systemReduceMotion: Boolean,
        appReduceMotion: Boolean,
        dataSaver: Boolean,
        visible: Boolean,
        covered: Boolean,
        hasArt: Boolean,
        focused: Boolean,
    ): BackgroundState = when {
        dataSaver -> BackgroundState.SaveData
        !hasArt -> BackgroundState.NoArt
        !visible -> BackgroundState.NotVisible
        focused -> BackgroundState.Song
        systemReduceMotion || appReduceMotion -> BackgroundState.ReducedMotion
        covered -> BackgroundState.Covered
        else -> BackgroundState.Animated
    }

    /**
     * Zoom/pan and crossfade frame interval: 30 fps, like the iOS and Windows backdrops,
     * instead of every vsync (issue #83).
     */
    const val FRAME_INTERVAL_NANOS = 1_000_000_000L / 30

    /**
     * Duration left of the zoom/pan when it resumes from [progress] (after a pause), so a
     * resumed drift keeps its speed.
     *
     * @param progress Current progress, 0…1.
     * @return Remaining milliseconds (at least 1).
     */
    fun remainingZoomMs(progress: Float): Int = ((1f - progress.coerceIn(0f, 1f)) * ZOOM_MS).toInt().coerceAtLeast(1)

    /**
     * Pick up to [MAX_COVERS] distinct shuffled cover URLs.
     *
     * @param songs Catalogue.
     * @param artworkUrl Resolver returning null for missing/invalid art.
     * @param random Shuffle source.
     * @return Distinct URLs.
     */
    fun pickCovers(songs: List<Song>, artworkUrl: (String?) -> String?, random: Random): List<String> =
        songs.mapNotNull { artworkUrl(it.albumArt) }.distinct().shuffled(random).take(MAX_COVERS)
}

// endregion

// region Background controller

/**
 * App-scoped backdrop state hosted once by the shell, so it never restarts across
 * tabs or pushes. Loads the catalogue independently of the Songs tab; song-scoped pages
 * (Song Detail and its solo and band leaderboards, via `SongCoverBackdrop`) push a static
 * focused cover and pop it when they leave.
 *
 * @property loadCatalog Catalogue read.
 * @property artworkUrl Artwork resolver.
 * @property random Shuffle source.
 */
class BackgroundController(
    private val loadCatalog: suspend () -> CatalogPayload,
    private val artworkUrl: (String?) -> String?,
    private val random: Random = Random.Default,
) {
    private val coversFlow = MutableStateFlow<List<String>>(emptyList())
    private val focusStack = MutableStateFlow<List<Pair<Any, String>>>(emptyList())
    private val focusFlow = MutableStateFlow<String?>(null)
    private var loadedPublication: Int? = null

    /** Shuffled carousel covers (empty until the catalogue loads). */
    val covers: StateFlow<List<String>> = coversFlow.asStateFlow()

    /** The topmost focused (static, dimmed) song cover, or null for the carousel. */
    val focus: StateFlow<String?> = focusFlow.asStateFlow()

    /**
     * Load covers once per publication; failures are ignored (the art is decorative).
     *
     * @param scope Scope to load in.
     */
    fun start(scope: CoroutineScope) {
        scope.launch {
            try {
                val payload = loadCatalog()
                if (payload.publicationId != loadedPublication) {
                    loadedPublication = payload.publicationId
                    coversFlow.value = BackgroundPolicy.pickCovers(payload.catalog.songs, artworkUrl, random)
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                // Decorative: a failed catalogue read leaves the plain background.
            }
        }
    }

    /**
     * Show a static cover while a song page is visible.
     *
     * @param raw Song `albumArt`.
     * @return Token for [popFocus], or null when the song has no usable art.
     */
    fun pushFocus(raw: String?): Any? {
        val url = artworkUrl(raw) ?: return null
        val token = Any()
        focusStack.value = focusStack.value + (token to url)
        focusFlow.value = focusStack.value.lastOrNull()?.second
        return token
    }

    /**
     * Remove a focused cover pushed earlier.
     *
     * @param token Token from [pushFocus].
     */
    fun popFocus(token: Any?) {
        if (token == null) return
        focusStack.value = focusStack.value.filterNot { it.first === token }
        focusFlow.value = focusStack.value.lastOrNull()?.second
    }
}

// endregion
