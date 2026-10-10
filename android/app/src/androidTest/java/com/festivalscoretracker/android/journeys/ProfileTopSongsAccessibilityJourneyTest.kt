package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Issue #595: on a player profile each chart's Top Five Songs and Bottom Five Songs are two
 * cards, each with its title and description above it (`section-headers` R2). At 1.0x and 2.0x
 * text, for each list:
 * - the title is a heading, outside its card, grown and unclipped;
 * - TalkBack reads the title, then its description, then that card's rows, and every Top Five
 *   row before the Bottom Five title;
 * - rows are 48 dp buttons;
 * - a chart with no ranked score keeps its one "No Scores Yet" card.
 *
 * ATF runs on every step. Fixtures only; `@DeviceCi` and the `android-device` job run it. Run with
 * `device.py test com.festivalscoretracker.android.journeys.ProfileTopSongsAccessibilityJourneyTest
 * --avd FST_Phone`; reading orders go to logcat `FST_A11Y`.
 */
@RunWith(AndroidJUnit4::class)
@DeviceCi
class ProfileTopSongsAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    /** Songs and a profile with seven ranked Lead scores (both lists), one Bass and no Drums score. */
    private fun transport() = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        ProfileFixtures.register(this)
        on("/api/player/${Fixtures.ACCOUNT_A}", headers = mapOf("X-FST-Publication-Id" to "7")) {
            ProfileFixtures.profile(rows = ProfileFixtures.topAndBottomRows)
        }
    }

    /** Both lists at 100% text. */
    @Test
    fun topAndBottomFiveAreTitledCardsAtDefaultText() = journey(1f)

    /** The same at 200% text: titles grow unclipped and rows stay 48 dp. */
    @Test
    fun topAndBottomFiveAreTitledCardsAtDoubleText() = journey(2f)

    private fun journey(scale: Float) {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = PLAYER, route = PlayerRoute(Fixtures.ACCOUNT_A), stillBackground = true), transport(), fontScale = { scale })
        h.waitForTag("fst.player.overview")
        h.publishTalkBackTree()
        LISTS.forEach { list ->
            val screen = "top-songs-${list.kind} ${scale}x"
            val header = "fst.player.${list.kind}-songs-header.Solo_Guitar"
            val card = "fst.player.${list.kind}-songs-card.Solo_Guitar"
            val rowPrefix = "fst.player.${list.kind}-song.Solo_Guitar."
            h.scrollTo(LIST, header)
            h.scrollTo(LIST, "$rowPrefix${list.firstSong}")
            rule.onAllNodes(hasText(list.title) and hasAnyAncestor(hasTestTag(card)), useUnmergedTree = true).assertCountEquals(0)
            rule.onAllNodes(hasText(list.description) and hasAnyAncestor(hasTestTag(card)), useUnmergedTree = true).assertCountEquals(0)
            h.assertTextUnclipped(screen, header, list.title, scale)
            val stops = h.readingStops(screen, fresh = true)
            val title = stops.indexOfFirst { it.label == list.title }
            assertTrue("$screen: \"${list.title}\" is read as a heading: ${stops.map { it.label }}", title >= 0 && stops[title].isHeading)
            assertTrue("$screen: the description follows its title", stops.getOrNull(title + 1)?.label == list.description)
            val rows = stops.withIndex().filter { it.value.id?.startsWith(rowPrefix) == true }
            assertTrue("$screen: its rows are read after the description: ${stops.map { it.label }}", rows.isNotEmpty() && rows.all { it.index > title + 1 })
            if (list.kind == "bottom") {
                val earlier = stops.withIndex().filter { it.value.id?.startsWith("fst.player.top-song.Solo_Guitar.") == true }
                assertTrue("$screen: Top Five rows precede the Bottom Five title", earlier.all { it.index < title })
            }
            h.assertTouchTarget(screen, "$rowPrefix${list.firstSong}")
        }
        h.scrollTo(LIST, "fst.player.top-songs-empty.Solo_Drums")
        h.readingOrder("top-songs-empty ${scale}x", fresh = true).let { order ->
            assertTrue("No Scores Yet is read: $order", order.any { it.startsWith("No Scores Yet") })
        }
        h.assertAccessible()
    }

    /** One titled list: its test-tag kind, title, description and first row's song. */
    private data class SongList(val kind: String, val title: String, val description: String, val firstSong: String)

    private companion object {
        val PLAYER = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")
        const val LIST = "fst.player.available"
        val LISTS = listOf(
            SongList("top", "Top Five Songs", "Synthetic Player's top ranked competitive songs on Lead, sorted by percentile.", "s-alpha"),
            SongList("bottom", "Bottom Five Songs", "Synthetic Player's lowest-ranked competitive songs on Lead, sorted by percentile.", "s-gamma"),
        )
    }
}
