package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.espresso.Espresso
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.testing.BandFixtures
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.testing.SongsFixtures
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Accessibility journeys over the Songs area: Songs with its Sort/Filter sheets, Song Detail
 * (band previews, Quick Links), the full song board, Paths, Item Shop and Suggestions. ATF runs
 * on every screen and interaction; reading orders go to logcat `FST_A11Y`
 * (`device.py test com.festivalscoretracker.android.journeys.SongsAccessibilityJourneyTest --avd …`).
 */
@RunWith(AndroidJUnit4::class)
class SongsAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")
    private val transport = BandFixtures.install(
        FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
            on("/api/shop", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.shopJson.replace("\"b.jpg\"", "null") }
            on("/api/paths/s-alpha/Solo_Guitar/expert/data", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.pathJson }
            ProfileFixtures.register(this)
        },
    )

    @Test
    fun songsListSortAndFilter() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = player, stillBackground = true), transport)
        h.waitForTag("fst.songs.list")
        h.readingOrder("songs")
        h.tap("fst.songs.sort.open")
        h.waitForTag("fst.songs.sort")
        h.readingOrder("songs-sort")
        Espresso.pressBack()
        h.waitGone("fst.songs.sort")
        h.tap("fst.songs.filter.open")
        h.waitForTag("fst.songs.filter")
        h.readingOrder("songs-filter")
        h.assertAccessible()
    }

    /** Sort states on a device (issue #125): live mode/direction/Reset, Item Shop sections and the spoken sort state. */
    @Test
    fun songsSortStates() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = player, stillBackground = true), transport)
        h.waitForTag("fst.songs.list")
        rule.onNodeWithTag("fst.songs.sort.open").assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Title, ascending"))
        h.tap("fst.songs.sort.open")
        h.waitForTag("fst.songs.sort.form")
        h.tap("fst.songs.sort.artist")
        rule.onNodeWithTag("fst.songs.sort.artist").assertIsSelected()
        h.tap("fst.songs.sort.descending")
        rule.onNodeWithTag("fst.songs.sort.descending").assertIsSelected()
        h.readingOrder("songs-sort-changed")
        h.tap("fst.songs.sort.reset")
        rule.onNodeWithTag("fst.songs.sort.title").assertIsSelected()
        rule.onNodeWithTag("fst.songs.sort.ascending").assertIsSelected()
        h.tap("fst.songs.sort.shop")
        h.tap("fst.songs.sort.done")
        h.waitGone("fst.songs.sort.form")
        h.waitForTag("fst.songs.shop-section.leaving-tomorrow")
        rule.onNodeWithTag("fst.songs.sort.open").assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Item Shop, ascending"))
        h.readingOrder("songs-sort-shop")
        h.assertAccessible()
    }

    @Test
    fun songDetailBoardAndPaths() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = player, songQuery = "s-alpha", stillBackground = true), transport)
        h.waitForTag("fst.song-detail.list")
        h.waitForTag("fst.song-detail.intensity")
        h.readingOrder("song-detail")
        h.assertNothingStraddles("fst.song-detail.intensity", "fst.song-detail.history", "fst.song-detail.preview.Solo_Guitar")
        h.scrollTo("fst.song-detail.list", "fst.song-detail.band-preview.Band_Duets")
        h.readingOrder("song-detail-bands")
        h.tap("fst.quick-links.open")
        h.readingOrder("song-detail-quick-links")
        h.tap("fst.quick-links.item.intensity")
        h.tap("fst.song-detail.paths.open")
        h.waitForTag("fst.paths.difficulty.open")
        h.readingOrder("paths")
        if (h.exists("fst.paths.karaoke-warning")) {
            h.tap("fst.paths.warning.ok")
            h.waitGone("fst.paths.karaoke-warning")
            h.readingOrder("paths-sheet")
        }
        h.tap("fst.paths.close")
        h.waitGone("fst.paths.close")
        h.scrollTo("fst.song-detail.list", "fst.song-detail.view-all.Solo_Guitar")
        h.tap("fst.song-detail.view-all.Solo_Guitar")
        h.waitForTag("fst.song-leaderboard.list")
        h.readingOrder("song-leaderboard")
        h.assertAccessible()
    }

    @Test
    fun itemShop() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(route = DebugLaunch.parseRoute("shop"), profile = player, stillBackground = true), transport)
        rule.waitUntil(15_000) { h.exists("fst.shop.list") || h.exists("fst.shop.grid") }
        h.readingOrder("shop")
        // Grid/List only switches on wide panes (compact phones always list).
        if (h.exists("fst.shop.view-toggle")) {
            h.tap("fst.shop.view-toggle")
            h.readingOrder("shop-toggled")
        }
        h.assertAccessible()
    }

    @Test
    fun suggestions() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(section = FestivalSection.Suggestions, profile = player, stillBackground = true), transport)
        h.waitForTag("fst.suggestions.filter-button")
        h.readingOrder("suggestions")
        h.tap("fst.suggestions.filter-button")
        h.waitForTag("fst.suggestions.filter.form")
        h.readingOrder("suggestions-filter")
        h.assertAccessible()
    }
}
