package com.festivalscoretracker.android.presentation

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.testing.MainDispatcherRule
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** Issue #616: publication-bound reads catch up in place with a newer observed generation. */
@OptIn(ExperimentalCoroutinesApi::class)
class PublicationCatchUpTest {
    @get:Rule
    val main = MainDispatcherRule()

    @Test
    fun catchUpKeepsContentOnFailureWithoutAnErrorOrCountdown() = runTest(main.dispatcher) {
        var fail = false
        val reads = mutableListOf<Boolean>()
        val loader = RetryingLoader(this, "k", ServiceRetryBackoff()) { refresh ->
            reads += refresh
            if (fail) throw FestivalApiException.HttpStatus(500) else 7
        }
        loader.retry()
        advanceUntilIdle()
        fail = true
        loader.catchUp()
        // Marked refreshing synchronously, so no observer sees the old value as settled.
        assertEquals(LoadState.Loaded(7, refreshing = true), loader.state.value)
        advanceUntilIdle()
        assertEquals(LoadState.Loaded(7), loader.state.value)
        // A catch-up is a plain read: the publication was already observed, so it is not re-read.
        assertEquals(listOf(false, false), reads)
    }

    @Test
    fun pendingOnlyWhileBehindAndUnsettled() {
        assertTrue(PublicationCatchUp.pending(7, 8, null))
        assertTrue(PublicationCatchUp.pending(7, 9, 8))
        assertFalse(PublicationCatchUp.pending(7, 8, 8))
        assertFalse(PublicationCatchUp.pending(8, 8, null))
        assertFalse(PublicationCatchUp.pending(null, 8, null))
        assertFalse(PublicationCatchUp.pending(7, null, null))
    }

    @Test
    fun newerGenerationReReadsOnceAndSettlesWhenStillBehind() = runTest(main.dispatcher) {
        val scope = CoroutineScope(main.dispatcher + SupervisorJob())
        var served = 7
        var reads = 0
        val gate = CompletableDeferred<Unit>()
        val loader = RetryingLoader(scope, "k", ServiceRetryBackoff()) {
            reads++
            if (reads == 2) gate.await()
            served
        }
        val publications = MutableStateFlow<Int?>(7)
        val catchUp = PublicationCatchUp(scope, loader, publications) { it }
        loader.retry()
        advanceUntilIdle()
        assertEquals(1, reads)

        // Another read observes 8: the loader re-reads in place, content kept meanwhile.
        served = 8
        publications.value = 8
        runCurrent()
        assertEquals(2, reads)
        assertEquals(LoadState.Loaded(7, refreshing = true), loader.state.value)
        assertTrue(PublicationCatchUp.pending(7, publications.value, catchUp.settled.value))
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(LoadState.Loaded(8), loader.state.value)
        assertNull(catchUp.settled.value)

        // 9 is observed but the catalogue still answers 8: one attempt, then settle (paused state).
        publications.value = 9
        advanceUntilIdle()
        assertEquals(3, reads)
        assertEquals(9, catchUp.settled.value)
        assertFalse(PublicationCatchUp.pending(8, 9, catchUp.settled.value))

        // A later generation tries again.
        served = 10
        publications.value = 10
        advanceUntilIdle()
        assertEquals(4, reads)
        assertEquals(LoadState.Loaded(10), loader.state.value)
        scope.cancel()
    }

    @Test
    fun failedCatchUpSettlesAndKeepsTheRows() = runTest(main.dispatcher) {
        val scope = CoroutineScope(main.dispatcher + SupervisorJob())
        var fail = false
        val loader = RetryingLoader(scope, "k", ServiceRetryBackoff()) { if (fail) throw FestivalApiException.HttpStatus(503) else 7 }
        val publications = MutableStateFlow<Int?>(7)
        val catchUp = PublicationCatchUp(scope, loader, publications) { it }
        loader.retry()
        advanceUntilIdle()
        fail = true
        publications.value = 8
        advanceUntilIdle()
        assertEquals(LoadState.Loaded(7), loader.state.value)
        assertEquals(8, catchUp.settled.value)
        scope.cancel()
    }
}
