package com.festivalscoretracker.android

import android.content.Intent
import android.os.Looper
import android.view.KeyEvent
import android.view.KeyboardShortcutGroup
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.time.Duration
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * The real single activity under Robolectric: splash + edge-to-edge setup, debug extras,
 * key shortcuts and the Keyboard Shortcuts Helper. The origin is a closed loopback port,
 * so no request ever leaves the machine (never production).
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp")
class MainActivityTest {
    @get:Rule
    val rule = createEmptyComposeRule()

    private fun intent(vararg extras: Pair<String, String>) =
        Intent(ApplicationProvider.getApplicationContext(), MainActivity::class.java).apply {
            putExtra("FST_ORIGIN", "http://127.0.0.1:9")
            putExtra("FST_DEBUG_STILL_BACKGROUND", "1")
            extras.forEach { (key, value) -> putExtra(key, value) }
        }

    private fun settle() = repeat(4) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100))
        rule.waitForIdle()
    }

    private fun exists(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    @Test
    fun launchesTheShellWithDebugExtrasAndSurvivesRecreation() {
        ActivityScenario.launch<MainActivity>(intent("FST_DEBUG_TAB" to "settings")).use { scenario ->
            rule.waitUntil(10_000) { settle(); exists("fst.settings.list") }
            // Recreation keeps the tab but does not replay one-shot launch extras.
            scenario.recreate()
            rule.waitUntil(10_000) { settle(); exists("fst.settings.list") }
        }
    }

    @Test
    fun launcherLabelIsShortWhileTheAppKeepsItsFullName() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val pm = context.packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER).setPackage(context.packageName)
        val entry = pm.queryIntentActivities(launcher, 0).single()
        // Home screens label the icon with the launcher activity's label (issue #79).
        assertEquals("FST", entry.loadLabel(pm).toString())
        // App info and in-app branding keep the full name.
        assertEquals("Festival Score Tracker", context.applicationInfo.loadLabel(pm).toString())
    }

    @Test
    fun ctrlKOpensGlobalSearchAndShortcutsAreListed() {
        ActivityScenario.launch<MainActivity>(intent()).use { scenario ->
            rule.waitUntil(10_000) { settle(); exists("fst.nav.top-bar") }
            scenario.onActivity { activity ->
                val down = KeyEvent(0, 0, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_K, 0, KeyEvent.META_CTRL_ON)
                assertTrue(activity.dispatchKeyEvent(down))
                // A plain key is not a shortcut and falls through to the views.
                activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_A))
                val groups = mutableListOf<KeyboardShortcutGroup>()
                activity.onProvideKeyboardShortcuts(groups, null, 0)
                val group = groups.single { it.label == "Festival Score Tracker" }
                assertEquals(listOf(KeyEvent.KEYCODE_K, KeyEvent.KEYCODE_F), group.items.map { it.keycode })
            }
            rule.waitUntil(10_000) { settle(); exists("fst.global-search.surface") || exists("fst.global-search.field") }
        }
    }
}
