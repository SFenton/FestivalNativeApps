package com.festivalscoretracker.android.presentation.songs

import androidx.compose.ui.graphics.ImageBitmap
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.paths.PathDifficulty
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.settings.PathDisplayMode
import com.festivalscoretracker.android.data.paths.SongPathDataPayload
import com.festivalscoretracker.android.data.paths.SongPathImagePayload
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

// region State

/** One Paths display's load state. */
sealed interface PathLoad {
    /** Loading. */
    data object Loading : PathLoad

    /**
     * Image loaded.
     *
     * @property image Validated PNG.
     * @property decoded Bitmap decoded during the spinner, or null when undecodable.
     * @property prepared Whether [decoded] came from the view model's decoder; when false the
     *   view decodes [image] itself.
     */
    data class Image(val image: SongPathImagePayload, val decoded: ImageBitmap? = null, val prepared: Boolean = false) : PathLoad

    /**
     * Table loaded.
     *
     * @property data Validated table.
     */
    data class Text(val data: SongPathDataPayload) : PathLoad

    /** The service has no path for this chart/difficulty (HTTP 404). */
    data object NotGenerated : PathLoad

    /**
     * Load failed.
     *
     * @property issue Classified failure.
     */
    data class Failed(val issue: ServiceIssue) : PathLoad
}

/**
 * Where a Paths content swap is (web `PathsModal` phases `fadeOutImage` → `spinner` →
 * `fadeOutSpinner` → `fadeInImage`/`textStagger` → `idle`).
 */
enum class PathSwapPhase {
    /** The previous chart/table/message is fading out. */
    ContentOut,

    /** The spinner is fading in or holding while the new content loads. */
    Spinner,

    /** The spinner is fading out. */
    SpinnerOut,

    /** [SongPathsState.load] is fading in or shown. */
    Content,
}

/**
 * Chart selection a Paths load belongs to.
 *
 * @property instrument Chart.
 * @property difficulty Difficulty.
 * @property display Image or text.
 */
data class PathSelection(val instrument: Instrument, val difficulty: PathDifficulty, val display: PathDisplayMode)

/**
 * Paths sheet selection and content.
 *
 * @property instrument Selected chart.
 * @property difficulty Selected difficulty.
 * @property display Image or text.
 * @property load Presented content, which belongs to [shown] and can lag the selection
 *   while the previous content fades out.
 * @property shown Selection [load] belongs to.
 * @property phase Swap phase; the view shows [load] only in [PathSwapPhase.Content] and
 *   [PathSwapPhase.ContentOut], and the spinner in [PathSwapPhase.Spinner]/[PathSwapPhase.SpinnerOut].
 */
data class SongPathsState(
    val instrument: Instrument,
    val difficulty: PathDifficulty = PathDifficulty.Expert,
    val display: PathDisplayMode = PathDisplayMode.Image,
    val load: PathLoad = PathLoad.Loading,
    val shown: PathSelection = PathSelection(instrument, difficulty, display),
    val phase: PathSwapPhase = PathSwapPhase.Spinner,
) {
    /** Current selection. */
    val selection: PathSelection get() = PathSelection(instrument, difficulty, display)

    /** Whether the spinner is mounted. */
    val spinnerVisible: Boolean get() = phase == PathSwapPhase.Spinner || phase == PathSwapPhase.SpinnerOut

    /** TalkBack status for the live region: loading, then what loaded. */
    val status: String
        get() = if (phase != PathSwapPhase.Content) {
            "Loading ${instrument.label} ${difficulty.label} path"
        } else {
            when (val load = load) {
                PathLoad.Loading -> "Loading ${shown.instrument.label} ${shown.difficulty.label} path"
                is PathLoad.Image -> "${shown.instrument.label} ${shown.difficulty.label} path image loaded"
                is PathLoad.Text -> "${shown.instrument.label} ${shown.difficulty.label} path loaded, ${activationCount(load.data.rows.size)}"
                PathLoad.NotGenerated -> notGeneratedText(shown)
                is PathLoad.Failed -> "Path unavailable"
            }
        }

    private fun activationCount(count: Int) = if (count == 1) "1 activation" else "$count activations"

    companion object {
        /**
         * Copy for a chart/difficulty with no generated path.
         *
         * @param selection Selection.
         * @return Message.
         */
        fun notGeneratedText(selection: PathSelection): String =
            "No ${selection.difficulty.label} path has been generated for ${selection.instrument.label} yet."
    }
}

/** Web `PathsModal` swap timing. */
object PathSwapTiming {
    /** Content and spinner fade (web `FADE_MS`). */
    const val FADE_MILLIS = 300L

    /** Minimum spinner hold for an image (web `MIN_SPINNER_MS`). */
    const val MIN_IMAGE_SPINNER_MILLIS = 400L

    /** Minimum spinner hold for the table (web `MIN_TEXT_SPINNER_MS`). */
    const val MIN_TEXT_SPINNER_MILLIS = 500L

