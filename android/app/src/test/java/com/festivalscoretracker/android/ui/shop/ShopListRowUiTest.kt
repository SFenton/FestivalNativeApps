package com.festivalscoretracker.android.ui.shop

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.ShopRoute
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.SongsFixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The Item Shop list row is the Songs page's shared `SongRowCard` (issue #18, validated in
 * issue #144): the row action (Song Details when matched, else the official link), one
 * TalkBack stop that reads the texts and badge with the cart link as its own stop, and the
 * card's title behavior (marquee for long titles, tail ellipsis under reduced motion,
 * wrapping at large text).
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ShopListRowUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val publication = mapOf("X-FST-Publication-Id" to "7")

    // region Harness

    private fun transport(longTitle: Boolean = false) = FakeTransport.standard().apply {
        on("/api/songs", headers = publication) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        on("/api/shop", headers = publication) {
            val shop = SongsFixtures.shopJson.replace("\"b.jpg\"", "null")
            if (longTitle) shop.replace("\"title\":\"Beta Song\"", "\"title\":\"$LONG_TITLE\"") else shop
        }
    }

    private fun launch(prefs: InMemoryPreferences = InMemoryPreferences(), longTitle: Boolean = false) {
        val debug = DebugLaunch(route = ShopRoute, stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport(longTitle), settingsStore = prefs)
        rule.setContent { FestivalApp(container, debug) }
        settle()
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

    private fun titleLayout(text: String): TextLayoutResult {
        val results = mutableListOf<TextLayoutResult>()
        rule.onNodeWithText(text, useUnmergedTree = true).fetchSemanticsNode().config[SemanticsActions.GetTextLayoutResult].action!!.invoke(results)
        return results.single()
    }

    private fun openedUrl(): String? = shadowOf(rule.activity).nextStartedActivity?.dataString

    private companion object {
        const val LONG_TITLE = "A Remarkably Long Synthetic Item Shop Song Title That Cannot Fit In One Row"
    }

    // endregion

    @Test
    fun matchedRowOpensSongDetails() {
        launch()
        waitForTag("fst.shop.song.s-alpha")
        rule.onNodeWithTag("fst.shop.song.s-alpha").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.song-detail.list")
        assertNull("a matched row never opens the external Shop", openedUrl())
    }

    @Test
    fun unmatchedRowOpensTheOfficialShopPage() {
        launch()
        waitForTag("fst.shop.song.s-x")
        rule.onNodeWithTag("fst.shop.song.s-x").performSemanticsAction(SemanticsActions.OnClick)
        settle()
        assertEquals(SongsFixtures.shopUrl("x"), openedUrl())
    }

    @Test
    fun rowIsOneTalkBackStopWithItsTextsAndBadgeAndTheLinkIsItsOwnStop() {
        launch()
        waitForTag("fst.shop.song.s-alpha")
        val row = rule.onNodeWithTag("fst.shop.song.s-alpha").fetchSemanticsNode().config
        val spoken = row.getOrNull(SemanticsProperties.Text).orEmpty().map { it.text }
        assertEquals(listOf("Alpha Tune", "Band One", "Leaving Tomorrow"), spoken)
        // No whole-card description: TalkBack reads the visible texts, never a hidden label.
        assertNull(row.getOrNull(SemanticsProperties.ContentDescription))
        assertTrue(row.contains(SemanticsActions.OnClick))
        // Single-pane Shop rows are not selectable, so TalkBack never says "Not selected".
        assertNull(row.getOrNull(SemanticsProperties.Selected))

        val link = rule.onNodeWithTag("fst.shop.external.s-alpha").fetchSemanticsNode().config
        assertEquals(listOf("Open Alpha Tune in the Fortnite Item Shop"), link.getOrNull(SemanticsProperties.ContentDescription))
        assertFalse("the link is not merged into the row", spoken.any { "Fortnite Item Shop" in it })
    }

    @Test
    fun newRowShowsNoVisibleBadgeButTalkBackStillHearsNew() {
        launch()
        waitForTag("fst.shop.song.s-beta")
        // Issue #562 (web `SongRow`): a New row is marked by its gold outline only.
        assertTrue(rule.onAllNodesWithTag("fst.shop.badge.new.s-beta", useUnmergedTree = true).fetchSemanticsNodes().isEmpty())
        assertTrue(rule.onAllNodes(hasText("New") and hasAnyAncestor(hasTestTag("fst.shop.song.s-beta")), useUnmergedTree = true).fetchSemanticsNodes().isEmpty())
        val row = rule.onNodeWithTag("fst.shop.song.s-beta").fetchSemanticsNode().config
        assertEquals(listOf("Beta Song", "Band Two · 2019"), row.getOrNull(SemanticsProperties.Text).orEmpty().map { it.text })
        // TalkBack reads the texts, then the state: "Beta Song, Band Two · 2019, New".
        assertEquals("New", row.getOrNull(SemanticsProperties.StateDescription))
        assertNull(row.getOrNull(SemanticsProperties.ContentDescription))
        // Leaving Tomorrow keeps its visible label and needs no extra state.
        val leaving = rule.onNodeWithTag("fst.shop.badge.leaving.s-alpha", useUnmergedTree = true).fetchSemanticsNode()
        assertTrue(leaving.size.width > 0 && leaving.size.height > 0)
        assertNull(rule.onNodeWithTag("fst.shop.song.s-alpha").fetchSemanticsNode().config.getOrNull(SemanticsProperties.StateDescription))
    }

    @Test
    fun longTitleScrollsAsAMarqueeOnOneLine() {
        launch(longTitle = true)
        waitForTag("fst.shop.song.s-beta")
        val title = titleLayout(LONG_TITLE)
        assertEquals(1, title.lineCount)
        assertFalse("a moving title is never ellipsized", title.isLineEllipsized(0))
        val rowPx = rule.onNodeWithTag("fst.shop.song.s-beta").fetchSemanticsNode().size.width
        assertTrue("the full title (${title.size.width} px) is wider than the row ($rowPx px), so it scrolls", title.size.width > rowPx)
    }

    @Test
    fun reducedMotionHoldsTheLongTitleStillWithATailEllipsis() {
        launch(InMemoryPreferences(mutablePreferencesOf(booleanPreferencesKey(SettingsRegistry.REDUCE_MOTION) to true)), longTitle = true)
        waitForTag("fst.shop.song.s-beta")
        val title = titleLayout(LONG_TITLE)
        assertEquals(1, title.lineCount)
        assertTrue(title.isLineEllipsized(0))
    }

    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi", fontScale = 2f)
    fun largeTextWrapsTheLongTitleInsteadOfScrolling() {
        launch(longTitle = true)
        waitForTag("fst.shop.song.s-beta")
        val title = titleLayout(LONG_TITLE)
        assertEquals("large text lets the title wrap", Int.MAX_VALUE, title.layoutInput.maxLines)
        assertFalse(title.isLineEllipsized(title.lineCount - 1))
        val row = rule.onNodeWithTag("fst.shop.song.s-beta").fetchSemanticsNode().boundsInRoot
        val text = rule.onNodeWithText(LONG_TITLE, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        assertTrue("title $text inside row $row", text.top >= row.top && text.bottom <= row.bottom && text.right <= row.right)
    }
}
