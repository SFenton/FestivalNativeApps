package com.festivalscoretracker.android.ui.background

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.ConnectivityManager
import android.os.Looper
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import coil3.ImageLoader
import coil3.asImage
import coil3.decode.DataSource
import coil3.intercept.Interceptor
import coil3.request.ErrorResult
import coil3.request.ImageResult
import coil3.request.SuccessResult
import com.festivalscoretracker.android.core.model.SongsResponse
import com.festivalscoretracker.android.data.CatalogPayload
import com.festivalscoretracker.android.presentation.BackgroundController
import com.festivalscoretracker.android.presentation.BackgroundPolicy
import com.festivalscoretracker.android.presentation.ModalCoverage
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import java.io.IOException
import java.time.Duration
import java.util.Collections
import kotlin.math.abs
import kotlin.random.Random
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Every reachable state of the shared backdrop (`fst.shell.artwork-background`, issue #124):
 * no-art, animated, reduced-motion (in-app, Disable Animated Artwork and the live system
 * animator scale), save-data (live Data Saver), not-visible, covered and the song cover, plus
 * paced failure recovery and the art-only dim. Covers are synthetic solid white bitmaps
 * served by a fake Coil interceptor; no network.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ArtworkBackgroundUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val context: Context = ApplicationProvider.getApplicationContext()
    private val requested = Collections.synchronizedList(mutableListOf<String>())

    @Volatile
    private var failing: Set<String> = emptySet()

    private val songs = (0 until 6).map { Fixtures.song("s$it", "T$it").copy(albumArt = "a$it.jpg") }
    private val artworkUrl: (String?) -> String? = { raw -> raw?.let { "https://art.invalid/$it" } }

    /** The carousel order a controller seeded with `Random(SEED)` will pick. */
    private val order = BackgroundPolicy.pickCovers(songs, artworkUrl, Random(SEED))

    private val loader: ImageLoader by lazy {
        val interceptor = object : Interceptor {
            override suspend fun intercept(chain: Interceptor.Chain): ImageResult {
                val url = chain.request.data.toString()
                requested += url
                if (url in failing) return ErrorResult(null, chain.request, IOException("404 $url"))
                val bitmap = Bitmap.createBitmap(8, 8, Bitmap.Config.ARGB_8888).apply { eraseColor(android.graphics.Color.WHITE) }
                return SuccessResult(bitmap.asImage(), chain.request, DataSource.MEMORY)
            }
        }
        ImageLoader.Builder(context).components { add(interceptor) }.build()
    }

    private class Owner : LifecycleOwner {
        val registry = LifecycleRegistry.createUnsafe(this).apply { currentState = Lifecycle.State.RESUMED }
        override val lifecycle: Lifecycle get() = registry
    }

    @After
    fun restoreSystemSettings() {
        Settings.Global.putFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f)
        shadowOf(context.getSystemService(ConnectivityManager::class.java))
            .setRestrictBackgroundStatus(ConnectivityManager.RESTRICT_BACKGROUND_STATUS_DISABLED)
    }

    private fun controller(fail: Boolean = false) = BackgroundController(
        loadCatalog = {
            if (fail) throw IOException("offline")
            CatalogPayload(SongsResponse(songs.size, null, songs), 1)
        },
        artworkUrl = artworkUrl,
        random = Random(SEED),
    )

    private fun setUp(
        controller: BackgroundController,
        owner: Owner = Owner(),
        coverage: ModalCoverage = ModalCoverage(),
        appReduceMotion: Boolean = false,
        forceStill: Boolean = false,
    ) {
        rule.mainClock.autoAdvance = false
        rule.setContent {
            CompositionLocalProvider(LocalLifecycleOwner provides owner) {
                FestivalTheme(appReduceMotion = appReduceMotion) {
                    LaunchedEffect(Unit) { controller.start(this) }
                    ArtworkBackground(controller, forceStill = forceStill, modifier = Modifier.size(200.dp), coverage = coverage, imageLoader = loader)
                }
            }
        }
        advance(100)
    }

    /** Advances the composition clock and the Robolectric main looper together. */
    private fun advance(ms: Long) {
        // The clock rounds each step up to whole 16 ms frames, so advance to a target time.
        val end = rule.mainClock.currentTime + ms
        while (rule.mainClock.currentTime < end) {
            val before = rule.mainClock.currentTime
            rule.mainClock.advanceTimeBy(minOf(32L, end - before))
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(rule.mainClock.currentTime - before))
        }
        rule.waitForIdle()
    }

    private fun node() = rule.onNodeWithTag(ARTWORK_BACKGROUND_TAG, useUnmergedTree = true).fetchSemanticsNode()

    private fun state() = node().config[ArtworkBackgroundStateKey]

    private fun cover() = node().config[ArtworkBackgroundCoverKey]

    /** Draws the window on the native canvas and reads the backdrop's centre pixel. */
    private fun centre(): Color {
        val bounds = node().boundsInWindow
        val root = rule.activity.window.decorView
        val bitmap = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
        rule.runOnUiThread { root.draw(Canvas(bitmap)) }
        return Color(bitmap.getPixel(bounds.center.x.toInt(), bounds.center.y.toInt()))
    }

    /** Decorative: no text, description, role or action for TalkBack, even over loaded covers. */
    private fun assertHiddenFromAccessibility() {
        val merged = rule.onNodeWithTag(ARTWORK_BACKGROUND_TAG).fetchSemanticsNode()
        assertTrue("children: ${merged.children.map { it.config }}", merged.children.isEmpty())
        for (key in listOf(SemanticsProperties.ContentDescription, SemanticsProperties.Text, SemanticsProperties.Role, SemanticsActions.OnClick)) {
            assertNull(merged.config.getOrNull(key))
        }
    }

    private fun assertColor(expected: Color, actual: Color) {
        val close = listOf(expected.red to actual.red, expected.green to actual.green, expected.blue to actual.blue).all { (e, a) -> abs(e - a) < 0.03f }
        assertTrue("expected $expected, got $actual", close)
    }

    private fun setAnimatorScale(scale: Float) {
        Settings.Global.putFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, scale)
        context.contentResolver.notifyChange(Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE), null)
        advance(100)
    }

    private fun setDataSaver(on: Boolean) {
        shadowOf(context.getSystemService(ConnectivityManager::class.java)).setRestrictBackgroundStatus(
            if (on) ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED else ConnectivityManager.RESTRICT_BACKGROUND_STATUS_DISABLED,
        )
        context.sendBroadcast(Intent(ConnectivityManager.ACTION_RESTRICT_BACKGROUND_CHANGED).setPackage(context.packageName))
        advance(100)
    }

    private val dimmedWhite = Color(BackgroundPolicy.ART_LIGHTNESS, BackgroundPolicy.ART_LIGHTNESS, BackgroundPolicy.ART_LIGHTNESS)

    // region States

    @Test
    fun noArtShowsTheUndimmedBrandSurfaceAndStaysHiddenFromAccessibility() {
        setUp(controller(fail = true))
        assertEquals("no-art", state())
        assertEquals("", cover())
        assertColor(BrandTokens.appBackground, centre())
        // Decorative: no text, description or actions for TalkBack, and nothing to tap.
        assertHiddenFromAccessibility()
    }

    @Test
    fun animatedRotatesEveryFiveSecondsAndDimsOnlyTheArt() {
        setUp(controller())
        assertEquals("animated", state())
        assertEquals(order[0], cover())
        advance(BackgroundPolicy.DWELL_MS - 500)
        assertEquals(order[0], cover())
        advance(1_000)
        assertEquals(order[1], cover())
        advance(BackgroundPolicy.DWELL_MS)
        assertEquals(order[2], cover())
        // White art multiplied by 0.3 equals black at 0.7 over opaque art.
        assertColor(dimmedWhite, centre())
        assertHiddenFromAccessibility()
        // The next cover is preloaded, and only one ahead.
        assertTrue(order[3] in requested)
        assertFalse(order[5] in requested)
    }

    @Test
    fun inAppReduceMotionHoldsOneStillDimmedCover() {
        setUp(controller(), appReduceMotion = true)
        assertEquals("reduced-motion", state())
        assertEquals(order[0], cover())
        advance(BackgroundPolicy.DWELL_MS * 2 + 500)
        assertEquals(order[0], cover())
        assertColor(dimmedWhite, centre())
    }

    @Test
    fun disableAnimatedArtworkHoldsOneStillCover() {
        setUp(controller(), forceStill = true)
        assertEquals("reduced-motion", state())
        advance(BackgroundPolicy.DWELL_MS + 500)
        assertEquals(order[0], cover())
    }

    @Test
    fun systemAnimatorScaleZeroStopsTheCarouselWithoutARestart() {
        setUp(controller())
        assertEquals("animated", state())
        setAnimatorScale(0f)
        assertEquals("reduced-motion", state())
        advance(BackgroundPolicy.DWELL_MS * 2)
        assertEquals(order[0], cover())
        setAnimatorScale(1f)
        assertEquals("animated", state())
        advance(BackgroundPolicy.DWELL_MS + 100)
        assertEquals(order[1], cover())
    }

    @Test
    fun dataSaverRemovesArtAndDimLiveAndRestoresThem() {
        setUp(controller())
        advance(1_500)
        assertEquals("animated", state())
        setDataSaver(true)
        assertEquals("save-data", state())
        assertEquals("", cover())
        assertColor(BrandTokens.appBackground, centre())
        setDataSaver(false)
        advance(1_500)
        assertEquals("animated", state())
        assertColor(dimmedWhite, centre())
    }

    @Test
    fun dataSaverAtLaunchNeverRequestsArt() {
        shadowOf(context.getSystemService(ConnectivityManager::class.java))
            .setRestrictBackgroundStatus(ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED)
        setUp(controller())
        advance(BackgroundPolicy.DWELL_MS + 100)
        assertEquals("save-data", state())
        assertTrue(requested.isEmpty())
    }

    @Test
    fun notVisiblePausesAndResumingContinues() {
        val owner = Owner()
        setUp(controller(), owner = owner)
        owner.registry.currentState = Lifecycle.State.STARTED
        advance(100)
        assertEquals("not-visible", state())
        advance(BackgroundPolicy.DWELL_MS * 2)
        assertEquals(order[0], cover())
        owner.registry.currentState = Lifecycle.State.RESUMED
        advance(100)
        assertEquals("animated", state())
        advance(BackgroundPolicy.DWELL_MS + 100)
        assertEquals(order[1], cover())
    }

    @Test
    fun aModalHoldsTheFrameAndTheSongCoverWins() {
        val coverage = ModalCoverage()
        val controller = controller()
        setUp(controller, coverage = coverage)
        coverage.open()
        advance(100)
        assertEquals("covered", state())
        advance(BackgroundPolicy.DWELL_MS + 100)
        assertEquals(order[0], cover())
        coverage.close()
        val token = rule.runOnIdle { controller.pushFocus("song.jpg") }
        advance(100)
        assertEquals("song", state())
        assertEquals("https://art.invalid/song.jpg", cover())
        advance(BackgroundPolicy.DWELL_MS + 100)
        assertEquals("https://art.invalid/song.jpg", cover())
        rule.runOnIdle { controller.popFocus(token) }
        advance(100)
        assertEquals("animated", state())
    }

    // endregion

    // region Failures

    @Test
    fun threeFailedCoversWaitForTheDeadlineThenTheFourthShows() {
        failing = order.take(3).toSet()
        setUp(controller())
        advance(500)
        // Two immediate skips, then the third failure waits for the deadline.
        assertEquals(order[2], cover())
        assertTrue(order.take(3).all { it in requested })
        advance(BackgroundPolicy.DWELL_MS)
        assertEquals(order[3], cover())
        assertEquals("animated", state())
        advance(1_500)
        assertColor(dimmedWhite, centre())
    }

    @Test
    fun fiveFailuresSpendThePoolAndStopRotationOnTheBrandSurface() {
        failing = order.toSet()
        setUp(controller())
        advance(500)
        assertEquals(order[2], cover())
        advance(BackgroundPolicy.DWELL_MS)
        assertEquals(order[4], cover())
        val requestsWhenSpent = requested.size
        advance(BackgroundPolicy.DWELL_MS * 3)
        assertEquals(order[4], cover())
        // Rotation (and preloading) stopped: no new requests after the budget is spent.
        assertEquals(requestsWhenSpent, requested.size)
        // A failure is never replaced by success-shaped imagery: the brand surface shows.
        assertColor(BrandTokens.appBackground, centre())
        assertNotEquals("no-art", state())
    }

    // endregion

    private companion object {
        const val SEED = 4
    }
}
