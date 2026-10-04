package com.festivalscoretracker.android.ui.songs

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.ComposeTimeoutException
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.isDialog
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.window.layout.FoldingFeature.Orientation
import androidx.window.layout.FoldingFeature.State
import androidx.window.testing.layout.FoldingFeature
import androidx.window.testing.layout.TestWindowLayoutInfo
import androidx.window.testing.layout.WindowLayoutInfoPublisherRule
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
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
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Every reachable Songs Sort state (issue #125, `.agents/controls/songs-sort/android.md`):
 * live-applied mode/direction/Reset, no discard confirmation, persistence, player and
 * single-chart modes, Item Shop sections and pauses, and large text.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class SongsSortUiTest {
    @get:Rule(order = 0)
    val windowInfo = WindowLayoutInfoPublisherRule()

    @get:Rule(order = 1)
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")
    private val publication = mapOf("X-FST-Publication-Id" to "7")

    private val profileJson = """
        {"accountId":"${Fixtures.ACCOUNT_A}","displayName":"Synthetic Player","totalScores":2,"scores":[
          {"si":"s-alpha","ins":"01","sc":95198,"acc":987,"fc":true,"st":6,"sn":15,"dif":3,"rk":42,"te":1000,"lp":"2026-09-01T12:00:00Z"},
          {"si":"s-beta","ins":"01","sc":5000,"acc":500,"fc":false,"st":2,"sn":9,"dif":1,"rk":900,"te":1000,"lp":"2026-09-20T12:00:00Z"}
        ]}
    """.trimIndent()

    // region Harness

    /** Catalogue Alpha Tune / Band One, Beta Song / Band Two, Échos / Band Three; Shop body per test. */
    private fun transport(shop: String? = SongsFixtures.shopJson.replace("\"b.jpg\"", "null"), shopStatus: Int = 200) = FakeTransport.standard().apply {
        on("/api/songs", headers = publication) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        if (shop != null) on("/api/shop", status = shopStatus, headers = publication) { shop }
        on("/api/player/${Fixtures.ACCOUNT_A}", headers = publication) { profileJson }
    }

    private fun prefs(vararg pairs: Preferences.Pair<*>) = InMemoryPreferences(mutablePreferencesOf(*pairs))

    private fun launch(debug: DebugLaunch = DebugLaunch(stillBackground = true), prefs: InMemoryPreferences = InMemoryPreferences(), transport: FakeTransport = transport()) {
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

    private fun waitForTag(tag: String) {
        try {
            rule.waitUntil(20_000) { settle(100); exists(tag) }
        } catch (timeout: ComposeTimeoutException) {
            throw AssertionError("Timed out waiting for $tag; present: ${tags("fst.")}", timeout)
        }
    }

    private fun waitGone(tag: String) = rule.waitUntil(10_000) { settle(100); !exists(tag) }

    private fun exists(tag: String) = rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()

    private fun click(tag: String) = rule.onNodeWithTag(tag).performSemanticsAction(SemanticsActions.OnClick)

    private fun tags(prefix: String): List<String> =
        rule.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsProperties.TestTag)).fetchSemanticsNodes()
            .map { it.config[SemanticsProperties.TestTag] }
            .filter { it.startsWith(prefix) }
            .distinct()

    /** Song row IDs in list order. */
    private fun rowOrder(): List<String> = tags("fst.songs.row.").map { it.removePrefix("fst.songs.row.") }

    private fun waitForOrder(expected: List<String>) {
        try {
            rule.waitUntil(10_000) { settle(100); rowOrder() == expected }
        } catch (timeout: ComposeTimeoutException) {
            throw AssertionError("Expected $expected, got ${rowOrder()}", timeout)
        }
    }

    private fun assertSortState(expected: String) =
        rule.onNodeWithTag("fst.songs.sort.open").assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, expected))

    private fun openSort() {
        waitForTag("fst.songs.row.s-alpha")
        click("fst.songs.sort.open")
        waitForTag("fst.songs.sort.form")
    }

    private fun closeSort() {
        click("fst.songs.sort.done")
        waitGone("fst.songs.sort.form")
    }

    private fun scrollTo(tag: String) = rule.onNodeWithTag("fst.songs.sort.form").performScrollToNode(hasTestTag(tag))

    // endregion

    // region Draft, live apply and persistence

    @Test
    fun defaultSheetShowsSavedSortAndCatalogueModes() {
        launch()
        openSort()
        assertSortState("Title, ascending")
        // The heading has its own ID, so `fst.songs.sort.title` is only the Title choice.
        rule.onNodeWithTag("fst.songs.sort.heading").assertIsDisplayed()
        assertEquals(1, rule.onAllNodesWithTag("fst.songs.sort.title").fetchSemanticsNodes().size)
        rule.onNodeWithTag("fst.songs.sort.title").assertIsSelected()
        listOf("artist", "year", "duration", "shop").forEach { rule.onNodeWithTag("fst.songs.sort.$it").assertIsNotSelected() }
        rule.onNodeWithTag("fst.songs.sort.ascending").assertIsSelected()
        rule.onNodeWithTag("fst.songs.sort.descending").assertIsNotSelected()
        listOf("mode", "direction").forEach { group ->
            assertTrue(rule.onNodeWithTag("fst.songs.sort.$group").fetchSemanticsNode().config.contains(SemanticsProperties.SelectableGroup))
        }
        // Anonymous: no player or single-chart modes, no Cancel/Apply.
        listOf("hasfc", "lastplayed", "chart-mode", "priority.0", "cancel", "apply").forEach { assertFalse(it, exists("fst.songs.sort.$it")) }
        rule.onNodeWithTag("fst.songs.sort.reset").assertIsDisplayed()
        assertEquals(listOf("s-alpha", "s-beta", "s-gamma"), rowOrder())
    }

    @Test
    fun modeDirectionAndResetApplyLiveAndCloseWithoutDiscardConfirm() {
        val store = InMemoryPreferences()
        launch(prefs = store)
        openSort()

        // changed-mode: Artist applies at once (Band One, Band Three, Band Two).
        click("fst.songs.sort.artist")
        settle()
        rule.onNodeWithTag("fst.songs.sort.artist").assertIsSelected()
        rule.onNodeWithTag("fst.songs.sort.title").assertIsNotSelected()
        waitForOrder(listOf("s-alpha", "s-gamma", "s-beta"))
        assertSortState("Artist, ascending")

        // changed-direction.
        click("fst.songs.sort.descending")
        settle()
        rule.onNodeWithTag("fst.songs.sort.descending").assertIsSelected()
        waitForOrder(listOf("s-beta", "s-gamma", "s-alpha"))
        assertSortState("Artist, descending")
        assertEquals("Artist", store.current[stringPreferencesKey(SettingsRegistry.SONG_SORT)])
        assertEquals(false, store.current[booleanPreferencesKey(SettingsRegistry.SONG_SORT_ASCENDING)])

        // reset-draft: Reset restores (and applies) Title ascending.
        click("fst.songs.sort.reset")
        settle()
        rule.onNodeWithTag("fst.songs.sort.title").assertIsSelected()
        rule.onNodeWithTag("fst.songs.sort.ascending").assertIsSelected()
        waitForOrder(listOf("s-alpha", "s-beta", "s-gamma"))
        assertSortState("Title, ascending")

        // discard-confirm is unreachable: closing after a change keeps it, with no dialog.
        click("fst.songs.sort.year")
        settle()
        closeSort()
        assertTrue(rule.onAllNodes(isDialog()).fetchSemanticsNodes().isEmpty())
        // applied: Year ascending (2019, 2021, 2023) with the gold-tint state spoken.
        waitForOrder(listOf("s-beta", "s-alpha", "s-gamma"))
        assertSortState("Year, ascending")
        assertEquals("Year", store.current[stringPreferencesKey(SettingsRegistry.SONG_SORT)])
    }

    @Test
    fun relaunchRestoresSavedModeAndDirection() {
        launch(
            prefs = prefs(
                stringPreferencesKey(SettingsRegistry.SONG_SORT) to "Duration",
                booleanPreferencesKey(SettingsRegistry.SONG_SORT_ASCENDING) to false,
            ),
        )
        // 240 s, 185 s, 95 s.
        waitForOrder(listOf("s-beta", "s-alpha", "s-gamma"))
        assertSortState("Duration, descending")
        openSort()
        rule.onNodeWithTag("fst.songs.sort.duration").assertIsSelected()
        rule.onNodeWithTag("fst.songs.sort.descending").assertIsSelected()
    }

    // endregion

    // region Player and single-chart modes

    @Test
    fun profileAddsHasFcAndLastPlayed() {
        launch(DebugLaunch(profile = player, stillBackground = true))
        openSort()
        rule.onNodeWithTag("fst.songs.sort.hasfc").assertIsNotSelected()
        click("fst.songs.sort.lastplayed")
        settle()
        rule.onNodeWithTag("fst.songs.sort.lastplayed").assertIsSelected()
        // Still no single-chart group without an instrument filter.
        assertFalse(exists("fst.songs.sort.chart-mode"))
        closeSort()
        assertSortState("Last Played, ascending")
        assertTrue(rule.onAllNodes(isDialog()).fetchSemanticsNodes().isEmpty())
    }

    @Test
    fun instrumentFilterAddsChartModesAndPriority() {
        launch(
            DebugLaunch(profile = player, stillBackground = true),
            prefs(stringPreferencesKey(SettingsRegistry.SONG_FILTERS) to """{"instrument":"Solo_Guitar"}"""),
        )
        openSort()
        assertTrue(exists("fst.songs.sort.chart-mode"))
        scrollTo("fst.songs.sort.score")
        click("fst.songs.sort.score")
        settle()
        rule.onNodeWithTag("fst.songs.sort.score").assertIsSelected()
        rule.onNodeWithTag("fst.songs.sort.title").assertIsNotSelected()
        scrollTo("fst.songs.sort.priority.0")
        rule.onNodeWithTag("fst.songs.sort.priority.0").assertIsDisplayed()
        closeSort()
        assertSortState("Score, ascending")
        // Lowest score first: Beta (5,000) before Alpha (95,198).
        rule.waitUntil(10_000) { settle(100); rowOrder().let { it.indexOf("s-beta") in 0 until it.indexOf("s-alpha") } }
        assertFalse(exists("fst.songs.sort-paused"))
    }

    // endregion

    // region Item Shop

    @Test
    fun shopSortShowsAllThreeSections() {
        launch()
        openSort()
        click("fst.songs.sort.shop")
        closeSort()
        waitForTag("fst.songs.shop-section.leaving-tomorrow")
        assertTrue(exists("fst.songs.shop-section.in-shop"))
        assertTrue(exists("fst.songs.shop-section.not-in-shop"))
        assertFalse(exists("fst.songs.sort-paused"))
        // Members first (Leaving Tomorrow, then In Shop), then the rest.
        assertEquals(listOf("s-alpha", "s-beta", "s-gamma"), rowOrder())
    }

    @Test
    fun shopSortWithEveryRowInOneBucketHasNoHeadings() {
        val all = """{"count":3,"lastUpdated":"2026-09-28T00:00:00Z","songs":[
            {"songId":"s-alpha","title":"Alpha Tune","artist":"Band One","shopUrl":"${SongsFixtures.shopUrl("alpha")}"},
            {"songId":"s-beta","title":"Beta Song","artist":"Band Two","shopUrl":"${SongsFixtures.shopUrl("beta")}"},
            {"songId":"s-gamma","title":"Échos","artist":"Band Three","shopUrl":"${SongsFixtures.shopUrl("gamma")}"}]}"""
        launch(prefs = prefs(stringPreferencesKey(SettingsRegistry.SONG_SORT) to "Shop"), transport = transport(shop = all))
        rule.waitUntil(20_000) { settle(100); rule.onAllNodesWithTag("fst.songs.shop-badge.s-alpha", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
        waitForOrder(listOf("s-alpha", "s-beta", "s-gamma"))
        assertTrue(tags("fst.songs.shop-section.").isEmpty())
        assertFalse(exists("fst.songs.sort-paused"))
    }

    @Test
    fun knownEmptyShopSortsWithoutHeadingsOrPause() {
        val empty = """{"count":0,"lastUpdated":"2026-09-28T00:00:00Z","songs":[]}"""
        launch(
            prefs = prefs(stringPreferencesKey(SettingsRegistry.SONG_SORT) to "Shop", booleanPreferencesKey(SettingsRegistry.SONG_SORT_ASCENDING) to false),
            transport = transport(shop = empty),
        )
        // Nobody is a member, so descending reverses the title tiebreak (whole-comparator direction).
        waitForOrder(listOf("s-gamma", "s-beta", "s-alpha"))
        assertTrue(tags("fst.songs.shop-section.").isEmpty())
        assertFalse(exists("fst.songs.sort-paused"))
        assertSortState("Item Shop, descending")
    }

    @Test
    fun unavailableShopPausesInSavedDirectionWithNotice() {
        launch(
            prefs = prefs(stringPreferencesKey(SettingsRegistry.SONG_SORT) to "Shop", booleanPreferencesKey(SettingsRegistry.SONG_SORT_ASCENDING) to false),
            transport = transport(shop = "{}", shopStatus = 500),
        )
        waitForTag("fst.songs.sort-paused")
        assertTrue(textOf("fst.songs.sort-paused").contains("Item Shop sort paused until Item Shop data loads"))
        // Title order in the saved (descending) direction, never empty Shop membership.
        waitForOrder(listOf("s-gamma", "s-beta", "s-alpha"))
        assertTrue(tags("fst.songs.shop-section.").isEmpty())
        openSort()
        rule.onNodeWithTag("fst.songs.sort.shop").assertIsSelected()
    }

    @Test
    fun hiddenShopRemovesChoiceAndPausesSavedShopSort() {
        launch(
            prefs = prefs(stringPreferencesKey(SettingsRegistry.SONG_SORT) to "Shop", booleanPreferencesKey(SettingsRegistry.HIDE_SHOP) to true),
        )
        waitForTag("fst.songs.sort-paused")
        assertTrue(textOf("fst.songs.sort-paused").contains("while the Item Shop is hidden"))
        waitForOrder(listOf("s-alpha", "s-beta", "s-gamma"))
        openSort()
        assertFalse(exists("fst.songs.sort.shop"))
        // Choosing another mode clears the pause.
        click("fst.songs.sort.artist")
        closeSort()
        waitGone("fst.songs.sort-paused")
    }

    private fun textOf(tag: String): String =
        rule.onNodeWithTag(tag).fetchSemanticsNode().let { node ->
            (listOf(node) + node.children).flatMap { it.config.getOrElseNullable(SemanticsProperties.Text) { null }.orEmpty() }.joinToString(" ") { it.text }
        }

    // endregion

    // region Large text

    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi", fontScale = 2f)
    fun largeTextKeepsEveryChoiceReachableAndTouchSized() {
        launch(DebugLaunch(profile = player, stillBackground = true))
        openSort()
        rule.onNodeWithTag("fst.songs.sort.heading").assertIsDisplayed()
        val density = rule.activity.resources.displayMetrics.density
        listOf("title", "artist", "year", "duration", "shop", "hasfc", "lastplayed", "ascending", "descending").forEach { mode ->
            val tag = "fst.songs.sort.$mode"
            scrollTo(tag)
            rule.onNodeWithTag(tag).assertIsDisplayed()
            val height = rule.onNodeWithTag(tag).fetchSemanticsNode().size.height / density
            assertTrue("$tag is $height dp", height >= 48f)
        }
        rule.onNodeWithTag("fst.songs.sort.reset").assertIsDisplayed()
        click("fst.songs.sort.descending")
        settle()
        closeSort()
        assertSortState("Title, descending")
    }

    // endregion

    // region Foldables

    /** Publish one fold to Jetpack WindowManager once the shell is observing it. */
    private fun fold(state: State, orientation: Orientation = Orientation.VERTICAL) {
        windowInfo.overrideWindowLayoutInfo(
            TestWindowLayoutInfo(listOf(FoldingFeature(rule.activity, state = state, orientation = orientation))),
        )
        settle()
    }

    /** Open Sort from the toolbar, or from ⋮ when a narrow pane moved the page tools there. */
    private fun openSortFromAnyBar() {
        waitForTag("fst.songs.row.s-alpha")
        if (!exists("fst.songs.sort.open")) {
            click("fst.nav.overflow")
            waitForTag("fst.songs.sort.open")
        }
        click("fst.songs.sort.open")
        waitForTag("fst.songs.sort.form")
    }

    /** Material 3: no interactive content across a hinge; the sheet keeps to the leading half. */
    @Test
    @Config(qualifiers = "w852dp-h883dp-xhdpi")
    fun halfOpenBookFoldKeepsTheSheetOffTheHinge() {
        launch()
        fold(State.HALF_OPENED)
        openSortFromAnyBar()
        val hinge = rule.activity.window.decorView.width / 2f
        listOf("heading", "done", "title", "lastplayed", "ascending", "descending", "reset").forEach { part ->
            val tag = "fst.songs.sort.$part"
            if (exists(tag)) {
                val bounds = rule.onNodeWithTag(tag).fetchSemanticsNode().boundsInWindow
                assertTrue("$tag ${bounds.right} crosses the hinge at $hinge", bounds.right <= hinge)
            }
        }
        click("fst.songs.sort.artist")
        settle()
        closeSort()
        assertSortState("Artist, ascending")
    }

    /** A flat fold is not separating: the sheet stays centred across it. */
    @Test
    @Config(qualifiers = "w852dp-h883dp-xhdpi")
    fun flatFoldKeepsTheCentredSheet() {
        launch()
        fold(State.FLAT)
        openSortFromAnyBar()
        val hinge = rule.activity.window.decorView.width / 2f
        val title = rule.onNodeWithTag("fst.songs.sort.title").fetchSemanticsNode().boundsInWindow
        assertTrue("${title.left}..${title.right} vs $hinge", title.left < hinge && title.right > hinge)
    }

    // endregion
}
