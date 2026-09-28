package com.festivalscoretracker.android.firstrun

import com.festivalscoretracker.android.core.firstrun.FirstRunCatalog
import com.festivalscoretracker.android.core.firstrun.FirstRunGate
import com.festivalscoretracker.android.core.firstrun.FirstRunGateContext
import com.festivalscoretracker.android.core.firstrun.FirstRunHashing
import com.festivalscoretracker.android.core.firstrun.FirstRunMode
import com.festivalscoretracker.android.core.firstrun.FirstRunPageKey
import com.festivalscoretracker.android.core.firstrun.FirstRunSeenRecord
import com.festivalscoretracker.android.core.firstrun.FirstRunSeenStore
import com.festivalscoretracker.android.core.firstrun.FirstRunSlide
import com.festivalscoretracker.android.core.firstrun.FirstRunSlideEvaluator
import com.festivalscoretracker.android.core.settings.MemoryBlobStore
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.CompeteTab
import com.festivalscoretracker.android.core.nav.LicensesRoute
import com.festivalscoretracker.android.core.nav.PlayerHistoryRoute
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.core.nav.RivalsRoute
import com.festivalscoretracker.android.core.nav.SettingsTab
import com.festivalscoretracker.android.core.nav.ShopRoute
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import com.festivalscoretracker.android.core.nav.SongsTab
import com.festivalscoretracker.android.core.nav.StatisticsTab
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.presentation.firstrun.FirstRunCenter
import com.festivalscoretracker.android.testing.Fixtures
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of Apple `FirstRunTests` plus Android center/catalog coverage. */
class FirstRunTest {
    private fun slide(
        id: String = "slide", version: Int = 1, title: String = "Title", description: String = "Description",
        contentKey: String? = null, gate: FirstRunGate = FirstRunGate.Always,
    ) = FirstRunSlide(id, version, title, description, contentKey, gate)

    private val now: Instant = Instant.parse("2026-09-28T12:00:00Z")

    // region Hashing

    @Test
    fun hashingIsDeterministicDistinctAndMatchesWebDjb2() {
        assertEquals(FirstRunHashing.contentHash("abc"), FirstRunHashing.contentHash("abc"))
        assertNotEquals(FirstRunHashing.contentHash("abc"), FirstRunHashing.contentHash("abd"))
        assertEquals("1505", FirstRunHashing.contentHash(""))
        assertEquals("2b606", FirstRunHashing.contentHash("a"))
        // 32-bit wraparound, unsigned hex like JS `(hash >>> 0).toString(16)`.
        val long = FirstRunHashing.contentHash("Song ListBrowse and search the entire Festival library.")
        assertTrue(long.length <= 8 && long.all { it in "0123456789abcdef" })
        // UTF-16 code units (JS charCodeAt), so an astral character hashes as two units.
        var h = 5381
        for (unit in intArrayOf(0xD83C, 0xDFB8)) h = (h shl 5) + h + unit
        assertEquals(Integer.toUnsignedString(h, 16), FirstRunHashing.contentHash("🎸"))
    }

    // endregion

    // region isUnseen

    @Test
    fun isUnseenRules() {
        assertTrue(FirstRunSlideEvaluator.isUnseen(slide(), emptyMap()))
        val target = slide(id = "s", version = 2, title = "T", description = "D")
        assertFalse(FirstRunSlideEvaluator.isUnseen(target, mapOf("s" to FirstRunSlideEvaluator.seenRecord(target, now))))
        val old = slide(id = "s", version = 1, title = "T", description = "D")
        assertTrue(FirstRunSlideEvaluator.isUnseen(target, mapOf("s" to FirstRunSlideEvaluator.seenRecord(old, now))))
        val lower = FirstRunSeenRecord(0, FirstRunHashing.contentHash("TD"), now)
        assertTrue(FirstRunSlideEvaluator.isUnseen(slide(id = "s", version = 3, title = "T", description = "D"), mapOf("s" to lower)))
        // A higher stored version with the same content is seen (strictly `>`, not `!=`).
        val higher = FirstRunSeenRecord(9, FirstRunHashing.contentHash("TD"), now)
        assertFalse(FirstRunSlideEvaluator.isUnseen(target, mapOf("s" to higher)))
        val original = slide(id = "s", title = "Old Title", description = "D")
        val edited = slide(id = "s", title = "New Title", description = "D")
        assertTrue(FirstRunSlideEvaluator.isUnseen(edited, mapOf("s" to FirstRunSlideEvaluator.seenRecord(original, now))))
    }

