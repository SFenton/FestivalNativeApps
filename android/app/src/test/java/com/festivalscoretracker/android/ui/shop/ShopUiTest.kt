package com.festivalscoretracker.android.ui.shop

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performSemanticsAction
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
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Item Shop states the Songs suite does not reach (issue #113 validation): loading, the
 * official-link button, highlighting off, the medium-width grid with its accessibility
 * actions, and large text without clipping.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class ShopUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    // region Harness

    private fun transport() = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        on("/api/shop", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.shopJson.replace("\"b.jpg\"", "null") }
    }

    private fun launch(prefs: InMemoryPreferences = InMemoryPreferences(), transport: FakeTransport = transport()) {
        val debug = DebugLaunch(route = ShopRoute, stillBackground = true)
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

    private fun waitForTag(tag: String, unmerged: Boolean = false) {
        rule.waitUntil(10_000) {
            settle(100)
            rule.onAllNodesWithTag(tag, useUnmergedTree = unmerged).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun absent(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isEmpty()

    private fun openedUrl(): String? = shadowOf(rule.activity).nextStartedActivity?.dataString

    private fun dp(px: Float) = px / rule.activity.resources.displayMetrics.density

    private companion object {
        const val LONG_TITLE = "Still D.R.E. (Remastered Extended Edition Version)"
        const val LONG_ARTIST = "Snoop Dogg ft. Pharrell & Uncle Charlie Wilson"
    }

    // endregion

    @Test
    fun loadingStateShowsTheSpinnerUntilTheShopArrives() {
        val gate = CountDownLatch(1)
        val slow = transport().apply {
            on("/api/shop", headers = mapOf("X-FST-Publication-Id" to "7")) {
                gate.await(10, TimeUnit.SECONDS)
                SongsFixtures.shopJson
            }
        }
        launch(transport = slow)
        rule.waitUntil(10_000) { settle(100); rule.onAllNodes(hasContentDescription("Loading Item Shop")).fetchSemanticsNodes().isNotEmpty() }
        assertTrue(absent("fst.shop.list"))
        gate.countDown()
        waitForTag("fst.shop.list")
    }

    @Test
    fun compactListRowExposesBadgeLabelsAndALabelledOfficialLink() {
        launch()
        waitForTag("fst.shop.song.s-beta")
        // Compact windows always list: no Grid/List toggle; the filter keeps its spoken label.
        assertTrue(absent("fst.shop.view-toggle"))
        rule.onNodeWithTag("fst.shop.filter.open").assertContentDescriptionEquals("Filter Item Shop")
        // Issue #562: New has no visible label (gold outline only, like the web); TalkBack still hears it as the row's state.
        assertTrue(absent("fst.shop.badge.new.s-beta"))
        rule.onNodeWithTag("fst.shop.song.s-beta").assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "New"))
        rule.onNodeWithTag("fst.shop.badge.leaving.s-alpha", useUnmergedTree = true).assertIsDisplayed()

        val link = rule.onNodeWithTag("fst.shop.external.s-beta")
        link.assertContentDescriptionEquals("Open Beta Song in the Fortnite Item Shop")
        // Material3 IconButton draws a 40 dp container and pads its touch area to 48 dp.
        val bounds = link.fetchSemanticsNode().touchBoundsInRoot
        assertTrue("touch target ${dp(bounds.width)}×${dp(bounds.height)} dp", dp(bounds.width) >= 48f && dp(bounds.height) >= 48f)
        link.performSemanticsAction(SemanticsActions.OnClick)
        settle()
        assertEquals(SongsFixtures.shopUrl("beta"), openedUrl())
    }

    @Test
    fun highlightingOffRemovesBadgesButKeepsOffersAndLinks() {
        val prefs = InMemoryPreferences(mutablePreferencesOf(booleanPreferencesKey(SettingsRegistry.DISABLE_SHOP_HIGHLIGHTING) to true))
        launch(prefs)
        waitForTag("fst.shop.song.s-beta")
        assertTrue(absent("fst.shop.badge.new.s-beta"))
        assertTrue(absent("fst.shop.badge.leaving.s-alpha"))
        assertTrue(rule.onAllNodesWithText("New", useUnmergedTree = true).fetchSemanticsNodes().isEmpty())
        rule.onNodeWithTag("fst.shop.external.s-alpha").assertIsDisplayed()
    }

    @Test
    @Config(qualifiers = "w720dp-h1000dp-xhdpi")
    fun mediumWidthGridCardsAnnounceTheLinkAndOfferSongDetailsAsAnAction() {
        launch()
        waitForTag("fst.shop.grid")
        waitForTag("fst.shop.song.s-alpha")
        rule.onNodeWithTag("fst.shop.view-toggle").assertContentDescriptionEquals("List View")

        val matched = rule.onNodeWithTag("fst.shop.song.s-alpha").fetchSemanticsNode().config
        assertEquals(
            listOf("Alpha Tune, Band One, Leaving Tomorrow. Opens the Fortnite Item Shop"),
            matched.getOrNull(SemanticsProperties.ContentDescription),
        )
        val actions = matched.getOrNull(SemanticsActions.CustomActions).orEmpty()
        assertEquals(listOf("Song Details"), actions.map { it.label })
        // An offer missing from the catalogue never invents a Details action.
        val unmatched = rule.onNodeWithTag("fst.shop.song.s-x").fetchSemanticsNode().config
        assertTrue(unmatched.getOrNull(SemanticsActions.CustomActions).isNullOrEmpty())

        rule.onNodeWithTag("fst.shop.song.s-alpha").performSemanticsAction(SemanticsActions.OnClick)
        settle()
        assertEquals(SongsFixtures.shopUrl("alpha"), openedUrl())

        rule.runOnIdle { actions.single().action() }
        waitForTag("fst.song-detail.list")
    }

    @Test
    @Config(qualifiers = "w1920dp-h1080dp-mdpi")
    fun desktopWidthCentresAFiveColumnGridNoWiderThan1040dp() {
        launch()
        waitForTag("fst.shop.grid")
        waitForTag("fst.shop.song.s-alpha")
        val grid = rule.onNodeWithTag("fst.shop.grid").fetchSemanticsNode().boundsInRoot
        val cards = listOf("s-alpha", "s-beta", "s-x").map { rule.onNodeWithTag("fst.shop.song.$it").fetchSemanticsNode().boundsInRoot }
        val expectedLeft = dp(grid.left) + (dp(grid.width) - SHOP_CONTENT_MAX_WIDTH_DP) / 2f
        val left = dp(cards.minOf { it.left })
        assertTrue("grid ${dp(grid.width)} dp should exceed the cap", dp(grid.width) > SHOP_CONTENT_MAX_WIDTH_DP + 32f)
        assertEquals("first column starts at the centred cap", expectedLeft, left, 1.5f)
        // Five columns fill the 1040 dp column: (1040 - 4 × 10) / 5 = 200 dp tiles.
        cards.forEach { assertEquals(200f, dp(it.width), 1.5f) }
    }

    @Test
    @Config(qualifiers = "w720dp-h1000dp-xhdpi", fontScale = 2f)
    fun largeTextGridCardKeepsLongTitleAndArtistInsideTheCard() {
        val long = transport().apply {
            on("/api/shop", headers = mapOf("X-FST-Publication-Id" to "7")) {
                SongsFixtures.shopJson.replace("\"b.jpg\"", "null")
                    .replace("\"title\":\"Alpha Tune\",\"artist\":\"Band One\"", "\"title\":\"$LONG_TITLE\",\"artist\":\"$LONG_ARTIST\"")
            }
        }
        launch(transport = long)
        waitForTag("fst.shop.grid")
        waitForTag("fst.shop.song.s-alpha")
        val card = rule.onNodeWithTag("fst.shop.song.s-alpha").fetchSemanticsNode().boundsInRoot
        listOf(LONG_TITLE, LONG_ARTIST).forEach { text ->
            val bounds = rule.onNodeWithText(text, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
            assertTrue("$text $bounds outside card $card", bounds.top >= card.top && bounds.bottom <= card.bottom)
        }
    }

    @Test
    @Config(qualifiers = "w720dp-h1000dp-xhdpi", fontScale = 2f)
    fun largeTextGridPillStaysInsideTheCardAboveTheTitle() {
        launch()
        waitForTag("fst.shop.grid")
        waitForTag("fst.shop.song.s-alpha")
        val card = rule.onNodeWithTag("fst.shop.song.s-alpha").fetchSemanticsNode().boundsInRoot
        val pill = rule.onNodeWithTag("fst.shop.badge.leaving.s-alpha", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val title = rule.onAllNodesWithText("Alpha Tune", useUnmergedTree = true).fetchSemanticsNodes()
            .map { it.boundsInRoot }.first { it.left >= card.left && it.right <= card.right && it.top >= card.top && it.bottom <= card.bottom }
        assertTrue("pill $pill outside card $card", pill.left >= card.left && pill.right <= card.right && pill.top >= card.top)
        assertTrue("pill $pill overlaps title $title", pill.bottom <= title.top)
    }

    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi", fontScale = 2f)
    fun largeTextKeepsRowTextsAndBadgesInsideTheirRows() {
        launch()
        waitForTag("fst.shop.song.s-beta")
        val row = rule.onNodeWithTag("fst.shop.song.s-beta").fetchSemanticsNode().boundsInRoot
        listOf("Beta Song").forEach { text ->
            val bounds = rule.onNodeWithText(text, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
            assertTrue("$text $bounds outside row $row", bounds.top >= row.top && bounds.bottom <= row.bottom)
        }
        val leavingRow = rule.onNodeWithTag("fst.shop.song.s-alpha").fetchSemanticsNode().boundsInRoot
        val leaving = rule.onNodeWithTag("fst.shop.badge.leaving.s-alpha", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        assertTrue("Leaving Tomorrow $leaving outside row $leavingRow", leaving.top >= leavingRow.top && leaving.bottom <= leavingRow.bottom)
        val link = rule.onNodeWithTag("fst.shop.external.s-beta").fetchSemanticsNode().boundsInRoot
        assertTrue("link $link outside row $row", link.left >= row.left && link.right <= row.right)

        rule.onNodeWithTag("fst.shop.filter.open").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.shop.filter.leaving")
        listOf("fst.shop.filter.new", "fst.shop.filter.available", "fst.shop.filter.leaving").forEach { tag ->
            rule.onNodeWithTag(tag).assertExists()
        }
    }
}
