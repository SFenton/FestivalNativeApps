package com.festivalscoretracker.android.journeys

import android.view.KeyEvent
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.DeviceConfigurationOverride
import androidx.compose.ui.test.FontScale
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.isFocused
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.activity.ComponentActivity
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.firstrun.FirstRunSlide
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.ui.shell.FestivalApp
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * First Run song demos on a real device window (issue #420, for #57's real catalogue songs).
 * The Songs tour's song demos (song list, Shop highlight, New in Shop, Leaving tomorrow) are
 * decorative: with catalogue songs or with redacted placeholders, TalkBack reads each slide as
 * its heading then its description, never a song title or artist, ATF finds nothing, the first
 * hardware Tab from touch mode lands on a dialog control, Tab and Shift+Tab never stop inside a
 * demo, and at 200% text the footer stays inside the dialog.
 * `@DeviceCi`: the `android-device` CI job runs it; locally,
 * `device.py test com.festivalscoretracker.android.journeys.FirstRunDemoSongsJourneyTest --avd …`.
 * The Robolectric `FirstRunDemoSongsAccessibilityUiTest` covers every song demo of every tour.
 */
@DeviceCi
@RunWith(AndroidJUnit4::class)
class FirstRunDemoSongsJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    /** Catalogue songs with artwork refs that resolve to nothing off loopback (no image traffic). */
    private val songs = listOf(
        Triple("demo-1", "Neon Overture", "Epic Games"),
        Triple("demo-2", "Crowd Surfer", "Epic Games"),
        Triple("demo-3", "Lighthouse Static", "Harbor Kids"),
        Triple("demo-4", "Velvet Circuit", "Harbor Kids"),
    )

    private val songTexts = songs.flatMap { listOf(it.second, it.third) }.distinct()

    /** `/api/songs` with [songs]; [withArt] false leaves the demos on placeholders (no song has art). */
    private fun songsJson(withArt: Boolean): String = songs.joinToString(",", prefix = """{"count":${songs.size},"currentSeason":15,"songs":[""", postfix = "]}") { (id, title, artist) ->
        val art = if (withArt) "\"/__fixture__/$id.jpg\"" else "null"
        """{"songId":"$id","title":"$title","artist":"$artist","year":2021,"durationSeconds":185,"albumArt":$art,"difficulty":{"guitar":3,"bass":2,"drums":1,"vocals":2}}"""
    }

    private fun transport(withArt: Boolean) = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { songsJson(withArt) }
    }

    private val fontScale = mutableFloatStateOf(1f)

    private lateinit var container: AppContainer

    private fun launch(withArt: Boolean) {
        val debug = DebugLaunch(firstRun = "on", stillBackground = true)
        container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport(withArt), settingsStore = MemoryPreferences())
        rule.setContent {
            DeviceConfigurationOverride(DeviceConfigurationOverride.FontScale(fontScale.floatValue)) { FestivalApp(container, debug) }
        }
        h.waitForTag("fst.first-run.dialog")
    }

    private fun position(): String =
        rule.onNodeWithTag("fst.first-run.position", useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.StateDescription]

    private fun SemanticsNode.label(): String = listOfNotNull(
        config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString(),
        config.getOrNull(SemanticsProperties.Text)?.joinToString { it.text },
    ).joinToString(", ")

    /** Song titles and artists the demo on [slide] draws (unmerged tree: pixels, not TalkBack). */
    private fun drawnSongs(slide: FirstRunSlide): List<String> =
        rule.onAllNodes(hasAnyAncestor(hasTestTag("fst.first-run.demo") and hasAnyAncestor(hasTestTag("fst.first-run.slide.${slide.id}"))), useUnmergedTree = true)
            .fetchSemanticsNodes().map { it.label() }.flatMap { label -> songTexts.filter { it in label } }.distinct()

    /**
     * Walks the Songs tour slide by slide, checking each one's TalkBack reading and, when
     * [keyboard], that hardware Tab steps over the demo to the footer.
     *
     * @return Slide id → song texts its demo draws.
     */
    private fun walk(state: String, keyboard: Boolean): Map<String, List<String>> {
        val slides = container.firstRun.active.value!!.slides
        val drawn = linkedMapOf<String, List<String>>()
        slides.forEachIndexed { index, slide ->
            rule.waitUntil(5_000) { position().startsWith("Slide ${index + 1} of ") }
            h.awaitAccessibilityTree("fst.first-run.slide.${slide.id}", slides.getOrNull(index - 1)?.let { "fst.first-run.slide.${it.id}" })
            val labels = h.readingOrder("first-run-demo-songs-$state-${slide.id}")
            val leaked = labels.filter { label -> songTexts.any { it in label } }
            assertTrue("${slide.id} ($state): TalkBack reads no demo song: $leaked", leaked.isEmpty())
            assertTrue("${slide.id} ($state): no unlabelled stop: $labels", "<unlabelled>" !in labels)
            val title = labels.indexOfFirst { slide.title in it }
            assertTrue("${slide.id} ($state): the slide title is read: $labels", title >= 0)
            assertEquals("${slide.id} ($state): the description follows the title: $labels", slide.description, labels.getOrNull(title + 1))
            val inDialog = rule.onAllNodes(hasAnyAncestor(hasTestTag("fst.first-run.dialog"))).fetchSemanticsNodes().map { it.label() }
            assertTrue("${slide.id} ($state): no song text in the dialog's merged tree", inDialog.none { label -> songTexts.any { it in label } })
            drawn[slide.id] = drawnSongs(slide)
            if (keyboard) assertTabSkipsTheDemo(slide, last = index == slides.lastIndex)
            val dialog = rule.onNodeWithTag("fst.first-run.dialog").fetchSemanticsNode().boundsInRoot
            val action = if (index == slides.lastIndex) "fst.first-run.done" else "fst.first-run.next"
            val button = rule.onNodeWithTag(action).fetchSemanticsNode()
            assertTrue("${slide.id} ($state): $action stays inside the dialog", button.boundsInRoot.bottom <= dialog.bottom && button.boundsInRoot.top >= dialog.top)
            val min = with(rule.density) { 48.dp.toPx() } - 1f
            assertTrue("${slide.id} ($state): $action keeps a 48 dp target", button.touchBoundsInRoot.height >= min && button.touchBoundsInRoot.width >= min)
            if (index < slides.lastIndex) h.tap("fst.first-run.next")
        }
        return drawn
    }

    /**
     * From the state the slide left (a touch-mode window after tapping Next: nothing focused),
     * presses hardware Tab until Next/Done has focus, then Shift+Tab until Close has focus,
     * failing if focus ever lands inside a demo or nowhere in the dialog.
     */
    private fun assertTabSkipsTheDemo(slide: FirstRunSlide, last: Boolean) {
        val target = if (last) "fst.first-run.done" else "fst.first-run.next"
        tabUntil(slide, KeyEvent.KEYCODE_TAB, 0, target)
        tabUntil(slide, KeyEvent.KEYCODE_TAB, KeyEvent.META_SHIFT_ON or KeyEvent.META_SHIFT_LEFT_ON, "fst.first-run.close")
    }

    /** Presses [code] with [meta] until [target] has focus; never a demo node, never nowhere after the first press. */
    private fun tabUntil(slide: FirstRunSlide, code: Int, meta: Int, target: String) {
        val key = if (meta != 0) "Shift+Tab" else "Tab"
        val stops = mutableListOf<String?>()
        for (step in 0 until 8) {
            val time = android.os.SystemClock.uptimeMillis()
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            instrumentation.sendKeySync(KeyEvent(time, time, KeyEvent.ACTION_DOWN, code, 0, meta))
            instrumentation.sendKeySync(KeyEvent(time, time, KeyEvent.ACTION_UP, code, 0, meta))
            rule.waitForIdle()
            val inDemo = rule.onAllNodes(isFocused() and hasAnyAncestor(hasTestTag("fst.first-run.demo")), useUnmergedTree = true).fetchSemanticsNodes()
            assertTrue("${slide.id}: $key ${step + 1} after $stops focused a hidden demo node", inDemo.isEmpty())
            val focused = rule.onAllNodes(isFocused() and hasAnyAncestor(hasTestTag("fst.first-run.dialog")), useUnmergedTree = true).fetchSemanticsNodes()
            stops += focused.firstOrNull()?.config?.getOrNull(SemanticsProperties.TestTag)
            if (stops.last() == target) break
        }
        assertEquals("${slide.id}: $key reaches $target (stops $stops)", target, stops.last())
        assertTrue("${slide.id}: $key never leaves focus nowhere after entering the dialog (stops $stops)", stops.drop(1).none { it == null })
    }

    /** Catalogue songs fill the demos (#57) but stay hidden from TalkBack and keyboard focus. */
    @Test
    fun catalogueSongDemosAreSilentAndSkippedByTab() {
        h.enableAccessibilityChecks()
        launch(withArt = true)
        val drawn = walk("songs", keyboard = true)
        assertTrue("the song list demo draws catalogue songs: $drawn", drawn["songs-song-list"].orEmpty().isNotEmpty())
        h.assertAccessible()
    }

    /** Placeholders (no catalogue song with art) read exactly like the loaded slide: heading, then description. */
    @Test
    fun placeholderDemosReadLikeLoadedDemos() {
        h.enableAccessibilityChecks()
        launch(withArt = false)
        assertTrue("placeholders show while no song has art", h.exists("fst.first-run.demo.placeholder"))
        val drawn = walk("placeholders", keyboard = false)
        assertTrue("placeholders draw no song: $drawn", drawn.values.all { it.isEmpty() })
        h.assertAccessible()
    }

    /** At 200% text the slide text grows beside the unscaled demo and the footer stays a 48 dp target in the dialog. */
    @Test
    fun largeTextKeepsSongDemoSlidesReadable() {
        h.enableAccessibilityChecks()
        fontScale.floatValue = 2f
        launch(withArt = true)
        walk("200pct", keyboard = false)
        h.assertAccessible()
    }
}
