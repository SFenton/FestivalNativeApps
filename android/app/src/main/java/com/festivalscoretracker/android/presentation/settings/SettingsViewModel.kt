package com.festivalscoretracker.android.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Publication
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.settings.MetadataField
import com.festivalscoretracker.android.core.settings.PathColumnKey
import com.festivalscoretracker.android.core.settings.PathDisplayMode
import com.festivalscoretracker.android.core.settings.SettingsOrder
import com.festivalscoretracker.android.data.SettingsRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

// region Service check

/** Settings "Service" section state (a keyless publication + catalogue re-read). */
sealed interface ServiceCheckState {
    /** Not checked yet this session. */
    data object Idle : ServiceCheckState

    /** Re-reading. */
    data object Checking : ServiceCheckState

    /**
     * Up to date.
     *
     * @property publication Current publication.
     * @property songCount Songs in the refreshed catalogue.
     */
    data class Current(val publication: Publication, val songCount: Int) : ServiceCheckState

    /**
     * The check failed.
     *
     * @property issue Shared service issue.
     */
    data class Failed(val issue: ServiceIssue) : ServiceCheckState
}

// endregion

// region View model

/**
 * Settings page actions: every write goes through [SettingsRepository.update]
 * (atomic, sanitized) so Songs, Song Detail, Paths and Leaderboards observe the
 * change through the shared settings flow.
 *
 * @property repository Persisted settings.
 * @param checkService Forced publication + catalogue refresh returning the publication and song count.
 * @param scope Scope for writes (the view model scope by default).
 */
class SettingsViewModel(
    private val repository: SettingsRepository,
    private val checkService: suspend () -> Pair<Publication, Int>,
    scope: CoroutineScope? = null,
) : ViewModel() {
    private val work: CoroutineScope = scope ?: viewModelScope
    private val serviceFlow = MutableStateFlow<ServiceCheckState>(ServiceCheckState.Idle)

    /** Service section state. */
    val service: StateFlow<ServiceCheckState> = serviceFlow.asStateFlow()

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
     * Debug tap diagnostics (clears telemetry when turned off).
     *
     * @param enabled Value.
     */
    fun setTapDiagnostics(enabled: Boolean) = update { it.withTapDiagnostics(enabled) }

    /**
     * Debug tap telemetry (requires diagnostics).
     *
     * @param enabled Value.
     */
    fun setTapTelemetry(enabled: Boolean) = update { it.copy(tapTelemetry = enabled) }

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

    /** Re-read the publication and catalogue (keyless public GETs). */
    fun checkForUpdates() {
        if (serviceFlow.value == ServiceCheckState.Checking) return
        serviceFlow.value = ServiceCheckState.Checking
        work.launch {
            serviceFlow.value = try {
                val (publication, count) = checkService()
                ServiceCheckState.Current(publication, count)
            } catch (error: Throwable) {
                ServiceCheckState.Failed(ServiceIssue.from(error))
            }
        }
    }
}

// endregion
