package com.festivalscoretracker.android.presentation

import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

/** Shared publication invalidation hides old results, cancels old work and preserves laziness. */
@OptIn(ExperimentalCoroutinesApi::class)
class PublicationReloadsTest {
    @Test
    fun advancesInvalidateStartedReadsAndCancelOlderWork() = runTest {
        val publication = MutableStateFlow<Int?>(7)
        val held = CompletableDeferred<Unit>()
        var reads = 0
        val refreshes = mutableListOf<Boolean>()
        val loader = RetryingLoader(backgroundScope, "test", ServiceRetryBackoff()) { refresh ->
            reads++
            refreshes += refresh
            val id = publication.value
            if (id == 8) held.await()
            id
        }
        var lazyReads = 0
        val lazy = RetryingLoader(backgroundScope, "lazy", ServiceRetryBackoff()) { lazyReads++; 1 }
        followPublications(backgroundScope, publication) { loader.invalidate(); lazy.invalidate() }
        loader.ensureStarted()
        runCurrent()
        assertEquals(LoadState.Loaded(7), loader.state.value)
        publication.value = 8
        runCurrent()
        assertEquals(LoadState.Loading, loader.state.value)
        publication.value = 9
        runCurrent()
        held.complete(Unit)
        runCurrent()
        assertEquals(LoadState.Loaded(9), loader.state.value)
        assertEquals(listOf(false, true, true), refreshes)
        assertEquals(0, lazyReads)
        publication.value = 9
        runCurrent()
        assertEquals(3, reads)
    }
}
