package com.festivalscoretracker.android.presentation

import androidx.compose.runtime.mutableIntStateOf
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.updateAndGet

// region Modal coverage

/**
 * Counts the Festival dialogs and bottom sheets on screen. Dialogs leave the activity
 * resumed, so the shared backdrop reads this to hold its frame while a modal covers
 * the page instead of animating unseen behind it (issue #83; iOS #28), and the page's
 * decorative loops (marquees, Shop pulses) hold theirs through [covers] (issue #186).
 */
class ModalCoverage {
    private val count = MutableStateFlow(0)
    private val snapshot = mutableIntStateOf(0)

    /** Open modals (never negative); the page is covered while it is above zero. */
    val openCount: StateFlow<Int> = count.asStateFlow()

    /**
     * The same count as Compose snapshot state: a composable that reads it recomposes when a
     * modal opens or closes without collecting [openCount] itself (many list rows read it).
     */
    val openModals: Int get() = snapshot.intValue

    /** Registers an opened modal. */
    fun open() = publish(count.updateAndGet { it + 1 })

    /** Unregisters a closed modal; extra calls are ignored. */
    fun close() = publish(count.updateAndGet { (it - 1).coerceAtLeast(0) })

    /**
     * Whether content enclosed by [depth] Festival modals (0 on a page, 1 inside a sheet or
     * dialog) is covered by a newer modal, so its decorative motion should hold still.
     *
     * @param depth Modals enclosing the content.
     * @return `true` while more modals are open than enclose it.
     */
    fun covers(depth: Int): Boolean = openModals > depth

    private fun publish(value: Int) {
        snapshot.intValue = value
    }

    companion object {
        /** The app's one instance, shared by every modal and the backdrop. */
        val shared = ModalCoverage()
    }
}

// endregion
