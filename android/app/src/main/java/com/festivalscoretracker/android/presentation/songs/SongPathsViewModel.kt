package com.festivalscoretracker.android.presentation.songs

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
     */
    data class Image(val image: SongPathImagePayload) : PathLoad

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
 * Paths sheet selection and content.
 *
 * @property instrument Selected chart.
 * @property difficulty Selected difficulty.
 * @property display Image or text.
 * @property load Content for the current selection.
 */
data class SongPathsState(
    val instrument: Instrument,
    val difficulty: PathDifficulty = PathDifficulty.Expert,
    val display: PathDisplayMode = PathDisplayMode.Image,
    val load: PathLoad = PathLoad.Loading,
)

// endregion

// region View model

/**
 * CHOpt Paths: each opening starts at the first path chart, Expert and the saved
 * default display; a newer selection cancels the older request so an old
 * response never paints (web `PathsModal` revision guard).
 *
 * @param instruments Path-capable, visible, charted instruments (non-empty).
 * @param defaultDisplay Saved default display.
 * @param loadImage PNG read `(instrument, difficulty)`.
 * @param loadText Table read `(instrument, difficulty)`.
 */
class SongPathsViewModel(
    val instruments: List<Instrument>,
    defaultDisplay: PathDisplayMode,
    private val loadImage: suspend (Instrument, PathDifficulty) -> SongPathImagePayload,
    private val loadText: suspend (Instrument, PathDifficulty) -> SongPathDataPayload,
) : ViewModel() {
    private val mutableState = MutableStateFlow(SongPathsState(instruments.first(), display = defaultDisplay))
    private var job: Job? = null
    private var revision = 0

    /** Current state. */
    val state: StateFlow<SongPathsState> = mutableState.asStateFlow()

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
        val (instrument, difficulty, display) = mutableState.value
        mutableState.value = mutableState.value.copy(load = PathLoad.Loading)
        job = viewModelScope.launch {
            val result = try {
                if (display == PathDisplayMode.Image) PathLoad.Image(loadImage(instrument, difficulty)) else PathLoad.Text(loadText(instrument, difficulty))
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: FestivalApiException.HttpStatus) {
                if (error.status == 404) PathLoad.NotGenerated else PathLoad.Failed(ServiceIssue.from(error))
            } catch (error: Exception) {
                PathLoad.Failed(ServiceIssue.from(error))
            }
            if (mine == revision) mutableState.value = mutableState.value.copy(load = result)
        }
    }
}

// endregion
