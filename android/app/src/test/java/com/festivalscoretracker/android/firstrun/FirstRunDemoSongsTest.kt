package com.festivalscoretracker.android.firstrun

import com.festivalscoretracker.android.core.firstrun.FirstRunDemoSongs
import com.festivalscoretracker.android.core.shop.ShopPayload
import com.festivalscoretracker.android.core.shop.ShopResponse
import com.festivalscoretracker.android.core.shop.ShopSong
import com.festivalscoretracker.android.testing.Fixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** First-run demo song selection (issue #57; Apple `FirstRunDemoSongsTests` port). */
class FirstRunDemoSongsTest {
    private fun song(id: String, artist: String, art: String? = "$id.jpg") = Fixtures.song(id, "T$id", artist).copy(albumArt = art)

    private val catalog = listOf(
        song("a", "Someone"),
        song("b", "Epic Games"),
        song("c", "Someone", art = null),
        song("d", "Epic Games ft. X"),
        song("e", "Epic Games", art = ""),
        song("f", "Other"),
    )

    @Test
    fun picksEpicGamesSongsWithArtFirstThenOthersInCatalogueOrder() {
        assertEquals(listOf("b", "d", "a", "f"), FirstRunDemoSongs.pick(catalog, 10).map { it.songId })
        assertEquals(listOf("b", "d"), FirstRunDemoSongs.pick(catalog, 2).map { it.songId })
        assertTrue(FirstRunDemoSongs.pick(catalog, 0).isEmpty())
        assertTrue(FirstRunDemoSongs.pick(catalog, -1).isEmpty())
    }

    @Test
    fun preferredIdsComeFirstWithoutDuplicatesOrArtlessSongs() {
        val picked = FirstRunDemoSongs.pick(catalog, 4, preferring = listOf("f", "c", "missing", "f", "b"))
        assertEquals(listOf("f", "b", "d", "a"), picked.map { it.songId })
    }

    @Test
    fun demoUsesPlaceholdersOnlyWithoutUsableCatalogue() {
        assertEquals(List(3) { null }, FirstRunDemoSongs.forDemo(null, 3))
        assertEquals(List(3) { null }, FirstRunDemoSongs.forDemo(emptyList(), 3))
        assertEquals(List(2) { null }, FirstRunDemoSongs.forDemo(listOf(song("x", "Epic Games", art = null)), 2))
        assertTrue(FirstRunDemoSongs.forDemo(null, 0).isEmpty())
        // A short catalogue shows the real songs it has rather than padding with invented rows.
        assertEquals(listOf("b"), FirstRunDemoSongs.forDemo(listOf(song("b", "Epic Games")), 3).map { it?.songId })
    }

    @Test
    fun shopPreferenceRequiresOnePublication() {
        val offers = listOf("f", "a").map { ShopSong(it, "T$it", "Artist", shopUrl = "https://www.fortnite.com/item-shop/jam-tracks/$it") }
        val shop = ShopPayload(ShopResponse(offers.size, offers), offers, publicationId = 5, observedPublicationId = 5)
        assertEquals(listOf("f", "a"), FirstRunDemoSongs.shopPreference(shop, catalogPublication = 5, current = 5))
        assertTrue(FirstRunDemoSongs.shopPreference(shop, catalogPublication = 4, current = 5).isEmpty())
        assertTrue(FirstRunDemoSongs.shopPreference(shop, catalogPublication = 5, current = 6).isEmpty())
        assertTrue(FirstRunDemoSongs.shopPreference(shop, catalogPublication = null, current = 5).isEmpty())
        assertTrue(FirstRunDemoSongs.shopPreference(null, catalogPublication = 5, current = 5).isEmpty())
    }
}
