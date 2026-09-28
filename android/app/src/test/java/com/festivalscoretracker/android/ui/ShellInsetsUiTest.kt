package com.festivalscoretracker.android.ui

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToIndex
import androidx.test.ext.junit.rules.ActivityScenarioRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import okhttp3.OkHttpClient
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Content must never draw above the top app bar (which owns the status-bar / cutout inset),
 * even after a scroll that no nested-scroll event reports, on every navigation layout.
 */
private fun AndroidComposeTestRule<ActivityScenarioRule<ComponentActivity>, ComponentActivity>.assertContentBelowTopBar() {
    val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
    }
    val debug = DebugLaunch(section = FestivalSection.Settings, stillBackground = true)
    val container = AppContainer(activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
    setContent { FestivalApp(container, debug) }
    fun settle() = repeat(4) { shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100)); waitForIdle() }
    waitUntil(10_000) { settle(); onAllNodesWithTag("fst.settings.list").fetchSemanticsNodes().isNotEmpty() }
    // Scroll without touch (like a Quick Links jump) so the pinned bar sees no nested scroll.
    onNodeWithTag("fst.settings.list").performScrollToIndexSafely(8)
    settle()
    val bar = onNodeWithTag("fst.nav.top-bar").fetchSemanticsNode().boundsInRoot
    val content = onNodeWithTag("fst.nav.content").fetchSemanticsNode().boundsInRoot
    assertTrue("content top ${content.top} above bar bottom ${bar.bottom}", content.top >= bar.bottom - 0.5f)
    val list = onNodeWithTag("fst.settings.list").fetchSemanticsNode()
    fun visit(node: SemanticsNode) {
        val b = node.boundsInRoot
        if (b.height > 0f) assertTrue("${node.config} drawn at ${b.top} above bar bottom ${bar.bottom}", b.top >= bar.bottom - 0.5f)
        node.children.forEach(::visit)
    }
    list.children.forEach(::visit)
}

private fun androidx.compose.ui.test.SemanticsNodeInteraction.performScrollToIndexSafely(index: Int) {
    val node = fetchSemanticsNode()
    val count = node.config.getOrElseNullable(androidx.compose.ui.semantics.SemanticsProperties.CollectionInfo) { null }?.rowCount ?: (index + 1)
    performScrollToIndex(minOf(index, (count - 1).coerceAtLeast(0)))
}

@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class PhoneShellInsetsUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun contentStaysBelowTopBar() = rule.assertContentBelowTopBar()
}

@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w900dp-h1000dp-xhdpi")
class RailShellInsetsUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun contentStaysBelowTopBar() = rule.assertContentBelowTopBar()
}

@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w1280dp-h800dp-land-xhdpi")
class DrawerShellInsetsUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun contentStaysBelowTopBar() = rule.assertContentBelowTopBar()
}
