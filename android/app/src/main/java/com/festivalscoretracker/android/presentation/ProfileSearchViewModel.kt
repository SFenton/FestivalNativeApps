package com.festivalscoretracker.android.presentation

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.festivalscoretracker.android.core.model.PlayerSearchResult
import com.festivalscoretracker.android.core.model.ProfileSearchText
import com.festivalscoretracker.android.core.service.ServiceIssue
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.stateIn

// region Profile search

/**
 * Profile search targets. The Bands target requests nothing: selecting a band as the
 * profile isn't supported yet, and global search is where bands are found (issue #320).
 *
 * @property label Segment label.
 * @property placeholder Search field prompt.
 */
enum class ProfileSearchScope(val label: String, val placeholder: String) {
    /** Keyless account search. */
    Players("Players", "Find Player"),

    /** Blocked; shown with an explanation. */
    Bands("Bands", "Find Band"),
}

/** Find Player results state. */
sealed interface ProfileSearchState {
    /** Bands target: search is unavailable and no request is made. */
    data object BandsUnavailable : ProfileSearchState

    /** Fewer than two characters: show the centered "Enter at least 2 characters" hint. */
    data object Hint : ProfileSearchState

    /** Search in flight. */
    data object Searching : ProfileSearchState

    /**
     * Results (possibly empty — never proof of no match).
     *
     * @property results Valid results.
     */
    data class Results(val results: List<PlayerSearchResult>) : ProfileSearchState

    /**
     * Search failed.
     *
     * @property issue Classified failure.
     */
    data class Failed(val issue: ServiceIssue) : ProfileSearchState
}

/**
 * Debounced keyless account search for the profile sheet.
 *
 * @param search Search read (`FestivalApi.searchPlayers`).
 */
@OptIn(FlowPreview::class, ExperimentalCoroutinesApi::class)
class ProfileSearchViewModel(private val search: suspend (String) -> List<PlayerSearchResult>) : ViewModel() {
    private val text = MutableStateFlow("")
    private val attempt = MutableStateFlow(0)
    private val target = MutableStateFlow(ProfileSearchScope.Players)

    /** Players or Bands. */
    val scope: StateFlow<ProfileSearchScope> = target.asStateFlow()

    /** Raw field text. */
    val query: StateFlow<String> = text.asStateFlow()

    /** Results for the debounced, trimmed query. */
    val state: StateFlow<ProfileSearchState> = combine(text.debounce(SEARCH_DEBOUNCE_MS), attempt, target) { raw, _, scope -> raw to scope }
        .flatMapLatest { (raw, scope) ->
            val trimmed = raw.trim()
            flow {
                if (scope == ProfileSearchScope.Bands) {
                    emit(ProfileSearchState.BandsUnavailable)
                    return@flow
                }
                if (trimmed.length < ProfileSearchText.MIN_QUERY || !ProfileSearchText.isValidQuery(trimmed)) {
                    emit(ProfileSearchState.Hint)
                    return@flow
                }
                emit(ProfileSearchState.Searching)
                val result = try {
                    ProfileSearchState.Results(search(trimmed))
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (error: Exception) {
                    ProfileSearchState.Failed(ServiceIssue.from(error))
                }
                emit(result)
            }
        }
        .stateIn(viewModelScope, SharingStarted.Eagerly, ProfileSearchState.Hint)

    /**
     * Update the field.
     *
     * @param value New text.
     */
    fun onQueryChange(value: String) {
        text.value = value
    }

    /**
     * Choose the search target.
     *
     * @param scope Players or Bands.
     */
    fun setScope(scope: ProfileSearchScope) {
        target.value = scope
    }

    /** Re-run the current query after a failure or an empty result. */
    fun retry() {
        attempt.value++
    }

    companion object {
        /** Keystroke debounce before a search GET (web `useUnifiedSearch`: 250 ms). */
        const val SEARCH_DEBOUNCE_MS = 250L
    }
}

// endregion
