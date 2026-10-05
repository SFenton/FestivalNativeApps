package com.festivalscoretracker.android.firstrun

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SongsResponse
import com.festivalscoretracker.android.core.shop.ShopPayload
import com.festivalscoretracker.android.core.shop.ShopResponse
import com.festivalscoretracker.android.core.shop.ShopSong
import com.festivalscoretracker.android.data.CatalogPayload
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.firstrun.FirstRunDemoCatalog
import com.festivalscoretracker.android.ui.firstrun.FirstRunDemoSongsSource
import com.festivalscoretracker.android.ui.firstrun.rememberFirstRunDemoCatalog
import java.io.IOException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The first-run host's catalogue wiring for song demos (issues #57, #165): placeholders while
 * `/api/songs` loads or after it fails, real songs once it arrives, and Shop songs first only
 * for a publication-matched Shop feed that Settings doesn't hide.
 */
@RunWith(AndroidJUnit4::class)
class FirstRunDemoCatalogHostTest {
    @get:Rule
    val rule = createComposeRule()

    private val songs = listOf("a", "b").map { Fixtures.song(it, "T$it", "Epic Games").copy(albumArt = "$it.jpg") }
    private val payload = CatalogPayload(SongsResponse(songs.size, null, songs), 5)
    private val offers = listOf(ShopSong("b", "Tb", "Epic Games", shopUrl = "https://www.fortnite.com/item-shop/jam-tracks/b"))
    private val shopLoaded = LoadState.Loaded(ShopPayload(ShopResponse(offers.size, offers), offers, publicationId = 5, observedPublicationId = 5))

    private fun source(
        load: suspend () -> CatalogPayload,
        shop: LoadState<ShopPayload> = LoadState.Loading,
        publication: Int? = 5,
    ) = FirstRunDemoSongsSource(load, MutableStateFlow(shop), MutableStateFlow(publication), { "art:$it" })

    private fun render(source: FirstRunDemoSongsSource, hideShop: Boolean = false): () -> FirstRunDemoCatalog {
        var latest = FirstRunDemoCatalog()
        rule.setContent { latest = rememberFirstRunDemoCatalog(source, hideShop) }
        rule.waitForIdle()
        return { latest }
    }

    @Test
    fun loadingShowsPlaceholdersThenCatalogueSongs() {
        val pending = CompletableDeferred<CatalogPayload>()
        val catalog = render(source({ pending.await() }))
        assertNull("placeholders while loading", catalog().songs)

        pending.complete(payload)
        rule.waitForIdle()
        assertEquals(listOf("a", "b"), catalog().songs?.map { it.songId })
        assertEquals("art:a.jpg", catalog().artworkUrl("a.jpg"))
    }

    @Test
    fun failedLoadKeepsPlaceholders() {
        val catalog = render(source({ throw IOException("offline") }))
        assertNull("a failed read leaves placeholders", catalog().songs)
        assertTrue(catalog().shopSongIds.isEmpty())
    }

    @Test
    fun shopSongsComeFirstOnlyForAMatchingVisibleShop() {
        assertEquals(listOf("b"), render(source({ payload }, shopLoaded)).invoke().shopSongIds)
    }

    @Test
    fun hiddenShopUsesNoShopSongs() {
        assertTrue(render(source({ payload }, shopLoaded), hideShop = true).invoke().shopSongIds.isEmpty())
    }

    @Test
    fun newerPublicationIgnoresTheShopFeed() {
        val catalog = render(source({ payload }, shopLoaded, publication = 6)).invoke()
        assertEquals(2, catalog.songs?.size)
        assertTrue("a Shop from another publication never reorders demos", catalog.shopSongIds.isEmpty())
    }
}
