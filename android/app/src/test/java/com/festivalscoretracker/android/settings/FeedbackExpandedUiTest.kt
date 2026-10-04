package com.festivalscoretracker.android.settings

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.assertWidthIsEqualTo
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.feedback.FeedbackProblem
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import okhttp3.OkHttpClient
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** The feedback form on an expanded window: a centred dialog capped at 640 dp, not full screen (issue #143). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w1280dp-h800dp-land-xhdpi")
class FeedbackExpandedUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val transport = FakeTransport.standard().apply {
        on("/api/service-info") { """{"contractVersion":2}""" }
        on("/api/version") { """{"version":"9.9.9"}""" }
        on("/api/features") { """{"appManual":false,"feedback":true}""" }
    }

    private fun settle(millis: Long = 400) = repeat(4) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
        rule.waitForIdle()
    }

    private fun waitFor(tag: String, gone: Boolean = false) = rule.waitUntil(10_000) {
        settle(100)
        rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isEmpty() == gone
    }

    @Test
    fun expandedWindowShowsACentredCappedDialog() {
        val debug = DebugLaunch(section = FestivalSection.Settings, stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        waitFor("fst.settings.list")
        rule.waitUntil(10_000) { settle(100); transport.sent("/api/features").isNotEmpty() }
        settle()
        rule.onNodeWithTag("fst.settings.list").performScrollToNode(hasTestTag("fst.settings.feedback.feature"))
        rule.onNodeWithTag("fst.settings.feedback.feature").performSemanticsAction(SemanticsActions.OnClick)
        waitFor("fst.settings.feedback.dialog")

        rule.onNodeWithTag("fst.settings.feedback.dialog").assertWidthIsEqualTo(640.dp)
        rule.onNodeWithTag("fst.settings.feedback.submit").assertIsNotEnabled()
        rule.onNodeWithTag("fst.settings.feedback.validation").assertTextEquals(FeedbackProblem.MissingTitle.message)
        rule.onNodeWithTag("fst.settings.feedback.close").performClick()
        waitFor("fst.settings.feedback.dialog", gone = true)
    }
}
