package com.festivalscoretracker.android.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.serviceinfo.ServiceInfoSnapshot
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.settings.MetadataField
import com.festivalscoretracker.android.core.settings.PathColumnKey
import com.festivalscoretracker.android.core.settings.PathDisplayMode
import com.festivalscoretracker.android.core.settings.SettingsOrder
import com.festivalscoretracker.android.data.SettingsRepository
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

// region Service version

/** Settings → Version "Service Version" (`GET /api/version`, read once per view model). */
sealed interface ServiceVersionState {
    /** Reading. */
    data object Loading : ServiceVersionState

    /**
     * Read.
     *
     * @property version Printable service version.
     */
    data class Loaded(val version: String) : ServiceVersionState

    /** The read failed. */
    data object Unavailable : ServiceVersionState
}

// endregion

// region View model

/**
 * Settings page actions: every write goes through [SettingsRepository.update]
 * (atomic, sanitized) so Songs, Song Detail, Paths and Leaderboards observe the
 * change through the shared settings flow.
 *
 * @property repository Persisted settings.
 * @param readServiceInfo One keyless `/api/service-info` read (Service Info card).
 * @param readServiceVersion One keyless `/api/version` read (Version section).
 * @param scope Scope for writes (the view model scope by default).
 */
class SettingsViewModel(
    private val repository: SettingsRepository,
    readServiceInfo: suspend () -> ServiceInfoSnapshot,
    private val readServiceVersion: suspend () -> String,
    scope: CoroutineScope? = null,
) : ViewModel() {
    private val work: CoroutineScope = scope ?: viewModelScope
    private val versionFlow = MutableStateFlow<ServiceVersionState>(ServiceVersionState.Loading)
    private var versionRequested = false

    /** Live Service Info card; the screen runs [ServiceInfoPoller.poll] only while visible. */
    val serviceInfo = ServiceInfoPoller(readServiceInfo)

    /** Service version for Settings → Version. */
    val serviceVersion: StateFlow<ServiceVersionState> = versionFlow.asStateFlow()

    /** Read the service version once (later calls are no-ops unless the read failed). */
    fun loadServiceVersion() {
        if (versionRequested && versionFlow.value != ServiceVersionState.Unavailable) return
        versionRequested = true
        versionFlow.value = ServiceVersionState.Loading
        work.launch {
            versionFlow.value = try {
                ServiceVersionState.Loaded(readServiceVersion())
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (error: Exception) {
                ServiceVersionState.Unavailable
            }
        }
    }

    private fun update(transform: (AppSettings) -> AppSettings) {
        work.launch { repository.update(transform) }
    }

    /**
     * Show or hide a chart (the last visible one stays on).
     *
     * @param instrument Chart.
     * @param visible Visibility.
     */
    fun setInstrumentVisible(instrument: Instrument, visible: Boolean) = update { it.withInstrumentVisible(instrument, visible) }

    /**
     * Show or hide a metadata field.
     *
     * @param field Field.
     * @param visible Visibility.
     */
    fun setMetadataVisible(field: MetadataField, visible: Boolean) = update { it.withMetadataVisible(field, visible) }

    /**
     * Show Instrument Icons.
     *
     * @param enabled Value.
     */
    fun setShowInstrumentIcons(enabled: Boolean) = update { it.copy(showInstrumentIcons = enabled) }

    /**
     * Independent song-row visual order.
     *
     * @param enabled Value.
     */
    fun setEnableVisualOrder(enabled: Boolean) = update { it.copy(enableVisualOrder = enabled) }

    /**
     * Move one song-row metadata field.
     *
     * @param index Current index.
     * @param offset Places to move.
     */
    fun moveVisualOrder(index: Int, offset: Int) = update { it.copy(songRowVisualOrder = SettingsOrder.move(it.songRowVisualOrder, index, offset)) }

    /**
     * Move one CHOpt text column.
     *
     * @param index Current index.
     * @param offset Places to move.
     */
    fun movePathColumn(index: Int, offset: Int) = update { it.copy(pathColumnOrder = SettingsOrder.move(it.pathColumnOrder, index, offset)) }

    /**
     * Replace the song-row order (drag end).
     *
     * @param order New order.
     */
    fun setVisualOrder(order: List<MetadataField>) = update { it.copy(songRowVisualOrder = order) }

    /**
     * Replace the CHOpt column order (drag end).
     *
     * @param order New order.
     */
    fun setPathColumnOrder(order: List<PathColumnKey>) = update { it.copy(pathColumnOrder = order) }

    /**
     * CHOpt path default view.
     *
     * @param mode Image or text.
     */
    fun setPathDefaultView(mode: PathDisplayMode) = update { it.copy(pathDefaultView = mode) }

    /**
     * Filter Invalid Scores.
     *
     * @param enabled Value.
     */
    fun setFilterInvalidScores(enabled: Boolean) = update { it.copy(filterInvalidScores = enabled) }

    /**
     * Enable Experimental Leaderboard Ranks (web `enableExperimentalRanks`).
     *
     * @param enabled Value.
     */
    fun setExperimentalRanks(enabled: Boolean) = update { it.copy(experimentalRanks = enabled) }

    /**
     * Invalid-score leeway (clamped and rounded on save).
     *
     * @param value Percent.
     */
    fun setLeeway(value: Double) = update { it.copy(leeway = value) }

    /**
     * Hide Item Shop.
     *
     * @param enabled Value.
     */
    fun setHideShop(enabled: Boolean) = update { it.copy(hideShop = enabled) }

    /**
     * Disable Item Shop Highlighting.
     *
     * @param enabled Value.
     */
    fun setDisableShopHighlighting(enabled: Boolean) = update { it.copy(disableShopHighlighting = enabled) }

    /**
     * Reduce Motion override.
     *
     * @param enabled Value.
     */
    fun setReduceMotion(enabled: Boolean) = update { it.copy(reduceMotion = enabled) }

    /**
     * Still artwork override.
     *
     * @param enabled Value.
     */
    fun setDisableAnimatedArtwork(enabled: Boolean) = update { it.copy(disableAnimatedArtwork = enabled) }

    /**
     * Increase Contrast override.
     *
     * @param enabled Value.
     */
    fun setIncreaseContrast(enabled: Boolean) = update { it.copy(increaseContrast = enabled) }

    /**
     * Reduce Transparency override.
     *
     * @param enabled Value.
     */
    fun setReduceTransparency(enabled: Boolean) = update { it.copy(reduceTransparency = enabled) }

    /** Confirmed Reset: app settings only. */
    fun resetAppSettings() {
        work.launch { repository.resetAppSettings() }
    }
}

// endregion
