package com.festivalscoretracker.android.journeys

import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.common.LARGE_TEXT_SCALE
import kotlin.math.abs
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The score-accuracy control on a device (`.agents/controls/score-accuracy/android.md`): the
 * Song Detail preview and the full chart with graded, full-combo, full-combo-without-accuracy
 * and absent rows. Checks ATF (contrast, labels, touch targets), that each row's TalkBack
 * stop includes its badge, that badges share one column, and that none straddles a hinge
 * (`device.py test com.festivalscoretracker.android.journeys.ScoreAccuracyJourneyTest --avd …`).
 */
@RunWith(AndroidJUnit4::class)
class ScoreAccuracyJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val graded = "abcdefabcdefabcdefabcdefabcdef01"
    private val missing = "abcdefabcdefabcdefabcdefabcdef02"
    private val absent = "abcdefabcdefabcdefabcdefabcdef03"
    private val low = "abcdefabcdefabcdefabcdefabcdef04"
    private val board = """{"songId":"s-alpha","instrument":"Solo_Guitar","count":5,"totalEntries":5,"localEntries":5,"entries":[
      {"accountId":"${Fixtures.ACCOUNT_B}","displayName":"Combo Player","score":99999,"rank":1,"accuracy":1000000,"isFullCombo":true},
      {"accountId":"$graded","displayName":"Graded Player","score":99998,"rank":2,"accuracy":873000,"isFullCombo":false},
      {"accountId":"$missing","displayName":"Missing Player","score":99997,"rank":3,"isFullCombo":true},
      {"accountId":"$absent","displayName":"Absent Player","score":99996,"rank":4},
      {"accountId":"$low","displayName":"Low Player","score":99995,"rank":5,"accuracy":120000,"isFullCombo":false}]}"""
    private val transport = FakeTransport.standard().apply {
        on("/api/leaderboard/s-alpha/Solo_Guitar", headers = mapOf("X-FST-Publication-Id" to "7")) { board }
    }

    private fun tag(id: String) = "fst.score.accuracy.$id"

    private fun badgeCentres(ids: List<String>): List<Float> = ids.map { id ->
        rule.onAllNodesWithTag(tag(id), useUnmergedTree = true).fetchSemanticsNodes().first().boundsInWindow.let { (it.left + it.right) / 2 }
    }

    /**
     * Asserts the badge column, hinge clearance and TalkBack labels for the current screen.
     *
     * @param screen Name for the reading-order log.
     * @param leftDetail A stop of the screen navigated away from that must no longer be read.
     */
    private fun assertBadges(screen: String, leftDetail: String? = null) {
        val badges = listOf(Fixtures.ACCOUNT_B, graded, missing, low)
        badges.forEach { h.waitForTag(tag(it)) }
        assertTrue("absent row drew a badge", !h.exists(tag(absent)))
        // Below LARGE_TEXT_SCALE badges share a column (aligned-columns); at large text rows stack
        // and each badge follows its score (large-text), so the column check applies only below it.
        if (rule.activity.resources.configuration.fontScale < LARGE_TEXT_SCALE) {
            val centres = badgeCentres(badges)
            assertTrue("$screen badges ragged: $centres", centres.all { abs(it - centres.first()) < 1f })
        }
        h.assertNothingStraddles(*badges.map(::tag).toTypedArray())
        val labels = listOf("Full combo, accuracy 100%", "Accuracy 87.3%", "Full combo; accuracy unavailable", "Accuracy 12%")
        // The accessibility tree trails Compose's semantics after a navigation, so re-walk until it shows this screen.
        fun settled(order: List<String>) = labels.all { label -> order.any { it.contains(label) } } && (leftDetail == null || order.none { it == leftDetail })
        val deadline = SystemClock.uptimeMillis() + 10_000
        var order = h.readingOrder(screen)
        while (!settled(order) && SystemClock.uptimeMillis() < deadline) {
            Thread.sleep(250)
            order = h.readingOrder(screen)
        }
        leftDetail?.let { stale -> assertTrue("$screen still reads the outgoing \"$stale\" stop: $order", order.none { it == stale }) }
        labels.forEach { label ->
            assertTrue("$screen: no stop reads \"$label\" in $order", order.any { it.contains(label) })
        }
    }

    @Test
    fun previewAndFullChart() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), songQuery = "s-alpha", stillBackground = true), transport)
        h.waitForTag("fst.song-detail.list")
        h.scrollTo("fst.song-detail.list", "fst.song-detail.view-all.Solo_Guitar")
        assertBadges("score-accuracy-preview")
        h.tap("fst.song-detail.view-all.Solo_Guitar")
        h.waitForTag("fst.song-leaderboard.list")
        // The preview rows share badge tags with the chart's, so wait out the outgoing Song Detail.
        h.waitGone("fst.song-detail.list")
        h.waitForTag("fst.song-leaderboard.row.$low")
        assertBadges("score-accuracy-full-chart", leftDetail = "Intensity")
        h.assertAccessible()
    }
}