    @Test
    fun contentKeySharesSeenStateAcrossCopyVariants() {
        val mobile = slide(id = "s", title = "Same", description = "Mobile copy", contentKey = "shared-key")
        val desktop = slide(id = "s", title = "Same", description = "Desktop copy", contentKey = "shared-key")
        assertFalse(FirstRunSlideEvaluator.isUnseen(desktop, mapOf("s" to FirstRunSlideEvaluator.seenRecord(mobile, now))))
        val compactNav = FirstRunCatalog.songs(compact = true).first { it.id == "songs-navigation" }
        val wideNav = FirstRunCatalog.songs(compact = false).first { it.id == "songs-navigation" }
        assertNotEquals(compactNav.description, wideNav.description)
        assertFalse(FirstRunSlideEvaluator.isUnseen(wideNav, mapOf(compactNav.id to FirstRunSlideEvaluator.seenRecord(compactNav, now))))
    }

    // endregion

    // region Slide selection

    @Test
    fun slideSelection() {
        val gated = slide(id = "gated", gate = FirstRunGate.HasPlayer)
        assertTrue(FirstRunSlideEvaluator.unseenSlides(listOf(gated), FirstRunGateContext(hasPlayer = false), emptyMap()).isEmpty())
        assertEquals(listOf("gated"), FirstRunSlideEvaluator.unseenSlides(listOf(gated), FirstRunGateContext(hasPlayer = true), emptyMap()).map { it.id })
        assertTrue(FirstRunSlideEvaluator.unseenSlides(listOf(slide(id = "fresh")), FirstRunGateContext(ready = false), emptyMap()).isEmpty())

        val existing = slide(id = "existing", title = "Existing", description = "D")
        val brandNew = slide(id = "brand-new", title = "New", description = "D2")
        val onlyNew = FirstRunSlideEvaluator.unseenSlides(
            listOf(existing, brandNew), FirstRunGateContext(), mapOf("existing" to FirstRunSlideEvaluator.seenRecord(existing, now)),
        )
        assertEquals(listOf("brand-new"), onlyNew.map { it.id })

        val seenAlways = slide(id = "seen-always")
        val gatedOff = slide(id = "gated-off", gate = FirstRunGate.HasPlayer)
        val forced = FirstRunSlideEvaluator.unseenSlides(
            listOf(seenAlways, gatedOff), FirstRunGateContext(hasPlayer = false, alwaysShow = true),
            mapOf("seen-always" to FirstRunSlideEvaluator.seenRecord(seenAlways, now)),
        )
        assertEquals(listOf("seen-always"), forced.map { it.id })

        assertEquals(listOf("seen-always"), FirstRunSlideEvaluator.gatePassingSlides(listOf(seenAlways), FirstRunGateContext()).map { it.id })
        assertTrue(FirstRunSlideEvaluator.gatePassingSlides(listOf(slide(gate = FirstRunGate.ShopHighlightEnabled)), FirstRunGateContext()).isEmpty())
        assertEquals(listOf("gated"), FirstRunSlideEvaluator.allSlides(listOf(gated)).map { it.id })
        assertTrue(FirstRunGate.ExperimentalRanksEnabled.passes(FirstRunGateContext(experimentalRanksEnabled = true)))
        assertTrue(FirstRunGate.ShopHighlightEnabled.passes(FirstRunGateContext(shopHighlightEnabled = true)))
    }

    // endregion

    // region Seen store

    private fun store(blob: MemoryBlobStore = MemoryBlobStore()) = FirstRunSeenStore(blob)

    @Test
    fun storeRoundTripsMarksResetsAndIsNoOpForEmpty() = runBlocking {
        val store = store()
        assertTrue(store.load().isEmpty())
        store.markSeen(emptyList())
        assertTrue(store.load().isEmpty())
        store.markSeen(listOf(slide(id = "s", version = 2, title = "T", description = "D")), now)
        val loaded = store.load()["s"]!!
        assertEquals(2, loaded.version)
        assertEquals(FirstRunHashing.contentHash("TD"), loaded.hash)
        assertEquals(now, loaded.seenAt)
        store.save(mapOf("a" to FirstRunSeenRecord(1, "h1", now), "b" to FirstRunSeenRecord(2, "h2", now)))
        assertEquals(2, store.load().size)
        store.markSeen(listOf(slide(id = "keep"), slide(id = "drop")), now)
        store.resetPage(listOf("drop"))
        store.resetPage(emptyList())
        assertNotNull(store.load()["keep"])
        assertNull(store.load()["drop"])
        store.resetAll()
        assertTrue(store.load().isEmpty())
    }

