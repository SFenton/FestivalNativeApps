package com.festivalscoretracker.android.journeys

import android.os.ParcelFileDescriptor
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.dp
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import kotlinx.coroutines.CompletableDeferred
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.math.roundToInt

/**
 * A card that groups several rows fades in as one card on a device (`load-transition` R11,
 * owner-approved #614 variant), through the Full Rankings board card and the Leaderboards
 * overview's Lead card. With system animations on, the board's read is held, then released with
 * the frame clock paused: 120 ms into the entrance every row of the card still drifts by the same
 * amount (one fade, no row stagger); under the app's Reduce Motion the rows sit in place at once.
 * Once settled, each row is a 48 dp TalkBack Button inside its card and the rows read in rank
 * order, at the device's text size and at 200%. ATF runs on every step. `@DeviceCi`
 * (`device.py test com.festivalscoretracker.android.journeys.CardEntranceAccessibilityJourneyTest --avd …`).
 */
@DeviceCi
@RunWith(AndroidJUnit4::class)
class CardEntranceAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private var savedAnimatorScale = "null"

    // region System settings

    private fun shell(command: String): String {
        val pfd = InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command)
        return ParcelFileDescriptor.AutoCloseInputStream(pfd).use { it.readBytes().decodeToString().trim() }
    }

    @Before
    fun animationsOn() {
        savedAnimatorScale = shell("settings get global animator_duration_scale").ifEmpty { "null" }
        shell("settings put global animator_duration_scale 1")
    }

    @After
    fun restoreAnimatorScale() {
        shell(if (savedAnimatorScale == "null") "settings delete global animator_duration_scale" else "settings put global animator_duration_scale $savedAnimatorScale")
    }

    // endregion

    // region Helpers

    private fun path(url: String) = "/" + url.substringAfter("://").substringAfter('/').substringBefore('?')

    private fun exists(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    /** Distinct visible rows whose tag starts with [prefix] inside [card], top first. */
    private fun rows(prefix: String, card: String): List<String> {
        val row = SemanticsMatcher("row $prefix") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith(prefix) == true }
        return rule.onAllNodes(row and hasAnyAncestor(hasTestTag(card)), useUnmergedTree = true).fetchSemanticsNodes()
            .filter { it.boundsInRoot.height > 0f }
            .sortedBy { it.boundsInRoot.top }
            .distinctBy { it.boundsInRoot.top.roundToInt() }
            .map { it.config[SemanticsProperties.TestTag] }
    }

    private fun top(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().first().boundsInRoot.top

    /**
     * Launches [route] with [path]'s read held, releases it with the frame clock paused, steps
     * frames until [loading] has gone and [count] rows of [card] are composed (fewer fit at large text), then returns how far
     * (px) each still sits below its settled place [PROBE_MS] into the entrance.
     */
    private fun entranceDrifts(route: String, path: String, loading: String, prefix: String, card: String, reduceMotion: Boolean = false, fontScale: Float = 1f, count: Int = ROWS): List<Float> {
        val gate = CompletableDeferred<Unit>()
        val transport = RankingsFixtures.install(
            FakeTransport.standard().apply {
                on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
            },
        )
        transport.beforeRespond = { request -> if (path(request.url) == path) gate.await() }
        h.enableAccessibilityChecks()
        h.launch(
            DebugLaunch(route = DebugLaunch.parseRoute(route), stillBackground = true),
            transport,
            MemoryPreferences(mutablePreferencesOf(booleanPreferencesKey(SettingsRegistry.REDUCE_MOTION) to reduceMotion)),
            fontScale = { fontScale },
        )
        h.waitForTag(loading)
        rule.mainClock.autoAdvance = false
        try {
            gate.complete(Unit)
            var frames = 0
            while (exists(loading) || rows(prefix, card).size < count) {
                check(frames++ < 3_000) { "$card never revealed" }
                Thread.sleep(2)
                rule.mainClock.advanceTimeByFrame()
            }
            val tags = rows(prefix, card).take(count)
            rule.mainClock.advanceTimeBy(PROBE_MS)
            val mid = tags.map(::top)
            rule.mainClock.advanceTimeBy(2_000)
            return tags.mapIndexed { i, tag -> mid[i] - top(tag) }
        } finally {
            rule.mainClock.autoAdvance = true
            rule.waitForIdle()
        }
    }

    private fun assertOneFade(screen: String, drifts: List<Float>) {
        assertTrue("$screen: the card is still drifting up: $drifts", drifts.first() > 0.5f)
        val frame = with(rule.density) { 1.2.dp.toPx() }
        drifts.forEach { assertEquals("$screen: every row drifts with its card: $drifts", drifts.first(), it, frame) }
    }

    /**
     * Settled: each of the card's first rows is one 48 dp TalkBack Button inside [card], and the
     * rows read in rank order.
     */
    private fun assertSettledCard(screen: String, prefix: String, card: String) {
        h.awaitAccessibilityTree(card)
        val cardBox = rule.onAllNodes(hasTestTag(card), useUnmergedTree = true).fetchSemanticsNodes().first().boundsInRoot
        val minPx = with(rule.density) { 48.dp.toPx() } - 1
        val tags = rows(prefix, card).take(2)
        assertEquals("$screen: rows in $card", 2, tags.size)
        tags.forEach { tag ->
            val node = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().first()
            assertEquals("$screen: $tag role", Role.Button, node.config.getOrNull(SemanticsProperties.Role))
            val box = node.boundsInRoot
            assertTrue("$screen: $tag $box under 48 dp", box.height >= minPx)
            assertTrue("$screen: $tag $box outside its card $cardBox", box.top >= cardBox.top - 1 && box.bottom <= cardBox.bottom + 1)
        }
        val order = h.readingOrder(screen, fresh = true)
        val first = order.indexOfFirst { it.contains("Synthetic Player 1.") }
        val second = order.indexOfFirst { it.contains("Synthetic Player 2.") }
        assertTrue("$screen: rank order in $order", first >= 0 && second > first)
        h.assertNothingStraddles(*tags.toTypedArray())
        h.assertAccessible()
    }

    // endregion

    // region Journeys

    @Test
    fun fullRankingsCardFadesInAsOne() = fullRankings("card-entrance-full-rankings")

    @Test
    fun fullRankingsCardFadesInAsOneAtLargeText() = fullRankings("card-entrance-full-rankings-font-2", fontScale = 2f, count = 2)

    @Test
    fun reduceMotionShowsTheFullRankingsCardInPlace() {
        val drifts = entranceDrifts(
            "fullRankings:Solo_Guitar", "/api/rankings/Solo_Guitar", "fst.full-rankings.loading", ROW, BOARD_CARD,
            reduceMotion = true,
        )
        drifts.forEach { assertEquals("no fade under Reduce Motion: $drifts", 0f, it, 0.5f) }
        assertSettledCard("card-entrance-full-rankings-reduced", ROW, BOARD_CARD)
    }

    @Test
    fun leaderboardsOverviewCardFadesInAsOne() {
        val card = "fst.leaderboards.card.Solo_Guitar"
        assertOneFade("card-entrance-overview", entranceDrifts("leaderboards", "/api/rankings/Solo_Guitar", "fst.leaderboards.loading", ROW, card))
        assertSettledCard("card-entrance-overview", ROW, card)
    }

    private fun fullRankings(screen: String, fontScale: Float = 1f, count: Int = ROWS) {
        assertOneFade(screen, entranceDrifts("fullRankings:Solo_Guitar", "/api/rankings/Solo_Guitar", "fst.full-rankings.loading", ROW, BOARD_CARD, fontScale = fontScale, count = count))
        assertSettledCard(screen, ROW, BOARD_CARD)
    }

    // endregion

    private companion object {
        const val ROW = "fst.rankings.row."
        const val BOARD_CARD = "fst.full-rankings.rows"

        /** Rows compared: the fifth would start 500 ms after the first under a row stagger. */
        const val ROWS = 5

        /** Well into the card's 400 ms entrance, before the second row's old 125 ms slot ends. */
        const val PROBE_MS = 120L
    }
}
