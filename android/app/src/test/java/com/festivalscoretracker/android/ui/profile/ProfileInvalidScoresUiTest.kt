package com.festivalscoretracker.android.ui.profile

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import java.net.URI
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** The rendered non-selected profile updates values and percentile rows in place. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class ProfileInvalidScoresUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()
    private val h = ProfileJourney(rule)

    @Test
    fun nonSelectedProfileShowsFilteredRanksAndRestoresRawRanksWithoutReloading() {
        h.transport.on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { ProfileFixtures.invalidScoresSongs }
        h.transport.on("/api/player/${Fixtures.ACCOUNT_A}", headers = mapOf("X-FST-Publication-Id" to "7")) { ProfileFixtures.invalidScoresProfile() }
        h.launch(DebugLaunch(
            profile = SelectedPlayer(Fixtures.ACCOUNT_B, "Other Player"),
            route = PlayerRoute(Fixtures.ACCOUNT_A),
            stillBackground = true,
        ))
        runBlocking { h.container.settings.update { it.copy(visibleInstruments = setOf(Instrument.Lead)) } }
        h.scrollTo(BEST_RANK)
        rule.onNodeWithTag(BEST_RANK).assertContentDescriptionEquals("Best Song Rank: #1")
        val reads = profileReads()

        update(enabled = true, leeway = 1.0)
        rule.onNodeWithTag(BEST_RANK).assertContentDescriptionEquals("Best Song Rank: #6")
        h.scrollTo("fst.player.percentile-row.10")
        rule.onNodeWithTag("fst.player.percentile-row.10").assertContentDescriptionEquals("Top 10%: 1 song")

        update(enabled = true, leeway = 2.0)
        h.scrollTo("fst.player.percentile-row.4")
        rule.onNodeWithTag("fst.player.percentile-row.4").assertContentDescriptionEquals("Top 4%: 1 song")
        h.scrollTo("fst.player.top-song.Solo_Guitar.s-alpha")
        rule.onNodeWithTag("fst.player.top-song.Solo_Guitar.s-alpha").assertContentDescriptionEquals("s-alpha, Synthetic Artist, Top 4%")

        update(enabled = false, leeway = 2.0)
        h.scrollTo(BEST_RANK)
        rule.onNodeWithTag(BEST_RANK).assertContentDescriptionEquals("Best Song Rank: #1")
        assertEquals(reads, profileReads())
        assertEquals(Fixtures.ACCOUNT_B, h.container.selectedProfile.state.value.player?.accountId)
    }

    private fun update(enabled: Boolean, leeway: Double) {
        runBlocking { h.container.settings.update { it.copy(filterInvalidScores = enabled, leeway = leeway) } }
        h.settle()
    }

    private fun profileReads() = h.transport.requests.count { URI(it.url).path == "/api/player/${Fixtures.ACCOUNT_A}" }

    private companion object {
        const val BEST_RANK = "fst.player.tile.overview.best-rank"
    }
}
