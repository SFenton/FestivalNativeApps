package com.festivalscoretracker.android.journeys

import android.graphics.Bitmap
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import coil3.ImageLoader
import coil3.SingletonImageLoader
import coil3.asImage
import coil3.decode.DataSource
import coil3.intercept.Interceptor
import coil3.request.ErrorResult
import coil3.request.ImageResult
import coil3.request.SuccessResult
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.background.ARTWORK_BACKGROUND_TAG
import com.festivalscoretracker.android.ui.background.ArtworkBackgroundCoverKey
import com.festivalscoretracker.android.ui.background.ArtworkBackgroundStateKey
import java.io.IOException
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Real-shell recovery with synthetic covers: artwork never becomes a TalkBack stop (#623). */
@DeviceCi
@RunWith(AndroidJUnit4::class)
class ArtworkRecoveryAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()
    private val h = JourneyHarness(rule)
    private val attempts = AtomicInteger()
    private val drawn = AtomicInteger()
    private var failCover = false
    private lateinit var savedLoader: ImageLoader
    private lateinit var loader: ImageLoader
    private var animatorScale = "1"
    private var dataSaver = false

    // region Fixture setup

    @Before
    fun setUp() {
        animatorScale = shell("settings get global animator_duration_scale")
        dataSaver = shell("cmd netpolicy get restrict-background").contains("enabled")
        shell("settings put global animator_duration_scale 1")
        shell("cmd netpolicy set restrict-background false")
        savedLoader = SingletonImageLoader.get(rule.activity)
        loader = ImageLoader.Builder(rule.activity).components {
            add(object : Interceptor {
                override suspend fun intercept(chain: Interceptor.Chain): ImageResult {
                    val attempt = attempts.incrementAndGet()
                    if (failCover && attempt == 1) return ErrorResult(null, chain.request, IOException("Synthetic cover outage"))
                    val bitmap = Bitmap.createBitmap(8, 8, Bitmap.Config.ARGB_8888).apply { eraseColor(android.graphics.Color.WHITE) }
                    drawn.incrementAndGet()
                    return SuccessResult(bitmap.asImage(), chain.request, DataSource.MEMORY)
                }
            })
        }.diskCache(null).build()
        SingletonImageLoader.setUnsafe(loader)
    }

    @After
    fun restore() {
        SingletonImageLoader.setUnsafe(savedLoader)
        loader.shutdown()
        if (animatorScale == "null") shell("settings delete global animator_duration_scale")
        else shell("settings put global animator_duration_scale $animatorScale")
        shell("cmd netpolicy set restrict-background $dataSaver")
    }

    private fun transport() = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) {
            Fixtures.songsJson.replace("alpha-512.jpg", "https://art.invalid/alpha.jpg")
        }
    }

    private fun shell(command: String): String {
        val descriptor = InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command)
        return ParcelFileDescriptor.AutoCloseInputStream(descriptor).use { it.readBytes().decodeToString().trim() }
    }

    // endregion

    // region Recovery journeys

    @Test
    fun failedCatalogueRecoversAndPublicationChangesKeepArtworkDecorativeAtLargeText() {
        val ready = CompletableDeferred<Unit>()
        val reads = AtomicInteger()
        val transport = transport().apply {
            beforeRespond = { request ->
                if (request.url.substringBefore('?').endsWith("/api/songs")) {
                    if (reads.incrementAndGet() == 1) throw FestivalApiException.PublicReadFrozen("scrape", "1")
                    ready.await()
                }
            }
        }
        var scale by mutableFloatStateOf(1f)
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(section = FestivalSection.Settings), transport, fontScale = { scale })
        h.waitForTag("fst.settings.list")
        h.publishTalkBackTree()
        rule.waitUntil(10_000) { reads.get() >= 1 }
        assertEquals("no-art", state())
        val before = h.readingOrder("artwork-before-recovery", fresh = true)
        assertSilent()
        ready.complete(Unit)
        rule.waitUntil(10_000) { state() == "animated" && drawn.get() > 0 }
        assertEquals(before, h.readingOrder("artwork-after-recovery", fresh = true))
        assertSilent()
        h.assertAccessible()

        scale = 2f
        rule.waitForIdle()
        val enlarged = h.readingOrder("artwork-large-text", fresh = true)
        assertTrue(enlarged.isNotEmpty())
        assertSilent()
        val earlierDraws = drawn.get()
        transport.publish(8)
        runBlocking { h.container.api.publication(force = true) }
        rule.waitUntil(10_000) { h.container.background.publication.value == 8 && state() == "animated" && drawn.get() > earlierDraws }
        assertEquals(enlarged, h.readingOrder("artwork-new-publication", fresh = true))
        assertSilent()
        h.assertAccessible()
    }

    @Test
    fun failedStillAndSongCoversRecoverWithoutMotionOrTalkBackStops() {
        failCover = true
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(section = FestivalSection.Settings, stillBackground = true), transport(), fontScale = { 2f })
        h.waitForTag("fst.settings.list")
        h.publishTalkBackTree()
        rule.waitUntil(10_000) { attempts.get() > 0 }
        val order = h.readingOrder("artwork-still-failed", fresh = true)
        rule.waitUntil(15_000) { drawn.get() > 0 }
        assertEquals("reduced-motion", state())
        val cover = cover()
        SystemClock.sleep(5_100)
        assertEquals(cover, cover())
        assertEquals(order, h.readingOrder("artwork-still-recovered", fresh = true))
        assertSilent()

        attempts.set(0)
        drawn.set(0)
        val token = rule.runOnIdle { h.container.background.pushFocus("https://art.invalid/song.jpg") }
        rule.waitUntil(15_000) { attempts.get() >= 2 && drawn.get() > 0 }
        assertEquals("song", state())
        assertEquals("https://art.invalid/song.jpg", cover())
        assertSilent()
        rule.runOnIdle { h.container.background.popFocus(token) }
        rule.waitUntil(10_000) { state() == "reduced-motion" }
        shell("cmd netpolicy set restrict-background true")
        rule.waitUntil(10_000) { state() == "save-data" }
        val stopped = attempts.get()
        SystemClock.sleep(5_100)
        assertEquals(stopped, attempts.get())
        assertEquals("", cover())
        assertSilent()
        h.assertAccessible()
    }

    // endregion

    // region Accessibility

    private fun state() = rule.onNodeWithTag(ARTWORK_BACKGROUND_TAG).fetchSemanticsNode().config[ArtworkBackgroundStateKey]
    private fun cover() = rule.onNodeWithTag(ARTWORK_BACKGROUND_TAG).fetchSemanticsNode().config[ArtworkBackgroundCoverKey]

    /** Neither Compose nor the published TalkBack tree may expose decorative artwork as a stop. */
    private fun assertSilent() {
        val node = rule.onNodeWithTag(ARTWORK_BACKGROUND_TAG).fetchSemanticsNode()
        assertTrue(node.children.isEmpty())
        for (key in listOf(SemanticsProperties.ContentDescription, SemanticsProperties.Text, SemanticsProperties.Role, SemanticsActions.OnClick)) {
            assertTrue(node.config.getOrNull(key) == null)
        }
        fun walk(node: AccessibilityNodeInfo) {
            if (node.viewIdResourceName?.endsWith(ARTWORK_BACKGROUND_TAG) == true) {
                assertTrue(!node.isFocusable && !node.isScreenReaderFocusable && !node.isClickable)
                assertTrue(node.text.isNullOrEmpty() && node.contentDescription.isNullOrEmpty() && node.childCount == 0)
            }
            for (i in 0 until node.childCount) node.getChild(i)?.let(::walk)
        }
        InstrumentationRegistry.getInstrumentation().uiAutomation.rootInActiveWindow?.let(::walk)
    }

    // endregion
}
