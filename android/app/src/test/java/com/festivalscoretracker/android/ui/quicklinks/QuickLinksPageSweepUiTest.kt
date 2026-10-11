package com.festivalscoretracker.android.ui.quicklinks

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.nav.CompeteRoute
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.nav.RivalryRoute
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.core.songs.SongSortMode
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.BandFixtures
import com.festivalscoretracker.android.testing.CompeteFixtures
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import com.festivalscoretracker.android.testing.RivalsFixtures
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
 * Issue #158 (Android check of #50 / #11): every other Quick Links page lists its sections in the
 * order the page shows them, top to bottom (left to right within a row), from the compact
 * floating-toolbar sheet and the wider top-app-bar menu alike. Settings and the player page are in
 * [QuickLinksPageOrderUiTest]; Songs runs every bucketed sort (and one descending sort) here.
 *
 * The page order is read from the rendered page, not from the Quick Links model: the list is
 * scrolled through and each section's on-page anchor is recorded by its on-screen position. Song
 * Detail also proves that Score History is listed exactly when the page shows its card. Rivalry
 * is checked for having no entry point at all (owner, #545).
 */
@RunWith(AndroidJUnit4::class)
class QuickLinksPageSweepUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    // region Harness

    private fun songsTransport(base: FakeTransport) = base.apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
    }

    private fun launch(debug: DebugLaunch, transport: FakeTransport, prefs: InMemoryPreferences = InMemoryPreferences()) {
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

    private fun exists(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun waitForTag(tag: String) {
        try {
            rule.waitUntil(10_000) {
                settle(100)
                exists(tag)
            }
        } catch (e: Throwable) {
            val tags = rule.onAllNodes(SemanticsMatcher("any") { it.config.getOrNull(SemanticsProperties.TestTag) != null }, useUnmergedTree = true)
                .fetchSemanticsNodes().map { it.config[SemanticsProperties.TestTag] }
            throw AssertionError("$tag never appeared; laid-out tags: $tags", e)
        }
    }

    private fun tagged(prefix: String) = SemanticsMatcher("tag starts with $prefix") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith(prefix) == true }

    // endregion

    // region Menu and page readers

    /** Items currently laid out in the open sheet or menu, top to bottom on screen. */
    private fun visibleItems(): List<String> = rule.onAllNodes(tagged(ITEM)).fetchSemanticsNodes()
        .sortedBy { it.positionInRoot.y }
        .map { it.config[SemanticsProperties.TestTag].removePrefix(ITEM) }

    /**
     * Opens Quick Links and reads every item in on-screen order (scrolling the lazy sheet). It is
     * left open: the page is read before this, and each test ends here.
     */
    private fun menuOrder(sheet: Boolean): List<String> {
        waitForTag(OPEN)
        rule.onNodeWithTag(OPEN).performSemanticsAction(SemanticsActions.OnClick)
        settle()
        val container = if (sheet) SHEET else MENU
        waitForTag(container)
        assertFalse("compact windows use the sheet, wider ones the menu", exists(if (sheet) MENU else SHEET))
        val seen = visibleItems().toMutableList()
        var index = 0
        while (sheet && index < seen.size) {
            rule.onNodeWithTag(LIST).performScrollToIndex(index++)
            settle(100)
            visibleItems().filterNot { it in seen }.forEach(seen::add)
        }
        return seen
    }

    /** Section IDs whose anchors are laid out now, top to bottom then start to end. */
    private fun anchorsOnScreen(sectionOf: (String) -> String?): List<String> =
        rule.onAllNodes(SemanticsMatcher("any tag") { it.config.getOrNull(SemanticsProperties.TestTag) != null }, useUnmergedTree = true)
            .fetchSemanticsNodes()
            .mapNotNull { node -> sectionOf(node.config[SemanticsProperties.TestTag])?.let { it to node.positionInRoot } }
            .sortedWith(compareBy({ it.second.y.toInt() }, { it.second.x }))
            .map { it.first }

    /**
     * The page's sections in on-screen order. A lazy page is walked item by item from the top:
     * anchors first laid out in a later step sit below every earlier one, and anchors that appear
     * together are ordered by position. A plain scrolling column lays everything out at once.
     *
     * @param pageTag Lazy list/grid (or scrolling column) test tag.
     * @param lazy Whether the page is a lazy list or grid.
     * @param sectionOf Section ID of an anchor tag, or null for other nodes.
     */
    private fun pageOrder(pageTag: String, lazy: Boolean = true, sectionOf: (String) -> String?): List<String> {
        if (!lazy) return anchorsOnScreen(sectionOf).distinct()
        val seen = mutableListOf<String>()
        var index = 0
        while (index < MAX_ITEMS) {
            val moved = runCatching { rule.onNodeWithTag(pageTag).performScrollToIndex(index) }.isSuccess
            if (!moved) break
            settle(100)
            anchorsOnScreen(sectionOf).filterNot { it in seen }.forEach(seen::add)
            index++
        }
        rule.onNodeWithTag(pageTag).performScrollToIndex(0)
        settle()
        return seen
    }

    private fun assertSameOrder(menu: List<String>, page: List<String>, context: String = "") {
        assertEquals("$context every section is listed once: $menu", menu.size, menu.toSet().size)
        assertEquals("$context Quick Links list the page's sections top to bottom", page, menu)
    }

    /** Closes the open sheet or menu by choosing [first] (Back would also pop a pushed page). */
    private fun closeQuickLinks(sheet: Boolean, first: String) {
        if (sheet) {
            rule.onNodeWithTag(LIST).performScrollToIndex(0)
            settle(100)
        }
        rule.onNodeWithTag(ITEM + first).performSemanticsAction(SemanticsActions.OnClick)
        rule.waitUntil(10_000) {
            settle(100)
            !exists(SHEET) && !exists(MENU)
        }
    }

    // endregion

    // region Song Detail

    private fun songDetailSection(tag: String): String? = when {
        tag == "fst.song-detail.intensity" -> "intensity"
        tag == "fst.song-detail.history.card" -> "score-history"
        tag.startsWith("fst.song-detail.preview.") -> tag.removePrefix("fst.song-detail.preview.").takeIf { '.' !in it }?.let { "instrument-$it" }
        tag.startsWith("fst.song-detail.band-preview.") -> tag.removePrefix("fst.song-detail.band-preview.").takeIf { '.' !in it }?.let { "band-$it" }
        else -> null
    }

    private fun songDetail(songId: String, player: Boolean, sheet: Boolean): List<String> {
        val transport = songsTransport(FakeTransport.standard()).apply { ProfileFixtures.register(this) }
        val profile = if (player) SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player") else null
        launch(DebugLaunch(route = SongDetailRoute(songId), profile = profile, anonymous = !player, stillBackground = true), transport)
        waitForTag("fst.song-detail.intensity")
        val page = pageOrder("fst.song-detail.list", sectionOf = ::songDetailSection)
        val menu = menuOrder(sheet)
        assertSameOrder(menu, page)
        assertEquals("Intensity leads", "intensity", menu.first())
        assertTrue("one link per chart: $menu", menu.count { it.startsWith("instrument-") } >= 2)
        assertEquals("band sizes come last: $menu", listOf("band-Band_Duets", "band-Band_Trios", "band-Band_Quad"), menu.takeLast(3))
        return menu
    }

    /** Phone, selected player with history on this song: Score History follows Intensity, as on the page. */
    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi")
    fun songDetailSheetWithScoreHistory() {
        val menu = songDetail("s-alpha", player = true, sheet = true)
        assertEquals("score-history", menu[1])
    }

    /** Wide window: the menu matches the two-column page (left card before right card in a row). */
    @Test
    @Config(qualifiers = "w1280dp-h800dp-xhdpi")
    fun songDetailMenuWithScoreHistory() {
        val menu = songDetail("s-alpha", player = true, sheet = false)
        assertEquals("score-history", menu[1])
    }

    /** No selected player: the page has no Score History card and Quick Links have no entry for it. */
    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi")
    fun songDetailWithoutPlayerHasNoScoreHistory() {
        val menu = songDetail("s-alpha", player = false, sheet = true)
        assertFalse(menu.toString(), "score-history" in menu)
        assertFalse(exists("fst.song-detail.history.card"))
    }

    /** A selected player with no history on this song: the same check hides both the card and its link. */
    @Test
    @Config(qualifiers = "w1280dp-h800dp-xhdpi")
    fun songDetailPlayerWithoutHistoryHasNoScoreHistory() {
        val menu = songDetail("s-beta", player = true, sheet = false)
        assertFalse(menu.toString(), "score-history" in menu)
        assertFalse(exists("fst.song-detail.history.card"))
    }

    // endregion

    // region Compete

    private fun compete(sheet: Boolean) {
        launch(DebugLaunch(route = if (sheet) null else CompeteRoute, section = FestivalSection.Compete.takeIf { sheet }, profile = SelectedPlayer(CompeteFixtures.PLAYER, "Synthetic Player"), stillBackground = true), CompeteFixtures.transport())
        waitForTag("fst.compete.section.leaderboards")
        val page = pageOrder("fst.compete.grid") { tag -> tag.removePrefix("fst.compete.section.").takeIf { it != tag } }
        val menu = menuOrder(sheet)
        assertSameOrder(menu, page)
        assertEquals(listOf("leaderboards", "rivals"), menu)
    }

    /** Phone: Leaderboards, then Rivals. */
    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi")
    fun competeSheetFollowsThePage() = compete(sheet = true)

    /** Wide window: Leaderboards, then Rivals. */
    @Test
    @Config(qualifiers = "w1280dp-h800dp-xhdpi")
    fun competeMenuFollowsThePage() = compete(sheet = false)

    // endregion

    // region Leaderboards

    private fun leaderboardsSection(tag: String): String? = when {
        tag == "fst.leaderboards.rank-history" -> "rank-history"
        tag.startsWith("fst.leaderboards.card.") -> tag.removePrefix("fst.leaderboards.card.").takeIf { '.' !in it }?.let { "instrument:$it" }
        tag.startsWith("fst.leaderboards.band-card.") -> tag.removePrefix("fst.leaderboards.band-card.").takeIf { '.' !in it }?.let { "band:$it" }
        else -> null
    }

    private fun leaderboards(sheet: Boolean) {
        val transport = RankingsFixtures.install(songsTransport(FakeTransport.standard()), unranked = setOf("Solo_Bass"))
        launch(DebugLaunch(route = DebugLaunch.parseRoute("leaderboards"), profile = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player"), stillBackground = true), transport)
        waitForTag("fst.leaderboards.rank-history")
        // The wide Rank History chart can fill the first screen: wait until the chart cards load below it.
        rule.waitUntil(10_000) {
            settle(100)
            runCatching { rule.onNodeWithTag("fst.leaderboards").performScrollToNode(hasTestTag("fst.leaderboards.card.Solo_Guitar")) }.isSuccess
        }
        val page = pageOrder("fst.leaderboards", sectionOf = ::leaderboardsSection)
        val menu = menuOrder(sheet)
        assertSameOrder(menu, page)
        assertEquals("Rank History leads with a selected player", "rank-history", menu.first())
    }

    /** Phone: Rank History, each chart, then each band size. */
    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi")
    fun leaderboardsSheetFollowsThePage() = leaderboards(sheet = true)

    /** Wide window: the multi-column overview reads row by row, left to right. */
    @Test
    @Config(qualifiers = "w1280dp-h800dp-xhdpi")
    fun leaderboardsMenuFollowsThePage() = leaderboards(sheet = false)

    // endregion

    // region Band Detail

    private fun bandSection(tag: String): String? = mapOf(
        "fst.band.members-section" to "members",
        "fst.band.summary-section" to "summary",
        "fst.band.statistics-section" to "statistics",
        "fst.band.history-section" to "rank-history",
        "fst.band.songs-section" to "songs",
    )[tag]

    /** Phone: Members, Summary, Statistics, Rank History, Songs (the one-column page; two panes have no Quick Links). */
    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi")
    fun bandDetailSheetFollowsThePage() {
        val transport = BandFixtures.install(songsTransport(FakeTransport.standard()))
        launch(DebugLaunch(route = DebugLaunch.parseRoute("band:${BandFixtures.DUO_ID}:Band_Duets:${BandFixtures.DUO_KEY}"), stillBackground = true), transport)
        waitForTag("fst.band.members-section")
        waitForTag("fst.band.songs-section")
        val page = pageOrder("fst.band.content", lazy = false, sectionOf = ::bandSection)
        val menu = menuOrder(sheet = true)
        assertSameOrder(menu, page)
        assertEquals(5, menu.size)
    }

    // endregion

    // region Rivals

    private val rivalsPlayer = SelectedPlayer(RivalsFixtures.PLAYER, "Synthetic Player")

    private fun rivalsTransport() = songsTransport(RivalsFixtures.transport())

    private fun rivalsHub(sheet: Boolean, leaderboardTab: Boolean) {
        launch(DebugLaunch(route = DebugLaunch.parseRoute("rivals"), profile = rivalsPlayer, stillBackground = true), rivalsTransport())
        waitForTag("fst.rivals.section.common")
        if (leaderboardTab) {
            rule.onNodeWithTag("fst.rivals.tab.leaderboard").performSemanticsAction(SemanticsActions.OnClick)
            waitForTag("fst.rivals.section.leaderboard.Solo_Guitar")
        }
        val page = pageOrder("fst.rivals.grid") { tag -> tag.removePrefix("fst.rivals.section.").takeIf { it != tag } }
        val menu = menuOrder(sheet)
        assertSameOrder(menu, page)
        assertTrue(menu.toString(), menu.size >= 2)
        if (!leaderboardTab) assertEquals("Common Rivals leads", "common", menu.first())
    }

    /** Phone, Song Rivals tab: Common Rivals, then each chart card. */
    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi")
    fun rivalsSheetFollowsThePage() = rivalsHub(sheet = true, leaderboardTab = false)

    /** Wide window, Song Rivals tab: the multi-column grid reads row by row. */
    @Test
    @Config(qualifiers = "w1280dp-h800dp-xhdpi")
    fun rivalsMenuFollowsThePage() = rivalsHub(sheet = false, leaderboardTab = false)

    /** Phone, Leaderboard Rivals tab: one card per chart. */
    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi")
    fun leaderboardRivalsSheetFollowsThePage() = rivalsHub(sheet = true, leaderboardTab = true)

    private fun rivalDetail(sheet: Boolean) {
        launch(DebugLaunch(route = DebugLaunch.parseRoute("rivals"), profile = rivalsPlayer, stillBackground = true), rivalsTransport())
        waitForTag("fst.rivals.row.${RivalsFixtures.RIVALS[1]}")
        rule.onAllNodesWithTag("fst.rivals.row.${RivalsFixtures.RIVALS[1]}")[0].performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.rival-detail.title")
        val page = pageOrder("fst.rival-detail.grid") { tag -> tag.removePrefix("fst.rival-detail.category.").takeIf { it != tag }?.let { "rival-category:$it" } }
        val menu = menuOrder(sheet)
        assertSameOrder(menu, page)
        assertTrue(menu.toString(), menu.size >= 2)
    }

    /** Phone: one link per comparison category, in page order. */
    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi")
    fun rivalDetailSheetFollowsThePage() = rivalDetail(sheet = true)

    /** Wide window: categories sit in a multi-column grid; the menu reads it row by row. */
    @Test
    @Config(qualifiers = "w1280dp-h800dp-xhdpi")
    fun rivalDetailMenuFollowsThePage() = rivalDetail(sheet = false)

    /**
     * Rivalry has no Quick Links (owner, #545): its one link per song only repeated the list, so
     * neither the compact floating toolbar nor the wide top app bar offers an entry point.
     */
    private fun rivalry() {
        launch(DebugLaunch(route = RivalryRoute(RivalsFixtures.RIVALS[3], "almost_passed"), profile = rivalsPlayer, section = FestivalSection.Songs, stillBackground = true), rivalsTransport())
        waitForTag("fst.rivalry.title")
        val page = pageOrder("fst.rivalry.list") { tag -> tag.removePrefix("fst.rivals.song.").takeIf { it != tag } }
        assertTrue("several songs on the page: $page", page.size >= 2)
        assertFalse("Rivalry offers no Quick Links", exists(OPEN))
        assertTrue("Sort stays", exists("fst.rivalry.sort"))
        assertTrue("View Profile stays", exists("fst.rival-detail.view-profile"))
    }

    /** Phone: no Quick Links in the floating toolbar. */
    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi")
    fun rivalryHasNoQuickLinksOnPhone() = rivalry()

    /** Wide window: no Quick Links in the top app bar. */
    @Test
    @Config(qualifiers = "w1280dp-h800dp-xhdpi")
    fun rivalryHasNoQuickLinksInWideWindow() = rivalry()

    // endregion

    // region Songs

    private fun songsBucketTransport() = FakeTransport.standard().apply {
        on("/api/songs", headers = PUBLICATION) { SONGS_CATALOGUE }
        on("/api/shop", headers = PUBLICATION) { SongsFixtures.shopJson.replace("\"b.jpg\"", "null") }
        on("/api/player/${Fixtures.ACCOUNT_A}", headers = PUBLICATION) { SONGS_PROFILE }
    }

    /** Menu ID of a rendered bucket header: `fst.songs.section.<mode>.<token>` or `fst.songs.shop-section.<token>`. */
    private fun songsSection(tag: String): String? = when {
        tag.startsWith(SHOP_HEADER) -> "${SongSortMode.Shop.webId}:${tag.removePrefix(SHOP_HEADER)}"
        tag.startsWith(BUCKET_HEADER) -> tag.removePrefix(BUCKET_HEADER).replaceFirst('.', ':')
        else -> null
    }

    /** Applies [mode] and [ascending] through the Sort sheet and waits for that sort's headers. */
    private fun applySort(mode: SongSortMode, ascending: Boolean) {
        rule.onNodeWithTag("fst.songs.sort.open").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.songs.sort.form")
        val option = "fst.songs.sort.${mode.name.lowercase()}"
        val direction = if (ascending) "fst.songs.sort.ascending" else "fst.songs.sort.descending"
        listOf(option, direction).forEach { tag ->
            rule.onNodeWithTag("fst.songs.sort.form").performScrollToNode(hasTestTag(tag))
            rule.onNodeWithTag(tag).performSemanticsAction(SemanticsActions.OnClick)
            settle(100)
        }
        rule.onNodeWithTag("fst.songs.sort.done").performSemanticsAction(SemanticsActions.OnClick)
        val header = if (mode == SongSortMode.Shop) SHOP_HEADER else "$BUCKET_HEADER${mode.webId}."
        rule.waitUntil(10_000) {
            settle(100)
            !exists("fst.songs.sort.form") && rule.onAllNodes(tagged(header), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
        }
    }

    /**
     * Every bucketed sort (all but Title and Artist, which use the section index) in turn: the
     * rendered sticky headers, read top to bottom, match the Quick Links items one for one.
     */
    private fun songs(sheet: Boolean) {
        val prefs = InMemoryPreferences(mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.SONG_FILTERS) to """{"instrument":"Solo_Guitar"}"""))
        launch(DebugLaunch(profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), stillBackground = true), songsBucketTransport(), prefs)
        waitForTag("fst.songs.row.s-alpha")
        val sorts = SongSortMode.entries.filterNot { it.usesSectionIndex }.map { it to true } + (SongSortMode.Duration to false)
        val menus = mutableMapOf<Pair<SongSortMode, Boolean>, List<String>>()
        for ((mode, ascending) in sorts) {
            val context = "${mode.name} ${if (ascending) "ascending" else "descending"}:"
            applySort(mode, ascending)
            val page = pageOrder("fst.songs.list", sectionOf = ::songsSection)
            val menu = menuOrder(sheet)
            assertSameOrder(menu, page, context)
            assertTrue("$context several buckets: $menu", menu.size >= 2)
            assertTrue("$context only this sort's buckets: $menu", menu.all { it.startsWith("${mode.webId}:") })
            menus[mode to ascending] = menu
            closeQuickLinks(sheet, menu.first())
        }
        assertEquals("Descending lists the buckets in reverse", menus.getValue(SongSortMode.Duration to true).reversed(), menus.getValue(SongSortMode.Duration to false))
    }

    /** Phone: each sort's buckets in the toolbar sheet, scrolled through. */
    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi")
    fun songsSheetFollowsTheBucketsForEverySort() = songs(sheet = true)

    /** Wide window (two panes): each sort's buckets in the top-bar menu. */
    @Test
    @Config(qualifiers = "w1280dp-h800dp-xhdpi")
    fun songsMenuFollowsTheBucketsForEverySort() = songs(sheet = false)

    // endregion

    private companion object {
        const val OPEN = "fst.quick-links.open"
        const val SHEET = "fst.quick-links.sheet"
        const val MENU = "fst.quick-links.menu"
        const val LIST = "fst.quick-links.list"
        const val ITEM = "fst.quick-links.item."
        const val MAX_ITEMS = 80
        const val BUCKET_HEADER = "fst.songs.section."
        const val SHOP_HEADER = "fst.songs.shop-section."
        val PUBLICATION = mapOf("X-FST-Publication-Id" to "7")

        /**
         * Nine Lead charts spread over every catalogue bucket (decades, minutes, intensities and
         * Shop states with [SongsFixtures.shopJson]) and, with [SONGS_PROFILE], every score bucket.
         */
        val SONGS_CATALOGUE: String = listOf(
            """{"songId":"s-alpha","title":"Alpha Tune","artist":"Band One","year":2021,"durationSeconds":185,"difficulty":{"guitar":3},"maxScores":{"Solo_Guitar":1150000}}""",
            """{"songId":"s-beta","title":"Beta Song","artist":"Band Two","year":2019,"durationSeconds":240,"difficulty":{"guitar":5},"maxScores":{"Solo_Guitar":1100000}}""",
            """{"songId":"s-gamma","title":"Gamma Ray","artist":"Band Three","year":1998,"durationSeconds":95,"difficulty":{"guitar":6},"maxScores":{"Solo_Guitar":700000}}""",
            """{"songId":"s-delta","title":"Delta Blues","artist":"Band Four","year":1985,"durationSeconds":45,"difficulty":{"guitar":0},"maxScores":{"Solo_Guitar":400000}}""",
            """{"songId":"s-epsilon","title":"Epsilon","artist":"Band Five","year":2005,"durationSeconds":330,"difficulty":{"guitar":1},"maxScores":{"Solo_Guitar":500000}}""",
            """{"songId":"s-zeta","title":"Zeta Waves","artist":"Band Six","year":1972,"durationSeconds":610,"difficulty":{"guitar":2},"maxScores":{"Solo_Guitar":402000}}""",
            """{"songId":"s-eta","title":"Eta Unknown","artist":"Band Seven","difficulty":{"guitar":4}}""",
            """{"songId":"s-theta","title":"Theta Line","artist":"Band Eight","year":2012,"durationSeconds":150,"difficulty":{"guitar":4},"maxScores":{"Solo_Guitar":900000}}""",
            """{"songId":"s-iota","title":"Iota Drift","artist":"Band Nine","year":2016,"durationSeconds":455,"difficulty":{"guitar":2},"maxScores":{"Solo_Guitar":300000}}""",
        ).let { """{"count":${it.size},"currentSeason":15,"songs":[${it.joinToString(",")}]}""" }

        /** Lead scores with mixed FC, stars, seasons, ranks, difficulties and play dates; Epsilon and Eta unplayed. */
        val SONGS_PROFILE: String = listOf(
            """{"si":"s-alpha","ins":"01","sc":1150000,"acc":1000,"fc":true,"st":6,"sn":15,"dif":3,"rk":3,"te":1000,"lp":"2026-09-01T12:00:00Z"}""",
            """{"si":"s-beta","ins":"01","sc":1050000,"acc":990,"fc":false,"st":5,"sn":12,"dif":2,"rk":40,"te":1000,"lp":"2025-01-20T12:00:00Z"}""",
            """{"si":"s-gamma","ins":"01","sc":620000,"acc":955,"fc":false,"st":4,"sn":9,"dif":1,"rk":300,"te":1000,"lp":"2024-05-02T12:00:00Z"}""",
            """{"si":"s-delta","ins":"01","sc":180000,"acc":800,"fc":false,"st":2,"sn":3,"dif":0,"rk":900,"te":1000,"lp":"2023-03-02T12:00:00Z"}""",
            """{"si":"s-zeta","ins":"01","sc":401500,"acc":930,"fc":true,"st":3,"sn":15,"dif":3,"rk":120,"te":1000,"lp":"2026-08-15T12:00:00Z"}""",
            """{"si":"s-theta","ins":"01","sc":760000,"acc":975,"fc":false,"st":5,"sn":11,"dif":2,"rk":60,"te":1000,"lp":"2026-06-15T12:00:00Z"}""",
            """{"si":"s-iota","ins":"01","sc":250000,"acc":910,"fc":false,"st":4,"sn":7,"dif":1,"rk":15,"te":1000,"lp":"2022-11-11T12:00:00Z"}""",
        ).let { """{"accountId":"${Fixtures.ACCOUNT_A}","displayName":"Synthetic Player","totalScores":${it.size},"scores":[${it.joinToString(",")}]}""" }
    }
}