    @Test
    fun corruptOversizedAndMalformedRecordsRecover() = runBlocking {
        assertTrue(store(MemoryBlobStore("not json at all {{{")).load().isEmpty())
        assertTrue(store(MemoryBlobStore("[1,2]")).load().isEmpty())
        assertTrue(store(MemoryBlobStore("A".repeat(300 * 1024))).load().isEmpty())
        val json = """
            {
              "valid": {"version": 1, "hash": "abc", "seenAt": "2024-01-01T00:00:00Z"},
              "negative-version": {"version": -1, "hash": "abc", "seenAt": "2024-01-01T00:00:00Z"},
              "empty-hash": {"version": 1, "hash": "", "seenAt": "2024-01-01T00:00:00Z"},
              "numeric-hash": {"version": 1, "hash": 12, "seenAt": "2024-01-01T00:00:00Z"},
              "bad-date": {"version": 1, "hash": "abc", "seenAt": "yesterday"},
              "not-object": 5
            }
        """.trimIndent()
        val loaded = store(MemoryBlobStore(json)).load()
        assertEquals(setOf("valid"), loaded.keys)
    }

    @Test
    fun storeIsBoundedKeepingMostRecent() = runBlocking {
        val store = store()
        val storage = (0 until FirstRunSeenStore.MAX_RECORDS + 5).associate { i ->
            "slide-$i" to FirstRunSeenRecord(1, "h", Instant.ofEpochSecond(i.toLong()))
        }
        store.save(storage)
        val loaded = store.load()
        assertEquals(FirstRunSeenStore.MAX_RECORDS, loaded.size)
        assertNull(loaded["slide-0"])
        assertNotNull(loaded["slide-${FirstRunSeenStore.MAX_RECORDS + 4}"])
        store.markSeen(listOf(slide(id = "newest")), Instant.ofEpochSecond(10_000))
        assertNotNull(store.load()["newest"])
        assertEquals(FirstRunSeenStore.MAX_RECORDS, store.load().size)
    }

    // endregion

    // region Catalog

    @Test
    fun catalogShape() {
        FirstRunPageKey.entries.forEach { page ->
            val ids = FirstRunCatalog.slides(page).map { it.id }
            assertTrue(ids.isNotEmpty())
            assertEquals(ids.size, ids.toSet().size)
        }
        val all = FirstRunPageKey.entries.flatMap { FirstRunCatalog.slides(it) }.map { it.id }
        assertEquals(all.size, all.toSet().size)
        assertEquals(42, all.size)
        assertEquals(9, FirstRunCatalog.songs(true).size)
        listOf("songs-shop-highlight", "songs-new-in-shop", "songs-leaving-tomorrow").forEach { id ->
            assertEquals(FirstRunGate.ShopHighlightEnabled, FirstRunCatalog.songs(true).first { it.id == id }.gate)
        }
        listOf("songs-filter", "songs-icons", "songs-metadata").forEach { id ->
            assertEquals(FirstRunGate.HasPlayer, FirstRunCatalog.songs(true).first { it.id == id }.gate)
        }
        assertEquals(FirstRunGate.ExperimentalRanksEnabled, FirstRunCatalog.leaderboards.first { it.id == "leaderboards-experimental-metrics" }.gate)
        assertEquals(
            setOf("songs", "songinfo", "playerhistory", "statistics", "suggestions", "leaderboards", "compete", "rivals", "shop"),
            FirstRunPageKey.entries.map { it.key }.toSet(),
        )
        assertEquals("Score History", FirstRunPageKey.PlayerHistory.label)
    }

