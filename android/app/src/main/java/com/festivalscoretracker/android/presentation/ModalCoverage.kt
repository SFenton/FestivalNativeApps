package com.festivalscoretracker.android.presentation

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

// region Modal coverage

/**
 * Counts the Festival dialogs and bottom sheets on screen. Dialogs leave the activity
 * resumed, so the shared backdrop reads this to hold its frame while a modal covers
 * the page instead of animating unseen behind it (issue #83; iOS #28).
 */
class ModalCoverage {
    private val count = MutableStateFlow(0)

    /** Open modals (never negative); the page is covered while it is above zero. */
    val openCount: StateFlow<Int> = count.asStateFlow()

    /** Registers an opened modal. */
    fun open() = count.update { it + 1 }

    /** Unregisters a closed modal; extra calls are ignored. */
    fun close() = count.update { (it - 1).coerceAtLeast(0) }

    companion object {
        /** The app's one instance, shared by every modal and the backdrop. */
        val shared = ModalCoverage()
    }
}

// endregion
