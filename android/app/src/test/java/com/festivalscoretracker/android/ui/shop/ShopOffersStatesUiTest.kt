package com.festivalscoretracker.android.ui.shop

import android.content.Intent
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.unit.Density
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.window.layout.FoldingFeature.Orientation
import androidx.window.layout.FoldingFeature.State
import androidx.window.testing.layout.FoldingFeature
import androidx.window.testing.layout.TestWindowLayoutInfo
import androidx.window.testing.layout.WindowLayoutInfoPublisherRule
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.ShopRoute
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.data.HttpTransport
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.SongsFixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.net.UnknownHostException
import java.time.Duration
import kotlinx.coroutines.CompletableDeferred
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Every reachable Shop offers state (issue #131, `.agents/controls/shop-offers/android.md`):
 * hidden, loading, empty, failed, offline, unverified, populated with New / Leaving
 * badges, grid and list, the official link, Song Detail's Shop action, highlights off,
 * the page filter and its no-match state, and the half-open book posture.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class ShopOffersStatesUiTest {
    @get:Rule(order = 0)
    val windowInfo = WindowLayoutInfoPublisherRule()

    @get:Rule(order = 1)
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val publication = mapOf("X-FST-Publication-Id" to "7")

    // region Harness

    private fun transport() = FakeTransport.standard().apply {
        on("/api/songs", headers = publication) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        on("/api/shop", headers = publication) { SongsFixtures.shopJson.replace("\"b.jpg\"", "null") }
    }

    private fun launch(
        debug: DebugLaunch = DebugLaunch(route = ShopRoute, stillBackground = true),
        prefs: InMemoryPreferences = InMemoryPreferences(),
        transport: HttpTransport = transport(),
    ) {
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = prefs)
        rule.setContent { FestivalApp(container, debug) }
        settle()
    }

    private fun settle(millis: Long = 400) {
        repeat(4) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
            rule.waitForIdle()
        }
    }

    private fun exists(tag: String, unmerged: Boolean = false) =
        rule.onAllNodesWithTag(tag, useUnmergedTree = unmerged).fetchSemanticsNodes().isNotEmpty()

    private fun textShown(text: String) = rule.onAllNodesWithText(text, substring = true).fetchSemanticsNodes().isNotEmpty()

    private fun waitForTag(tag: String, unmerged: Boolean = false) {
        rule.waitUntil(10_000) {
            settle(100)
            exists(tag, unmerged)
        }
    }

    private fun waitForText(text: String) {
        rule.waitUntil(10_000) {
            settle(100)
            textShown(text)
        }
    }

    private fun click(tag: String) = rule.onNodeWithTag(tag).performSemanticsAction(SemanticsActions.OnClick)

    private fun bounds(tag: String) = rule.onNodeWithTag(tag).fetchSemanticsNode().boundsInWindow

    private fun dp(px: Float) = px / Density(rule.activity).density

    /** Publish one fold to Jetpack WindowManager once the shell is observing it. */
    private fun fold(state: State) {
        windowInfo.overrideWindowLayoutInfo(
            TestWindowLayoutInfo(listOf(FoldingFeature(rule.activity, state = state, orientation = Orientation.VERTICAL))),
        )
        settle()
    }

    // endregion

    // region Visibility and load states

    @Test
    fun hiddenShowsTheNoticeWithoutPageTools() {
        val prefs = InMemoryPreferences(mutablePreferencesOf(booleanPreferencesKey(SettingsRegistry.HIDE_SHOP) to true))
        launch(prefs = prefs)
        waitForTag("fst.shop.hidden")
        assertFalse(exists("fst.shop.filter.open"))
        assertFalse(exists("fst.shop.view-toggle"))
        assertFalse(exists("fst.shop.song.s-alpha"))
    }

    @Test
    fun loadingShowsTheSpinnerUntilTheFeedArrives() {
        val gate = CompletableDeferred<Unit>()
        val inner = transport()
        val spinner = hasContentDescription("Loading Item Shop")
        launch(transport = HttpTransport { request -> if ("/api/shop" in request.url) gate.await(); inner.send(request) })
        rule.waitUntil(10_000) { settle(100); rule.onAllNodes(spinner).fetchSemanticsNodes().isNotEmpty() }
        assertFalse(exists("fst.shop.song.s-alpha"))
        gate.complete(Unit)
        waitForTag("fst.shop.song.s-alpha")
        assertTrue(rule.onAllNodes(spinner).fetchSemanticsNodes().isEmpty())
    }

    @Test
    fun emptyFeedIsTheEmptyStateNotAnError() {
        val empty = transport().apply { on("/api/shop", headers = publication) { """{"count":0,"songs":[]}""" } }
        launch(transport = empty)
        waitForTag("fst.shop.empty")
        waitForText("No Songs in the Item Shop")
        assertFalse(exists("fst.shop.error"))
        assertFalse(exists("fst.shop.filter.empty"))
    }

    @Test
    fun failureOffersRetryThatRecovers() {
        val failing = transport().apply { on("/api/shop", status = 503) { "{}" } }
        launch(transport = failing)
        waitForTag("fst.shop.error")
        assertFalse(exists("fst.shop.empty"))
        failing.on("/api/shop", headers = publication) { SongsFixtures.shopJson }
        rule.onAllNodesWithText("Retry").onFirst().performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.shop.song.s-alpha")
    }

    @Test
    fun offlineIsAnExplicitOfflineState() {
        val offline = transport().apply { onRaw("/api/shop") { throw UnknownHostException("synthetic") } }
        launch(transport = offline)
        waitForTag("fst.shop.error")
        waitForText("You're offline")
        assertFalse(exists("fst.shop.empty"))
    }

    @Test
    fun untrustedShopLinkRejectsTheFeed() {
        val untrusted = transport().apply {
            on("/api/shop", headers = publication) {
                """{"count":1,"songs":[{"songId":"s-alpha","title":"Alpha Tune","artist":"Band One","shopUrl":"https://example.com/item-shop/jam-tracks/alpha"}]}"""
            }
        }
        launch(transport = untrusted)
        waitForTag("fst.shop.error")
        assertFalse(exists("fst.shop.song.s-alpha"))
        assertFalse(exists("fst.shop.empty"))
    }

    // endregion

    // region Offers

    @Test
    fun populatedListIsTitleOrderedWithBadgesAndLargeTargets() {
        launch()
        waitForTag("fst.shop.list")
        waitForTag("fst.shop.song.s-beta")
        // Compact: always the list, no grid toggle.
        assertFalse(exists("fst.shop.view-toggle"))
        val order = listOf("s-alpha", "s-x", "s-beta").map { bounds("fst.shop.song.$it").top }
        assertEquals(order.sorted(), order)
        // New and Leaving Tomorrow are visible text, not color alone.
        rule.onNodeWithTag("fst.shop.badge.new.s-beta", useUnmergedTree = true).assertExists()
        rule.onNodeWithTag("fst.shop.badge.leaving.s-alpha", useUnmergedTree = true).assertExists()
        assertFalse(exists("fst.shop.badge.new.s-x", unmerged = true) || exists("fst.shop.badge.leaving.s-x", unmerged = true))
        rule.onNode(hasContentDescription("Open Beta Song in the Fortnite Item Shop"), useUnmergedTree = true).assertExists()
        val target = bounds("fst.shop.external.s-beta")
        assertTrue("external link ${dp(target.width)}×${dp(target.height)} dp", dp(target.height) >= 48f && dp(target.width) >= 48f)
    }

    @Test
    @Config(qualifiers = "w1280dp-h800dp-xhdpi")
    fun gridCardsAreSquareAndListToggleKeepsTheOffers() {
        launch()
        waitForTag("fst.shop.grid")
        waitForTag("fst.shop.song.s-alpha")
        val card = bounds("fst.shop.song.s-alpha")
        assertEquals(card.width, card.height, 1f)
        // Grid cards announce the badge and the official link in one label.
        rule.onNode(hasTestTag("fst.shop.song.s-alpha") and hasContentDescription("Leaving Tomorrow", substring = true)).assertExists()
        rule.onNode(hasContentDescription("List View")).assertExists()
        click("fst.shop.view-toggle")
        waitForTag("fst.shop.list")
        waitForTag("fst.shop.song.s-alpha")
        rule.onNode(hasContentDescription("Grid View")).assertExists()
        click("fst.shop.view-toggle")
        waitForTag("fst.shop.grid")
    }

    @Test
    fun officialLinkOpensTheFortniteItemShop() {
        launch()
        waitForTag("fst.shop.external.s-beta")
        click("fst.shop.external.s-beta")
        settle()
        val intent = shadowOf(rule.activity).nextStartedActivity
        assertEquals(Intent.ACTION_VIEW, intent.action)
        assertEquals(SongsFixtures.shopUrl("beta"), intent.dataString)
    }

    @Test
    fun songDetailShowsTheShopActionWithItsStatus() {
        launch(DebugLaunch(songQuery = "s-alpha", stillBackground = true))
        waitForTag("fst.song-detail.list")
        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag("fst.song-detail.shop"))
        rule.onNode(hasContentDescription("Item Shop, Leaving Tomorrow, opens the Fortnite Item Shop"), useUnmergedTree = true).assertExists()
    }

    @Test
    fun songDetailShowsAnExplicitShopError() {
        val failing = transport().apply { on("/api/shop", status = 503) { "{}" } }
        launch(DebugLaunch(songQuery = "s-alpha", stillBackground = true), transport = failing)
        waitForTag("fst.song-detail.list")
        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag("fst.song-detail.shop-error"))
        assertFalse(exists("fst.song-detail.shop"))
    }

    @Test
    fun highlightsOffHideBadgesButKeepTheLink() {
        val prefs = InMemoryPreferences(mutablePreferencesOf(booleanPreferencesKey(SettingsRegistry.DISABLE_SHOP_HIGHLIGHTING) to true))
        launch(prefs = prefs)
        waitForTag("fst.shop.song.s-beta")
        assertFalse(exists("fst.shop.badge.new.s-beta", unmerged = true))
        assertFalse(exists("fst.shop.badge.leaving.s-alpha", unmerged = true))
        rule.onNodeWithTag("fst.shop.external.s-beta").assertExists()
    }

    // endregion

    // region Filter

    @Test
    fun filterNarrowsTheOffersLive() {
        launch()
        waitForTag("fst.shop.song.s-alpha")
        click("fst.shop.filter.open")
        waitForTag("fst.shop.filter.leaving")
        click("fst.shop.filter.leaving")
        rule.waitUntil(10_000) { settle(100); !exists("fst.shop.song.s-alpha") }
        assertTrue(exists("fst.shop.song.s-beta"))
        assertTrue(exists("fst.shop.song.s-x"))
        click("fst.shop.filter.leaving")
        click("fst.shop.filter.new")
        click("fst.shop.filter.available")
        rule.waitUntil(10_000) { settle(100); exists("fst.shop.song.s-alpha") && !exists("fst.shop.song.s-x") && !exists("fst.shop.song.s-beta") }
        click("fst.shop.filter.done")
        rule.waitUntil(10_000) { settle(100); !exists("fst.shop.filter.new") }
        assertTrue(exists("fst.shop.song.s-alpha"))
    }

    @Test
    fun filterWithNoMatchIsDistinctFromEmpty() {
        val plain = transport().apply {
            on("/api/shop", headers = publication) {
                """{"count":1,"songs":[{"songId":"s-x","title":"Alpha Tune","artist":"Other","shopUrl":"${SongsFixtures.shopUrl("x")}"}]}"""
            }
        }
        launch(transport = plain)
        waitForTag("fst.shop.song.s-x")
        click("fst.shop.filter.open")
        waitForTag("fst.shop.filter.available")
        click("fst.shop.filter.available")
        click("fst.shop.filter.done")
        waitForTag("fst.shop.filter.empty")
        assertFalse(exists("fst.shop.empty"))
        click("fst.shop.filter.empty-reset")
        waitForTag("fst.shop.song.s-x")
    }

    // endregion

    // region Foldables

    private fun hingeX() = rule.activity.window.decorView.width / 2f

    private fun assertOffHinge(tags: List<String>) {
        val hinge = hingeX()
        tags.forEach { tag ->
            val box = bounds(tag)
            assertTrue("$tag [${box.left}, ${box.right}] crosses the hinge at $hinge", box.right <= hinge || box.left >= hinge)
        }
    }

    /** Material 3: no interactive content across a hinge; book posture splits the rows at the fold. */
    @Test
    @Config(qualifiers = "w790dp-h840dp-xhdpi")
    fun halfOpenBookFoldKeepsGridCardsAndListRowsOffTheHinge() {
        launch()
        fold(State.HALF_OPENED)
        waitForTag("fst.shop.grid")
        waitForTag("fst.shop.song.s-beta")
        val offers = listOf("s-alpha", "s-x", "s-beta").map { "fst.shop.song.$it" }
        assertOffHinge(offers)
        val hinge = hingeX()
        assertTrue("cards on both sides", offers.any { bounds(it).right <= hinge } && offers.any { bounds(it).left >= hinge })
        // Cards keep one size across unequal panes.
        assertEquals(bounds(offers[0]).width, bounds(offers[2]).width, 1f)
        click("fst.shop.view-toggle")
        waitForTag("fst.shop.list")
        waitForTag("fst.shop.song.s-beta")
        assertOffHinge(offers + listOf("fst.shop.external.s-alpha", "fst.shop.external.s-beta"))
        // Flat again: one full-width list.
        fold(State.FLAT)
        rule.waitUntil(10_000) { settle(100); bounds("fst.shop.song.s-alpha").let { it.left < hinge && it.right > hinge } }
    }

    /**
     * Large text: the list goes full width (one column, as on every page), but the grid keeps
     * its columns, so its cards still split at the fold instead of straddling it (issue #113).
     */
    @Test
    @Config(qualifiers = "w790dp-h840dp-xhdpi", fontScale = 2f)
    fun halfOpenBookFoldAtLargeTextSplitsTheGridButNotTheList() {
        launch()
        fold(State.HALF_OPENED)
        waitForTag("fst.shop.grid")
        waitForTag("fst.shop.song.s-beta")
        val offers = listOf("s-alpha", "s-x", "s-beta").map { "fst.shop.song.$it" }
        assertOffHinge(offers)
        val hinge = hingeX()
        assertTrue("cards on both sides", offers.any { bounds(it).right <= hinge } && offers.any { bounds(it).left >= hinge })
        click("fst.shop.view-toggle")
        waitForTag("fst.shop.list")
        waitForTag("fst.shop.song.s-alpha")
        rule.waitUntil(10_000) { settle(100); bounds("fst.shop.song.s-alpha").let { it.left < hinge && it.right > hinge } }
    }

    @Test
    @Config(qualifiers = "w790dp-h840dp-xhdpi")
    fun halfOpenBookFoldKeepsCentredStatesOnTheLeadingPane() {
        val empty = transport().apply { on("/api/shop", headers = publication) { """{"count":0,"songs":[]}""" } }
        launch(transport = empty)
        fold(State.HALF_OPENED)
        waitForTag("fst.shop.empty")
        waitForTag("fst.shop.start-pane")
        assertOffHinge(listOf("fst.shop.empty", "fst.shop.start-pane"))
    }

    // endregion
}
