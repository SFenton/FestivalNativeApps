package com.festivalscoretracker.android.ui.shop

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performSemanticsAction
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
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
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Item Shop sort (issue #379, `.agents/pages/shop/android.md`): the Songs-style Sort sheet with
 * Title, Artist, Year and Duration plus direction, applied live to list and grid, persisted,
 * and the Duration pause without same-publication song lengths.
 *
 * Fixture order: Shop offers s-beta ("Beta Song", Band Two, 2019), s-alpha ("Alpha Tune",
 * Band One, no year) and s-x ("Alpha Tune", Other, no year); catalogue lengths s-beta 240 s,
 * s-alpha 185 s, s-x none (sorts as zero, like Songs).
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class ShopSortUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val publication = mapOf("X-FST-Publication-Id" to "7")
    private val ids = listOf("s-beta", "s-alpha", "s-x")

    // region Harness

    private fun transport(catalogFails: Boolean = false) = FakeTransport.standard().apply {
        if (catalogFails) {
            on("/api/songs", status = 500) { "" }
        } else {
            on("/api/songs", headers = publication) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        }
        on("/api/shop", headers = publication) { SongsFixtures.shopJson.replace("\"b.jpg\"", "null") }
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

    private fun exists(tag: String) = rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()

    private fun waitForTag(tag: String) {
        rule.waitUntil(10_000) {
            settle(100)
            exists(tag)
        }
    }

    private fun click(tag: String) = rule.onNodeWithTag(tag).performSemanticsAction(SemanticsActions.OnClick)

    private fun bounds(id: String) = rule.onNodeWithTag("fst.shop.song.$id").fetchSemanticsNode().boundsInRoot

    /** Offers in reading order (rows top to bottom; grid cells by row, then left to right). */
    private fun shown(): List<String> = ids.filter { exists("fst.shop.song.$it") }
        .sortedWith(compareBy({ bounds(it).top }, { bounds(it).left }))

    private fun waitForOrder(expected: List<String>) {
        rule.waitUntil(10_000) {
            settle(100)
            shown() == expected
        }
    }

    private fun sortState() = rule.onNodeWithTag("fst.shop.sort.open").fetchSemanticsNode().config.getOrNull(SemanticsProperties.StateDescription)

    private fun stored(key: String, prefs: InMemoryPreferences) = prefs.current[stringPreferencesKey(key)]

    private fun savedPrefs(mode: String, ascending: String?) = InMemoryPreferences(
        mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.SHOP_SORT) to mode).apply {
            if (ascending != null) this[stringPreferencesKey(SettingsRegistry.SHOP_SORT_ASCENDING)] = ascending
        },
    )

    // endregion

    @Test
    fun sortSheetReordersTheListLiveAndSavesTheChoice() {
        val prefs = InMemoryPreferences()
        launch(prefs)
        waitForOrder(listOf("s-alpha", "s-x", "s-beta"))
        val open = rule.onNodeWithTag("fst.shop.sort.open")
        open.assertContentDescriptionEquals("Sort Item Shop")
        assertEquals("Title, ascending", sortState())
        // Material 3 IconButton keeps a 48 dp touch target.
        val bounds = open.fetchSemanticsNode().touchBoundsInRoot
        val density = rule.activity.resources.displayMetrics.density
        assertTrue(bounds.width / density >= 48f && bounds.height / density >= 48f)

        click("fst.shop.sort.open")
        waitForTag("fst.shop.sort.artist")
        rule.onNodeWithTag("fst.shop.sort.heading").assertExists()
        rule.onNodeWithTag("fst.shop.sort.title").assertIsSelected()
        rule.onNodeWithTag("fst.shop.sort.ascending").assertIsSelected()
        click("fst.shop.sort.artist")
        click("fst.shop.sort.descending")
        settle()
        rule.onNodeWithTag("fst.shop.sort.artist").assertIsSelected()
        rule.onNodeWithTag("fst.shop.sort.title").assertIsNotSelected()
        rule.onNodeWithTag("fst.shop.sort.descending").assertIsSelected()
        click("fst.shop.sort.done")
        rule.waitUntil(10_000) { settle(100); !exists("fst.shop.sort.artist") }
        waitForOrder(listOf("s-x", "s-beta", "s-alpha"))
        assertEquals("Artist, descending", sortState())
        assertEquals("Artist", stored(SettingsRegistry.SHOP_SORT, prefs))
        assertEquals("false", stored(SettingsRegistry.SHOP_SORT_ASCENDING, prefs))

        // Year ascending: missing years sort first (as zero, like Songs).
        click("fst.shop.sort.open")
        waitForTag("fst.shop.sort.year")
        click("fst.shop.sort.year")
        click("fst.shop.sort.ascending")
        click("fst.shop.sort.done")
        waitForOrder(listOf("s-alpha", "s-x", "s-beta"))
        assertEquals("Year", stored(SettingsRegistry.SHOP_SORT, prefs))
        assertNull(stored(SettingsRegistry.SHOP_SORT_ASCENDING, prefs))

        // Reset restores Title ascending and clears the saved keys.
        click("fst.shop.sort.open")
        waitForTag("fst.shop.sort.reset")
        click("fst.shop.sort.reset")
        settle()
        rule.onNodeWithTag("fst.shop.sort.title").assertIsSelected()
        click("fst.shop.sort.done")
        waitForOrder(listOf("s-alpha", "s-x", "s-beta"))
        assertNull(stored(SettingsRegistry.SHOP_SORT, prefs))
        assertEquals("Title, ascending", sortState())
    }

    @Test
    fun savedDurationSortUsesCatalogueLengths() {
        launch(savedPrefs("Duration", null))
        waitForOrder(listOf("s-x", "s-alpha", "s-beta"))
        assertEquals("Duration, ascending", sortState())
        assertTrue(!exists("fst.shop.sort-paused"))
    }

    @Test
    @Config(qualifiers = "w1280dp-h800dp-xhdpi")
    fun gridAndListFollowTheSavedSort() {
        launch(savedPrefs("Duration", "false"))
        waitForTag("fst.shop.grid")
        waitForOrder(listOf("s-beta", "s-alpha", "s-x"))
        click("fst.shop.view-toggle")
        waitForTag("fst.shop.list")
        waitForOrder(listOf("s-beta", "s-alpha", "s-x"))
    }

    @Test
    fun durationSortPausesToTitleOrderWhenSongDetailsFail() {
        launch(savedPrefs("Duration", "false"), transport(catalogFails = true))
        waitForTag("fst.shop.sort-paused")
        // Title order in the chosen (descending) direction; the choice stays saved.
        waitForOrder(listOf("s-beta", "s-x", "s-alpha"))
        assertEquals("Duration, descending", sortState())
    }
}
