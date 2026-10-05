package com.festivalscoretracker.android.settings

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.BuildConfig
import com.festivalscoretracker.android.core.settings.AppBuildInfo
import com.festivalscoretracker.android.ui.settings.AppVersionRow
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * Settings → App Version row in both reachable states, stamped with a commit and not (issue #151;
 * the formatting rules are in [AppBuildInfoTest]). Robolectric phone window.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class AppVersionRowUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    // region Fixtures

    private val stamped = AppBuildInfo.versionText("2610.04.12", 261004012, "42edc57a1b2c3d4e5f60718293a4b5c6d7e8f901")
    private val unstamped = AppBuildInfo.versionText("2610.04.12", 261004012, "dev")

    private fun show(text: String?, width: Dp = 360.dp) {
        rule.setContent {
            FestivalTheme {
                Box(Modifier.width(width)) {
                    if (text == null) AppVersionRow() else AppVersionRow(text)
                }
            }
        }
        rule.waitForIdle()
    }

    private fun row() = rule.onNodeWithTag(TAG).fetchSemanticsNode()

    private fun spoken(): List<String> = row().config[SemanticsProperties.Text].map { it.text }

    private fun bounds(text: String): Rect = rule.onNodeWithText(text, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot

    // endregion

    // region States

    @Test
    fun stampedBuildReadsTitleThenVersionAndShortCommitAsOneItem() {
        show(stamped)
        assertEquals(listOf("App Version", "2610.04.12 (261004012) · 42edc57"), spoken())
        // Read-only: one merged TalkBack item, no click action or role.
        assertNull(row().config.getOrNull(SemanticsProperties.Role))
        assertFalse(row().config.contains(SemanticsActions.OnClick))
    }

    @Test
    fun unstampedBuildShowsOnlyVersionAndCode() {
        show(unstamped)
        assertEquals(listOf("App Version", "2610.04.12 (261004012)"), spoken())
        assertFalse(spoken().last().contains(AppBuildInfo.COMMIT_SEPARATOR.trim()))
    }

    @Test
    fun defaultTextIsThisBuildsIdentity() {
        show(null)
        val expected = AppBuildInfo.versionText(BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE, BuildConfig.GIT_SHA)
        assertEquals(listOf("App Version", expected), spoken())
        assertTrue(expected.startsWith("${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"))
    }

    // endregion

    // region Large text

    @Test
    @Config(qualifiers = "w360dp-h792dp-xhdpi", fontScale = 2f)
    fun largeTextKeepsTheStampedRowInsideItsBoundsWithoutOverlap() = assertLargeTextFits(stamped)

    @Test
    @Config(qualifiers = "w360dp-h792dp-xhdpi", fontScale = 2f)
    fun largeTextKeepsTheUnstampedRowInsideItsBoundsWithoutOverlap() = assertLargeTextFits(unstamped)

    private fun assertLargeTextFits(text: String) {
        show(text, width = 328.dp)
        assertEquals(2f, rule.density.fontScale)
        val rowBounds = row().boundsInRoot
        val title = bounds("App Version")
        val value = bounds(text)
        for (part in listOf(title, value)) {
            assertTrue("$part in $rowBounds", part.left >= rowBounds.left - 0.5f && part.right <= rowBounds.right + 0.5f)
            assertTrue("$part in $rowBounds", part.top >= rowBounds.top - 0.5f && part.bottom <= rowBounds.bottom + 0.5f)
        }
        // Either side by side or stacked, never overlapping.
        assertFalse("$title overlaps $value", title.overlaps(value))
    }

    // endregion

    private companion object {
        const val TAG = "fst.settings.app-version"
    }
}
