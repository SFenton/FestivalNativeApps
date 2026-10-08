package com.festivalscoretracker.android.shop

import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.lifecycle.HasDefaultViewModelProviderFactory
import androidx.lifecycle.VIEW_MODEL_STORE_OWNER_KEY
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.viewmodel.CreationExtras
import androidx.lifecycle.viewmodel.MutableCreationExtras
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.journeys.JourneyHarness
import com.festivalscoretracker.android.journeys.MemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.SongsFixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Item Shop sort on a real device (issue #379, `catalogue-sort` pattern): open **Sort Item
 * Shop**, pick Duration and Descending, check the order in the layout the window shows and,
 * where Grid/List switches (unfolded book, tablet), in the other one too, then relaunch the
 * shell on the same settings store and check the saved order again. ATF runs before every
 * interaction; reading orders go to logcat `FST_A11Y`. Run with
 * `device.py test com.festivalscoretracker.android.shop.ShopSortDeviceJourneyTest --avd FST_Book_Fold`
 * (also `--posture half`: rows run across the fold, nothing straddles it).
 *
 * Fixture: s-beta ("Beta Song", 240 s), s-alpha ("Alpha Tune", 185 s), s-x ("Alpha Tune", no
 * length, which sorts as zero, like Songs).
 */
@RunWith(AndroidJUnit4::class)
class ShopSortDeviceJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val ids = listOf("s-alpha", "s-x", "s-beta")
    private val titleOrder = listOf("s-alpha", "s-x", "s-beta")
    private val longestFirst = listOf("s-beta", "s-alpha", "s-x")
    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = PUBLICATION) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        on("/api/shop", headers = PUBLICATION) { SongsFixtures.shopJson.replace("\"b.jpg\"", "null") }
    }

    // region Helpers

    /** Bumping this discards the whole shell and builds a new one: a cold relaunch on the same settings. */
    private var launches by mutableIntStateOf(0)

    /**
     * Launch the shell on the Item Shop. Each launch gets a fresh [AppContainer] and view-model
     * store, so only [preferences] carries over.
     *
     * @param preferences Settings store shared by every launch.
     */
    private fun launch(preferences: MemoryPreferences) {
        val debug = DebugLaunch(route = DebugLaunch.parseRoute("shop"), stillBackground = true)
        rule.setContent {
            key(launches) {
                val owner = remember { FreshOwner(rule.activity) }
                DisposableEffect(owner) { onDispose { owner.viewModelStore.clear() } }
                val container = remember { AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = preferences) }
                CompositionLocalProvider(LocalViewModelStoreOwner provides owner) { FestivalApp(container, debug) }
            }
        }
        awaitOffers()
    }

    private fun relaunch() {
        rule.runOnUiThread { launches++ }
        rule.waitForIdle()
        awaitOffers()
    }

    private fun awaitOffers() {
        rule.waitUntil(15_000) { h.exists("fst.shop.list") || h.exists("fst.shop.grid") }
        ids.forEach { h.waitForTag("fst.shop.song.$it") }
    }

    private fun bounds(id: String) = rule.onAllNodesWithTag("fst.shop.song.$id", useUnmergedTree = true).fetchSemanticsNodes().first().boundsInWindow

    /**
     * Offers in reading order: rows top to bottom, then cells left to right. Around a separating
     * hinge the rows run across it (the list puts one row in each pane, row-major, hinge-columns).
     */
    private fun shown(): List<String> =
        ids.filter { h.exists("fst.shop.song.$it") }.sortedWith(compareBy({ bounds(it).top }, { bounds(it).left }))

    private fun assertOrder(expected: List<String>, layout: String) {
        runCatching { rule.waitUntil(10_000) { shown() == expected } }
        assertEquals("$layout order", expected, shown())
    }

    private fun layout() = if (h.exists("fst.shop.grid")) "grid" else "list"

    private fun node(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true)[0]

    private fun sortState() = node("fst.shop.sort.open").fetchSemanticsNode().config.getOrNull(SemanticsProperties.StateDescription)

    private fun stored(preferences: MemoryPreferences, key: String) = runBlocking { preferences.data.first()[stringPreferencesKey(key)] }

    /** Check the order in the current layout, then in the other one when the window offers Grid/List. */
    private fun assertBothLayouts(expected: List<String>) {
        val first = layout()
        assertOrder(expected, first)
        if (!h.exists("fst.shop.view-toggle")) return
        h.tap("fst.shop.view-toggle")
        rule.waitUntil(15_000) { layout() != first }
        awaitOffers()
        assertOrder(expected, layout())
        h.assertNothingStraddles(*ids.map { "fst.shop.song.$it" }.toTypedArray())
    }

    // endregion

    /** Duration, descending from the sheet; grid and list follow; the choice survives a relaunch; Reset restores title order. */
    @Test
    fun sortSheetOrdersGridAndListAndPersistsAcrossRelaunch() {
        val preferences = MemoryPreferences()
        h.enableAccessibilityChecks()
        launch(preferences)
        assertOrder(titleOrder, layout())
        assertEquals("Title, ascending", sortState())

        h.tap("fst.shop.sort.open")
        h.waitForTag("fst.shop.sort.duration")
        node("fst.shop.sort.title").assertIsSelected()
        node("fst.shop.sort.ascending").assertIsSelected()
        h.tap("fst.shop.sort.duration")
        h.tap("fst.shop.sort.descending")
        node("fst.shop.sort.duration").assertIsSelected()
        node("fst.shop.sort.descending").assertIsSelected()
        h.readingOrder("shop-sort")
        h.assertNothingStraddles("fst.shop.sort.duration", "fst.shop.sort.descending", "fst.shop.sort.reset")
        h.tap("fst.shop.sort.done")
        h.waitGone("fst.shop.sort.duration")

        assertEquals("Duration, descending", sortState())
        assertEquals("Duration", stored(preferences, SettingsRegistry.SHOP_SORT))
        assertEquals("false", stored(preferences, SettingsRegistry.SHOP_SORT_ASCENDING))
        assertBothLayouts(longestFirst)
        h.readingOrder("shop-sorted")

        relaunch()
        assertEquals("Duration, descending", sortState())
        assertBothLayouts(longestFirst)

        h.tap("fst.shop.sort.open")
        h.waitForTag("fst.shop.sort.reset")
        node("fst.shop.sort.duration").assertIsSelected()
        node("fst.shop.sort.descending").assertIsSelected()
        h.tap("fst.shop.sort.reset")
        node("fst.shop.sort.title").assertIsSelected()
        h.tap("fst.shop.sort.done")
        h.waitGone("fst.shop.sort.reset")
        assertOrder(titleOrder, layout())
        assertEquals("Title, ascending", sortState())
        h.assertAccessible()
    }

    /**
     * A view-model store for one launch. It keeps the activity's factory and saved-state
     * registry (shell view models need a `SavedStateHandle`) but holds its own handles, so a
     * relaunch restores nothing but the settings store.
     *
     * @param activity Host activity.
     */
    private class FreshOwner(activity: ComponentActivity) : ViewModelStoreOwner, HasDefaultViewModelProviderFactory {
        override val viewModelStore = ViewModelStore()
        override val defaultViewModelProviderFactory: ViewModelProvider.Factory = activity.defaultViewModelProviderFactory
        override val defaultViewModelCreationExtras: CreationExtras =
            MutableCreationExtras(activity.defaultViewModelCreationExtras).apply { set(VIEW_MODEL_STORE_OWNER_KEY, this@FreshOwner) }
    }

    private companion object {
        val PUBLICATION = mapOf("X-FST-Publication-Id" to "7")
    }
}
