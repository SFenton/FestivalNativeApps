package com.festivalscoretracker.android.ui.settings

import android.os.Looper
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.feedback.FeedbackAttachment
import com.festivalscoretracker.android.core.feedback.FeedbackJob
import com.festivalscoretracker.android.core.feedback.FeedbackJobState
import com.festivalscoretracker.android.core.feedback.FeedbackKind
import com.festivalscoretracker.android.presentation.feedback.FeedbackViewModel
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import java.time.Duration
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Issue #634: sending a feedback form fades its fields out to a centred spinner, title and
 * subtitle; "Uploading Media" over a determinate bar hands off to "Filing Request" with the
 * spinner kept, and Reduce Motion swaps the text without a fade.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class FeedbackBusyViewTest {
    @get:Rule
    val rule = createComposeRule()

    private val uploaded = CompletableDeferred<Unit>()
    private val filed = CompletableDeferred<Unit>()
    private var report: ((Float?) -> Unit)? = null
    private val jobId = "0123456789abcdef0123456789abcdef"

    // region Helpers

    private fun settle() = repeat(4) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100))
        rule.waitForIdle()
    }

    private fun gone(tag: String) = rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isEmpty()

    /**
     * Open a feature form with one image and submit it; the upload and filing wait for the test.
     *
     * @param reduceMotion In-app Reduce Motion.
     * @return The view model.
     */
    private fun submitWithMedia(reduceMotion: Boolean = false): FeedbackViewModel {
        val viewModel = FeedbackViewModel(
            send = { _, onProgress -> report = onProgress; uploaded.await(); FeedbackJob(jobId, FeedbackJobState.Queued) },
            status = { filed.await(); FeedbackJob(jobId, FeedbackJobState.Submitted, 3) },
            features = { true },
            appVersion = "test",
            clientInfo = "test",
            io = Dispatchers.Unconfined,
            scope = MainScope(),
        )
        viewModel.open(FeedbackKind.Feature)
        viewModel.edit { it.copy(title = "[Feature] Themes", description = "More themes") }
        viewModel.addAttachments(listOf(FeedbackAttachment("content://x/shot.png", "shot.png", "image/png", 2_048)))
        rule.setContent { FestivalTheme(appReduceMotion = reduceMotion) { FeedbackDialogHost(viewModel) } }
        settle()
        rule.onNodeWithTag("fst.settings.feedback.field.title").assertIsDisplayed()
        viewModel.submit()
        settle()
        return viewModel
    }

    // endregion

    @Test
    fun uploadingMediaThenFilingInACentredBusyView() {
        submitWithMedia()
        rule.onNodeWithTag("fst.settings.feedback.progress").assertIsDisplayed()
        rule.onNodeWithTag("fst.settings.feedback.progress.title").assertTextEquals("Uploading Media")
        rule.onNodeWithTag("fst.settings.feedback.progress.spinner").assertContentDescriptionEquals("Sending your request")
        val bar = rule.onNodeWithTag("fst.settings.feedback.progress.bar")
        bar.assertContentDescriptionEquals("Upload progress")
        assertEquals(0f, bar.fetchSemanticsNode().config.getOrNull(SemanticsProperties.ProgressBarRangeInfo)!!.current, 0f)
        assertTrue(gone("fst.settings.feedback.progress.subtitle"))
        // The fields are out of TalkBack and touch; the header's Close stays and Submit is off.
        assertTrue(gone("fst.settings.feedback.field.title"))
        assertTrue(gone("fst.settings.feedback.attach"))
        rule.onNodeWithTag("fst.settings.feedback.close").assertIsDisplayed()
        rule.onNodeWithTag("fst.settings.feedback.submit").assertIsNotEnabled()

        // The bar follows the upload.
        report!!(0.456f)
        settle()
        val info = rule.onNodeWithTag("fst.settings.feedback.progress.bar").fetchSemanticsNode().config[SemanticsProperties.ProgressBarRangeInfo]
        assertEquals(0.45f, info.current, 0.001f)

        // Centred horizontally in the body under the header (vertical centring is checked with the
        // subtitle below: M3 pads the bar's semantics bounds by 10 dp for touch exploration).
        val region = rule.onNodeWithTag("fst.settings.feedback.progress").fetchSemanticsNode().boundsInRoot
        val spinner = rule.onNodeWithTag("fst.settings.feedback.progress.spinner").fetchSemanticsNode().boundsInRoot
        val barBounds = rule.onNodeWithTag("fst.settings.feedback.progress.bar").fetchSemanticsNode().boundsInRoot
        assertEquals(region.center.x, spinner.center.x, 1f)
        assertEquals(region.center.x, barBounds.center.x, 1f)
        val header = rule.onNodeWithTag("fst.settings.feedback.close").fetchSemanticsNode().boundsInRoot
        assertTrue("busy region $region under the header $header", region.top >= header.bottom - 1f)

        // Hand-off: the title, bar and subtitle change; the spinner stays.
        uploaded.complete(Unit)
        settle()
        rule.onNodeWithTag("fst.settings.feedback.progress.title").assertTextEquals("Filing Request")
        val subtitle = rule.onNodeWithTag("fst.settings.feedback.progress.subtitle")
        subtitle.assertTextEquals("We\u2019re filing your request. Please wait while we upload it.")
        assertTrue(gone("fst.settings.feedback.progress.bar"))
        val kept = rule.onNodeWithTag("fst.settings.feedback.progress.spinner").assertIsDisplayed().fetchSemanticsNode().boundsInRoot
        val bottom = subtitle.fetchSemanticsNode().boundsInRoot.bottom
        assertEquals(kept.top - region.top, region.bottom - bottom, 2f)

        // Filed: the form closes before its result alert (#565).
        filed.complete(Unit)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(FeedbackViewModel.POLL_INTERVAL_MS + 100))
        settle()
        assertTrue(gone("fst.settings.feedback.dialog"))
        rule.onNodeWithTag("fst.settings.feedback.sent").assertIsDisplayed()
    }

    @Test
    fun stepChangeFadesOutBeforeTheNewTitle() {
        submitWithMedia()
        rule.mainClock.autoAdvance = false
        uploaded.complete(Unit)
        shadowOf(Looper.getMainLooper()).idle()
        rule.mainClock.advanceTimeByFrame()
        rule.mainClock.advanceTimeBy(64)
        // Mid fade-out: the old title is still on screen; the new one follows after 150 ms.
        rule.onNodeWithTag("fst.settings.feedback.progress.title").assertTextEquals("Uploading Media")
        rule.mainClock.advanceTimeBy(400)
        rule.onNodeWithTag("fst.settings.feedback.progress.title").assertTextEquals("Filing Request")
        rule.mainClock.autoAdvance = true
    }

    @Test
    fun reduceMotionSwapsTheTitleAtOnce() {
        submitWithMedia(reduceMotion = true)
        rule.mainClock.autoAdvance = false
        uploaded.complete(Unit)
        shadowOf(Looper.getMainLooper()).idle()
        rule.mainClock.advanceTimeByFrame()
        rule.onNodeWithTag("fst.settings.feedback.progress.title").assertTextEquals("Filing Request")
        rule.mainClock.autoAdvance = true
    }
}
