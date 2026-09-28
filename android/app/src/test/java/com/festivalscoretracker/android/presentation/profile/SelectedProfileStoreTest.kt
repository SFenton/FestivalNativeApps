package com.festivalscoretracker.android.presentation.profile

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.profile.PlayerProfilePayload
import com.festivalscoretracker.android.core.profile.PlayerProfileResponse
import com.festivalscoretracker.android.core.profile.PlayerProfileState
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SelectedProfileStoreTest {
    private val playerA = SelectedPlayer(Fixtures.ACCOUNT_A, "Player A")
    private val playerB = SelectedPlayer(Fixtures.ACCOUNT_B, "Player B")

    private fun payload(account: String, observed: Int = 7, state: PlayerProfileState = PlayerProfileState.Available) = PlayerProfilePayload(
        FestivalApi.JSON.decodeFromString(PlayerProfileResponse.serializer(), ProfileFixtures.profile(account)),
        state,
        observed,
        observed,
    )

    private var harness: Harness? = null

    @org.junit.After
    fun tearDown() {
        harness?.close()
    }

    private class Harness(scope: TestScope) {
        val reads = mutableListOf<String>()
        val publications = MutableStateFlow<Int?>(7)
        val players = MutableStateFlow<SelectedPlayer?>(null)
        var respond: suspend (String) -> PlayerProfilePayload = { error("unset") }
        val store = SelectedProfileStore({ reads += it; respond(it) }, publications, ServiceRetryBackoff())

        val job = Job()

        init {
            store.start(CoroutineScope(scope.coroutineContext + job), players)
        }

        fun close() = job.cancel()
    }

    @Test
    fun loadsSwitchesAndClearsOnDeselect() = runTest {
        val h = Harness(this).also { harness = it }
        h.respond = { payload(it) }
        runCurrent()
        assertEquals(SelectedProfileStatus.None, h.store.state.value.status)
        h.players.value = playerA
        advanceUntilIdle()
        val loaded = h.store.state.value
        assertEquals(SelectedProfileStatus.Available, loaded.status)
        assertEquals(7, loaded.observedPublicationId)
        assertEquals(3, loaded.scoreIndex!!.size)
        assertTrue(loaded.load is LoadState.Loaded)

        h.players.value = playerA.copy(displayName = "Renamed")
        advanceUntilIdle()
        assertEquals(1, h.reads.size)
        assertEquals("Renamed", h.store.state.value.player?.displayName)

        h.players.value = playerB
        runCurrent()
        assertEquals(Fixtures.ACCOUNT_B, h.store.state.value.player?.accountId)
        advanceUntilIdle()
        assertTrue(h.store.state.value.payload!!.belongsTo(Fixtures.ACCOUNT_B))

        h.players.value = null
        advanceUntilIdle()
        assertEquals(SelectedProfileState(), h.store.state.value)
    }

    @Test
    fun seedAvoidsASecondReadAndSyncingIsNeverEmptySuccess() = runTest {
        val h = Harness(this).also { harness = it }
        runCurrent()
        h.store.seed(playerA, payload(Fixtures.ACCOUNT_A, state = PlayerProfileState.Syncing))
        h.players.value = playerA
        advanceUntilIdle()
        assertTrue(h.reads.isEmpty())
        assertEquals(SelectedProfileStatus.Syncing, h.store.state.value.status)
        assertNull(h.store.state.value.scoreIndex)
        h.store.seed(playerB, payload(Fixtures.ACCOUNT_A))
        assertEquals(Fixtures.ACCOUNT_A, h.store.state.value.player?.accountId)
    }

    @Test
    fun failureRetryAndPublicationAdvance() = runTest {
        val h = Harness(this).also { harness = it }
        h.respond = { throw FestivalApiException.HttpStatus(403) }
        h.players.value = playerA
        advanceUntilIdle()
        val failed = h.store.state.value
        assertEquals(SelectedProfileStatus.Failed, failed.status)
        assertTrue(failed.load is LoadState.Failed)
        assertNull(failed.scoreIndex)

        h.respond = { payload(it) }
        h.store.retry()
        advanceUntilIdle()
        assertEquals(SelectedProfileStatus.Available, h.store.state.value.status)

        h.respond = { payload(it, observed = 8) }
        h.publications.value = 8
        advanceUntilIdle()
        assertEquals(8, h.store.state.value.observedPublicationId)
        assertEquals(3, h.reads.size)
    }

    @Test
    fun scrapeFreezeCountsDownAndRetries() = runTest {
        val h = Harness(this).also { harness = it }
        var attempts = 0
        h.respond = {
            attempts++
            if (attempts == 1) throw FestivalApiException.PublicReadFrozen("scrape", "2") else payload(it)
        }
        h.players.value = playerA
        runCurrent()
        val frozen = h.store.state.value
        assertEquals(SelectedProfileStatus.Failed, frozen.status)
        assertTrue(frozen.issue is ServiceIssue.ScrapeInProgress)
        assertTrue((frozen.countdown ?: 0) > 0)
        advanceTimeBy(60_000)
        advanceUntilIdle()
        assertEquals(SelectedProfileStatus.Available, h.store.state.value.status)
    }

    @Test
    fun lateReadForAPreviousAccountIsDropped() = runTest {
        val h = Harness(this).also { harness = it }
        val gate = CompletableDeferred<Unit>()
        h.respond = { account -> if (account == Fixtures.ACCOUNT_A) gate.await(); payload(account) }
        h.players.value = playerA
        runCurrent()
        h.players.value = playerB
        advanceUntilIdle()
        gate.complete(Unit)
        advanceUntilIdle()
        assertTrue(h.store.state.value.payload!!.belongsTo(Fixtures.ACCOUNT_B))
    }
}
