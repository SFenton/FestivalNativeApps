package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.click
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import com.festivalscoretracker.android.ui.leaderboards.ColumnProbe
import com.festivalscoretracker.android.ui.leaderboards.LocalColumnProbe
import java.time.LocalDate
import java.util.concurrent.ConcurrentHashMap
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Leaderboards Rank History draws every row's rank and value, the bold newest row's and the
 * tapped bar's detail included, in one right-aligned column each measured over the whole
 * chart (issue #594, `leaderboard-row` R11, web `RankHistoryChart`): the columns line up on a
 * device at 100% and 200% text, TalkBack reads the rows newest first, and ATF passes
 * (`device.py test com.festivalscoretracker.android.journeys.RankHistoryAlignmentAccessibilityJourneyTest --avd …`).
 */
@DeviceCi
@RunWith(AndroidJUnit4::class)
class RankHistoryAlignmentAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val tag = "fst.leaderboards.rank-history"
    private val bounds = ConcurrentHashMap<String, Rect>()
    private val probe = ColumnProbe { key, rect -> bounds[key] = rect }

    /** Total Score ranks of one to three digits (values from 100,000 to 89,300,000), newest last. */
    private val ranks = listOf(7, 899, 98, 40)

    /** Asserts the rows' and the detail's rank and value columns share their left and right edges. */
    private fun assertAligned(screen: String) {
        val keys = (0 until ranks.size).map { "leaderboards.row.$it" } + "leaderboards.detail.row"
        listOf("rank", "value").forEach { column ->
            val edges = keys.map { key -> bounds["history.$column.$key"] ?: error("$screen: no $column for $key in ${bounds.keys}") }
            edges.drop(1).forEachIndexed { i, other ->
                assertEquals("$screen: $column right, ${keys[i + 1]}", edges.first().right, other.right, 1.5f)
                assertEquals("$screen: $column left, ${keys[i + 1]}", edges.first().left, other.left, 1.5f)
            }
        }
    }

    /** Asserts TalkBack reads the visible rows newest first, each as one stop with its rank. */
    private fun assertReadingOrder(screen: String) {
        val stops = h.readingStops(screen, fresh = true)
        val order = stops.map { "${it.id}: ${it.label}" }
        val rows = (0 until ranks.size).map { i -> stops.indexOfFirst { it.id == "$tag.row.$i" } }.filter { it >= 0 }
        assertTrue("$screen: rows in $order", rows.size >= 2)
        assertEquals("$screen: rows read newest first in $order", rows.sorted(), rows)
        val newest = stops[rows.first()].label
        assertTrue("$screen: newest row reads its rank: $newest", newest.contains("rank #40"))
    }

    @Test
    fun rankHistoryColumnsAlignAtDefaultAndLargeText() {
        h.enableAccessibilityChecks()
        var scale by mutableFloatStateOf(1f)
        val today = LocalDate.now()
        val days = ranks.mapIndexed { i, rank -> today.minusDays((ranks.size - 1 - i).toLong()).toString() to rank }
        val transport = RankingsFixtures.install(
            FakeTransport.standard().apply {
                on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
            },
        ).apply {
            onRaw("/api/rankings/Solo_Guitar/${RankingsFixtures.SELECTED}/history") {
                HttpResult(200, RankingsFixtures.rankHistory("Solo_Guitar", days = days).toByteArray(), mapOf("X-FST-Publication-Id" to "7"))
            }
        }
        h.launch(
            DebugLaunch(route = DebugLaunch.parseRoute("leaderboards"), profile = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player"), stillBackground = true),
            transport,
            fontScale = { scale },
            wrap = { content -> CompositionLocalProvider(LocalColumnProbe provides probe) { content() } },
        )
        h.waitForTag("$tag.row.${ranks.size - 1}")
        h.scrollTo("fst.leaderboards", "$tag.plot")
        // The oldest bar's detail (rank #7) uses the same columns as the rows.
        rule.onNodeWithTag("$tag.plot").performTouchInput { click(centerLeft.copy(x = 4f)) }
        h.waitForTag("$tag.detail")
        h.scrollTo("fst.leaderboards", "$tag.row.${ranks.size - 1}")
        rule.waitForIdle()
        assertAligned("rank-history")
        assertReadingOrder("rank-history")

        // 200% text: the columns keep one width, nothing clips, the date moves above when needed.
        scale = 2f
        rule.waitForIdle()
        h.scrollTo("fst.leaderboards", "$tag.row.${ranks.size - 1}")
        rule.waitForIdle()
        if (!h.exists("$tag.detail")) {
            h.scrollTo("fst.leaderboards", "$tag.plot")
            rule.onNodeWithTag("$tag.plot").performTouchInput { click(centerLeft.copy(x = 4f)) }
            h.waitForTag("$tag.detail")
            h.scrollTo("fst.leaderboards", "$tag.row.${ranks.size - 1}")
            rule.waitForIdle()
        }
        assertAligned("rank-history-200")
        assertReadingOrder("rank-history-200")
        h.assertAccessible()
    }
}
