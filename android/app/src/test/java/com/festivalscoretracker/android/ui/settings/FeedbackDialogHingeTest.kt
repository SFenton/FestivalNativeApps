package com.festivalscoretracker.android.ui.settings

import android.os.Looper
import androidx.compose.material3.adaptive.HingeInfo
import androidx.compose.material3.adaptive.Posture
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.feedback.FeedbackKind
import com.festivalscoretracker.android.presentation.feedback.FeedbackViewModel
import com.festivalscoretracker.android.ui.common.LocalShellPosture
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import java.time.Duration
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Issue #146: the wide-window Report an Issue / Request a Feature dialog keeps to one side of a
 * separating hinge (M3 "Never place interactive content or critical information across the hinge
 * area") and stays centred across a flat fold.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w841dp-h900dp")
class FeedbackDialogHingeTest {
    @get:Rule
    val rule = createComposeRule()

    // region Helpers

    private fun settle() = repeat(4) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100))
        rule.waitForIdle()
    }

    /**
     * Open the bug form over a vertical hinge in the middle of the window.
     *
     * @param separating Whether the fold separates the panes (half-open) or is flat.
     * @return Hinge and dialog bounds in root pixels.
     */
    private fun feedbackOverHinge(separating: Boolean): Pair<Rect, Rect> {
        val viewModel = FeedbackViewModel(
            send = { error("not sent") },
            status = { error("not polled") },
            features = { true },
            appVersion = "test",
            clientInfo = "test",
            io = Dispatchers.Unconfined,
            scope = MainScope(),
        )
        viewModel.open(FeedbackKind.Bug)
        var hinge = Rect.Zero
        rule.setContent {
            val density = LocalDensity.current.density
            hinge = Rect(415 * density, 0f, 425 * density, 900 * density)
            val posture = Posture(hingeList = listOf(HingeInfo(hinge, isFlat = !separating, isVertical = true, isSeparating = separating, isOccluding = false)))
            CompositionLocalProvider(LocalShellPosture provides posture) {
                FestivalTheme { FeedbackDialogHost(viewModel) }
            }
        }
        settle()
        rule.onNodeWithTag("fst.settings.feedback.close", useUnmergedTree = true).assertIsDisplayed()
        return hinge to rule.onNodeWithTag("fst.settings.feedback.dialog").fetchSemanticsNode().boundsInRoot
    }

    // endregion

    @Test
    fun wideFeedbackAvoidsASeparatingHinge() {
        val (hinge, dialog) = feedbackOverHinge(separating = true)
        assertTrue("dialog $dialog clears hinge $hinge", dialog.right <= hinge.left || dialog.left >= hinge.right)
    }

    @Test
    fun wideFeedbackStaysCentredAcrossAFlatFold() {
        val (hinge, dialog) = feedbackOverHinge(separating = false)
        assertTrue("centred dialog $dialog spans the flat fold $hinge", dialog.left < hinge.left && dialog.right > hinge.right)
    }
}
