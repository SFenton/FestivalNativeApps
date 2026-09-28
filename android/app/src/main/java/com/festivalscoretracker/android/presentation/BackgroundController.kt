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
 * One slow zoom/pan preset (scale ≤ 1.18, translation ≤ 18 dp).
 *
 * @property scale End scale.
 * @property dx End x translation in dp.
 * @property dy End y translation in dp.
 */
data class KenBurnsPreset(val scale: Float, val dx: Float, val dy: Float)

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

    /** Dim layer alpha over the art. */
    const val DIM_ALPHA = 0.7f

    /** Failed covers tolerated per publication pool before the carousel stops trying. */
    const val FAILURE_BUDGET = 5

    /** The ten zoom/pan presets. */
    val PRESETS = listOf(
        KenBurnsPreset(1.12f, 0f, 0f),
        KenBurnsPreset(1.15f, 12f, 0f),
        KenBurnsPreset(1.15f, -12f, 0f),
        KenBurnsPreset(1.14f, 0f, 12f),
        KenBurnsPreset(1.14f, 0f, -12f),
        KenBurnsPreset(1.18f, 18f, 10f),
        KenBurnsPreset(1.18f, -18f, -10f),
        KenBurnsPreset(1.16f, 14f, -14f),
        KenBurnsPreset(1.16f, -14f, 14f),
        KenBurnsPreset(1.10f, 6f, 6f),
    )

    /**
     * Decide the render mode; the in-app reduce-motion override only adds to the OS setting.
     *
     * @param systemReduceMotion OS animator scale is zero.
     * @param appReduceMotion In-app override.
     * @param dataSaver OS data saver restricts background data.
     * @param visible App is resumed.
     * @return Render mode.
     */
    fun mode(systemReduceMotion: Boolean, appReduceMotion: Boolean, dataSaver: Boolean, visible: Boolean): BackgroundMode = when {
        dataSaver -> BackgroundMode.None
        systemReduceMotion || appReduceMotion || !visible -> BackgroundMode.Still
        else -> BackgroundMode.Animated
    }

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
 * tabs or pushes. Loads the catalogue independently of the Songs tab; Song Detail
 * pushes a static focused cover and pops it when it leaves.
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
