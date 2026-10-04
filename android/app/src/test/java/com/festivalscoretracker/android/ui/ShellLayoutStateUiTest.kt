package com.festivalscoretracker.android.ui

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.input.pointer.PointerKeyboardModifiers
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.platform.WindowInfo
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.unit.IntSize
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.nav.LicensesRoute
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import kotlin.math.roundToInt
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

// region Shell layout state

/**
 * Rotating a tablet crosses the shell's rail ↔ permanent drawer boundary. The page tree must
 * move between the two chrome branches rather than be rebuilt, so the open license (page
 * `rememberSaveable` state) survives (issue #122). Robolectric with a fake transport; the
 * window size is driven through [LocalWindowInfo], which `currentWindowSize()` reads.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w1280dp-h800dp-xhdpi")
class ShellLayoutStateUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val activityRow = "fst.licenses.row.androidx.activity:activity-ktx"

    private fun settle(millis: Long = 400) = repeat(4) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
        rule.waitForIdle()
    }

    private fun waitFor(tag: String) = rule.waitUntil(10_000) {
        settle(100)
        rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
    }

    @Test
    fun openLicenseSurvivesRailToPermanentDrawer() {
        val debug = DebugLaunch(section = FestivalSection.Settings, route = LicensesRoute, stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = FakeTransport.standard(), settingsStore = InMemoryPreferences())
        val portrait = mutableStateOf(true)
        rule.setContent {
            val density = LocalDensity.current
            val window = object : WindowInfo {
                override val isWindowFocused = true
                override val keyboardModifiers = PointerKeyboardModifiers(0)
                override val containerSize: IntSize
                    get() {
                        val short = (800 * density.density).roundToInt()
                        val long = (1280 * density.density).roundToInt()
                        return if (portrait.value) IntSize(short, long) else IntSize(long, short)
                    }
            }
            CompositionLocalProvider(LocalWindowInfo provides window) { FestivalApp(container, debug) }
        }
        waitFor("fst.licenses.list")
        assertTrue(rule.onAllNodesWithTag("fst.nav.permanent-drawer").fetchSemanticsNodes().isEmpty())

        rule.onNodeWithTag("fst.licenses.list").performScrollToNode(hasTestTag(activityRow))
        rule.onNodeWithTag(activityRow).performSemanticsAction(SemanticsActions.OnClick)
        settle()
        rule.onNodeWithTag(activityRow).assertIsSelected()

        portrait.value = false
        waitFor("fst.nav.permanent-drawer")
        settle()
        assertEquals(1, rule.onAllNodesWithTag("fst.licenses.list").fetchSemanticsNodes().size)
        rule.onNodeWithTag(activityRow).assertIsSelected()
    }
}

// endregion