    /**
     * Minimum spinner hold for a display.
     *
     * @param display Display.
     * @return Milliseconds.
     */
    fun minimumSpinner(display: PathDisplayMode): Long =
        if (display == PathDisplayMode.Image) MIN_IMAGE_SPINNER_MILLIS else MIN_TEXT_SPINNER_MILLIS
}

// endregion

// region View model

/**
 * CHOpt Paths: each opening starts at the first path chart, Expert and the saved
 * default display; a newer selection cancels the older request so an old
 * response never paints (web `PathsModal` revision guard).
 *
 * A switch runs the web swap: the shown content fades out ([PathSwapTiming.FADE_MILLIS]),
 * the spinner fades in and holds at least [PathSwapTiming.minimumSpinner] while the
 * read (and image decode) runs, fades out, and the new content fades in. A newer
 * selection cancels the sequence; the spinner, not the stale content, stays up.
 * With [reduceMotion] the swap is instant: no fade waits and no minimum spinner.
 *
 * @param instruments Path-capable, visible, charted instruments (non-empty).
 * @param defaultDisplay Saved default display.
 * @param loadImage PNG read `(instrument, difficulty)`.
 * @param loadText Table read `(instrument, difficulty)`.
 * @param decodeImage Bitmap decode run during the spinner, or null to let the view decode.
 */
class SongPathsViewModel(
    val instruments: List<Instrument>,
    defaultDisplay: PathDisplayMode,
    private val loadImage: suspend (Instrument, PathDifficulty) -> SongPathImagePayload,
    private val loadText: suspend (Instrument, PathDifficulty) -> SongPathDataPayload,
    private val decodeImage: (suspend (SongPathImagePayload) -> ImageBitmap?)? = null,
) : ViewModel() {
    private val mutableState = MutableStateFlow(SongPathsState(instruments.first(), display = defaultDisplay))
    private var job: Job? = null
    private var revision = 0

    /** Current state. */
    val state: StateFlow<SongPathsState> = mutableState.asStateFlow()

    /** System or app Reduce Motion; read at each swap step. */
    var reduceMotion: Boolean = false

    init {
        reload()
    }

    /**
     * Choose a chart.
     *
     * @param instrument Chart from [instruments].
     */
    fun selectInstrument(instrument: Instrument) {
        if (instrument !in instruments || instrument == mutableState.value.instrument) return
        mutableState.value = mutableState.value.copy(instrument = instrument)
        reload()
    }

    /**
     * Choose a difficulty.
     *
     * @param difficulty Difficulty.
     */
    fun selectDifficulty(difficulty: PathDifficulty) {
        if (difficulty == mutableState.value.difficulty) return
        mutableState.value = mutableState.value.copy(difficulty = difficulty)
        reload()
    }

    /**
     * Switch image/text.
     *
     * @param display Display.
     */
    fun selectDisplay(display: PathDisplayMode) {
        if (display == mutableState.value.display) return
        mutableState.value = mutableState.value.copy(display = display)
        reload()
    }

    /** Retry the current selection. */
    fun retry() = reload()

    private fun reload() {
        job?.cancel()
        val mine = ++revision
        val target = mutableState.value.selection
        job = viewModelScope.launch {
            coroutineScope {
                val fetch = async { fetch(target) }
                val phase = mutableState.value.phase
                if (!reduceMotion && (phase == PathSwapPhase.Content || phase == PathSwapPhase.ContentOut)) {
                    mutableState.value = mutableState.value.copy(phase = PathSwapPhase.ContentOut)
                    delay(PathSwapTiming.FADE_MILLIS)
                }
                // Unmount the old content before anything new shows: no stale chart or nodes.
                mutableState.value = mutableState.value.copy(load = PathLoad.Loading, shown = target, phase = PathSwapPhase.Spinner)
                val minimum = if (reduceMotion) null else async { delay(PathSwapTiming.minimumSpinner(target.display)) }
                val result = fetch.await()
                minimum?.await()
                if (!reduceMotion) {
                    mutableState.value = mutableState.value.copy(phase = PathSwapPhase.SpinnerOut)
                    delay(PathSwapTiming.FADE_MILLIS)
                }
                if (mine == revision) mutableState.value = mutableState.value.copy(load = result, shown = target, phase = PathSwapPhase.Content)
            }
        }
    }

    private suspend fun fetch(target: PathSelection): PathLoad = try {
        if (target.display == PathDisplayMode.Image) {
            val image = loadImage(target.instrument, target.difficulty)
            val decoder = decodeImage
            if (decoder == null) PathLoad.Image(image) else PathLoad.Image(image, decoder(image), prepared = true)
        } else {
            PathLoad.Text(loadText(target.instrument, target.difficulty))
        }
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (error: FestivalApiException.HttpStatus) {
        if (error.status == 404) PathLoad.NotGenerated else PathLoad.Failed(ServiceIssue.from(error))
    } catch (error: Exception) {
        PathLoad.Failed(ServiceIssue.from(error))
    }
}

// endregion