    @Test
    fun routeMapping() {
        assertEquals(FirstRunPageKey.Songs, FirstRunPageKey.forRoute(SongsTab))
        assertEquals(FirstRunPageKey.SongInfo, FirstRunPageKey.forRoute(SongDetailRoute("x")))
        assertEquals(FirstRunPageKey.PlayerHistory, FirstRunPageKey.forRoute(PlayerHistoryRoute("x", "Solo_Guitar")))
        assertEquals(FirstRunPageKey.Statistics, FirstRunPageKey.forRoute(StatisticsTab))
        assertEquals(FirstRunPageKey.Statistics, FirstRunPageKey.forRoute(PlayerRoute(Fixtures.ACCOUNT_A)))
        assertEquals(FirstRunPageKey.Compete, FirstRunPageKey.forRoute(CompeteTab))
        assertEquals(FirstRunPageKey.Rivals, FirstRunPageKey.forRoute(RivalsRoute))
        assertEquals(FirstRunPageKey.Shop, FirstRunPageKey.forRoute(ShopRoute))
        assertNull(FirstRunPageKey.forRoute(SettingsTab))
        assertNull(FirstRunPageKey.forRoute(LicensesRoute))
        assertNull(FirstRunPageKey.forRoute(null))
    }

    @Test
    fun modeParsing() {
        assertEquals(FirstRunMode.Off, FirstRunMode.parse(null, debugBuild = true))
        assertEquals(FirstRunMode.Normal, FirstRunMode.parse(" ON ", debugBuild = true))
        assertEquals(FirstRunMode.Force, FirstRunMode.parse("force", debugBuild = true))
        assertEquals(FirstRunMode.Off, FirstRunMode.parse("off", debugBuild = true))
        assertEquals(FirstRunMode.Normal, FirstRunMode.parse("off", debugBuild = false))
    }

    // endregion

    // region Center

    @Test
    fun centerShowsOnlyUnseenAndOneCarouselAtATime() = runBlocking {
        val center = FirstRunCenter(store(), FirstRunMode.Normal) { now }
        val anonymous = AppSettings()
        val first = center.tryBegin(FirstRunPageKey.Songs, anonymous, compact = true)!!
        // Anonymous with Shop highlighting on: 3 ungated + 3 shop slides.
        assertEquals(listOf("songs-song-list", "songs-sort", "songs-navigation", "songs-shop-highlight", "songs-new-in-shop", "songs-leaving-tomorrow"), first.slides.map { it.id })
        assertEquals("Slide 2 of 6", first.position(1))
        assertNull(center.tryBegin(FirstRunPageKey.Leaderboards, anonymous, compact = true))
        assertNull(center.beginReplay(FirstRunPageKey.Leaderboards, compact = true))
        center.complete(first)
        assertNull(center.active.value)
        center.complete(first) // stale: no-op

        // Selecting a player later surfaces only the newly eligible slides.
        val player = anonymous.copy(selectedPlayer = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"))
        assertEquals(listOf("songs-filter", "songs-icons", "songs-metadata"), center.tryBegin(FirstRunPageKey.Songs, player, true)!!.slides.map { it.id })
        center.complete(center.active.value!!)
        assertNull(center.tryBegin(FirstRunPageKey.Songs, player, false))
    }

    @Test
    fun replayIgnoresGatesAndSeenStateAndShopUsesFixedContext() = runBlocking {
        val store = store()
        val center = FirstRunCenter(store, FirstRunMode.Normal) { now }
        val hidden = AppSettings(hideShop = true)
        assertTrue(center.pendingSlides(FirstRunPageKey.Songs, hidden, true).none { it.gate == FirstRunGate.ShopHighlightEnabled })
        // Shop page always evaluates shopHighlightEnabled = true, hasPlayer = false (web ShopPage.tsx).
        assertEquals(4, center.pendingSlides(FirstRunPageKey.Shop, hidden, true).size)
        val replay = center.beginReplay(FirstRunPageKey.Songs, compact = false)!!
        assertTrue(replay.isReplay)
        assertEquals(9, replay.slides.size)
        center.complete(replay)
        assertEquals(9, store.load().size)
        assertTrue(center.pendingSlides(FirstRunPageKey.Songs, AppSettings(), true).isEmpty())
    }

    @Test
    fun offModeShowsNothingAndForceIgnoresSeenState() = runBlocking {
        val store = store()
        assertNull(FirstRunCenter(store, FirstRunMode.Off).tryBegin(FirstRunPageKey.Rivals, AppSettings(), true))
        val forced = FirstRunCenter(store, FirstRunMode.Force) { now }
        val carousel = forced.tryBegin(FirstRunPageKey.Rivals, AppSettings(), true)!!
        forced.complete(carousel)
        assertEquals(3, forced.tryBegin(FirstRunPageKey.Rivals, AppSettings(), true)!!.slides.size)
        assertTrue(forced.context(FirstRunPageKey.Rivals, AppSettings()).alwaysShow)
    }

    // endregion
}
