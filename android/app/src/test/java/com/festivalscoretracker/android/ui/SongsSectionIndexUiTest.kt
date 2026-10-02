package com.festivalscoretracker.android.ui

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.click
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.songs.SongSectionIndex
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import java.time.Duration
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Songs #–Z index rail on a short (landscape phone) window, where it can draw only every
 * few letters (issue #48): tapping a drawn letter lands on that letter's section at the
 * top, including far jumps, and the rail's announced section follows at once.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w891dp-h411dp-xxhdpi")
class SongsSectionIndexUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    /** #, A–Z with two synthetic songs each. */
    private val labels = listOf("#") + ('A'..'Z').map { it.toString() }

    private val catalogue: String
        get() {
            val songs = labels.flatMapIndexed { section, label ->
                (1..2).map { n ->
                    val title = if (label == "#") "$n$section Tune" else "${label}tune $n"
                    """{"songId":"s-$section-$n","title":"$title","artist":"Synthetic Artist","year":2020,"durationSeconds":180,"difficulty":{"guitar":2}}"""
                }
            }
            return """{"count":${songs.size},"currentSeason":15,"songs":[${songs.joinToString(",")}]}"""
        }

    private fun settle(millis: Long = 400) {
        repeat(4) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
            rule.waitForIdle()
        }
    }

    private fun waitForTag(tag: String) {
        rule.waitUntil(10_000) {
            settle(100)
            rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun railState(): String? =
        rule.onNodeWithTag("fst.songs.section-index").fetchSemanticsNode().config.getOrNull(SemanticsProperties.StateDescription)

    /** Taps the centre of drawn label [k] of [drawn] equal slots. */
    private fun tapLabel(k: Int, drawn: Int) {
        rule.onNodeWithTag("fst.songs.section-index").performTouchInput {
            click(Offset(width / 2f, height * (k + 0.5f) / drawn))
        }
        settle()
    }

    /** Tag of the first song row below the list's top content edge (the rail sits 56 dp under it). */
    private fun firstVisibleRow(): String? {
        val contentTop = rule.onNodeWithTag("fst.songs.section-index").fetchSemanticsNode().boundsInRoot.top -
            56 * rule.activity.resources.displayMetrics.density
        val isRow = SemanticsMatcher("song row") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("fst.songs.row.") == true }
        return rule.onAllNodes(isRow, useUnmergedTree = true).fetchSemanticsNodes()
            .filter { it.layoutInfo.isPlaced && it.boundsInRoot.bottom > contentTop + 1 }
            .minByOrNull { it.boundsInRoot.top }
            ?.config?.getOrNull(SemanticsProperties.TestTag)
    }

    @Test
    fun farJumpsOnASampledRailLandOnTheTappedLetter() {
        val transport = FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { catalogue }
        }
        val debug = DebugLaunch(stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        rule.setContent { com.festivalscoretracker.android.ui.shell.FestivalApp(container, debug) }
        settle()
        waitForTag("fst.songs.row.s-0-1")
        waitForTag("fst.songs.section-index")

        val rail = rule.onNodeWithTag("fst.songs.section-index").fetchSemanticsNode().boundsInRoot
        val density = rule.activity.resources.displayMetrics.density * rule.activity.resources.configuration.fontScale
        val stride = SongSectionIndex.stride(labels.size, (rail.height / (20 * density)).toInt().coerceAtLeast(2))
        assertTrue("rail must sample labels (stride $stride)", stride >= 3)
        val drawn = (labels.size + stride - 1) / stride

        // Far jump # → the drawn letter at or before P, then back to #, then the last drawn letter.
        val far = (labels.indexOf("P") / stride) * stride
        for (target in listOf(far, 0, (drawn - 2) * stride, stride)) {
            tapLabel(target / stride, drawn)
            assertEquals("tapped ${labels[target]}", labels[target], railState())
            assertEquals("${labels[target]} at the top", "fst.songs.row.s-$target-1", firstVisibleRow())
        }
    }
}
