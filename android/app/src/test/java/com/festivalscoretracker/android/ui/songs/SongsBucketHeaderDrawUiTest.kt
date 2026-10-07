package com.festivalscoretracker.android.ui.songs

import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToIndex
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.data.HttpTransport
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.BucketHeaderFixtures
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.SongsFixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import kotlin.math.abs
import okhttp3.OkHttpClient
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Songs bucket headers have no backing in every Quick Links sort (issues #91, #189): Duration,
 * Year, Item Shop and the single-chart Score, Percentile and Stars sorts. The empty end of each
 * header must show exactly what the list's side padding shows (the artwork background), both at
 * rest and while pinned over scrolled rows, so neither an opaque band nor a row hidden under the
 * pinned title can appear behind it. Native graphics, so the pinned-header cut and recorded
 * header layers really draw.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SongsBucketHeaderDrawUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")

    private val profileJson = """
        {"accountId":"${Fixtures.ACCOUNT_A}","displayName":"Synthetic Player","totalScores":1,"scores":[
          {"si":"s-alpha","ins":"01","sc":95198,"acc":987,"fc":true,"st":6,"sn":15,"dif":3,"rk":42,"te":1000,"lp":"2026-09-01T12:00:00Z"}
        ]}
    """.trimIndent()

    /** The three-song catalogue with the Shop feed and one Lead score (each sort yields at least two buckets). */
    private fun smallTransport() = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        on("/api/shop", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.shopJson.replace("\"b.jpg\"", "null") }
        on("/api/player/${Fixtures.ACCOUNT_A}", headers = mapOf("X-FST-Publication-Id" to "7")) { profileJson }
    }

    /** Ten songs per decade and per minute bucket ([BucketHeaderFixtures]), so a section outgrows the screen. */
    private fun largeTransport() = BucketHeaderFixtures.transport()

    private fun prefs(vararg pairs: Preferences.Pair<*>) = InMemoryPreferences(mutablePreferencesOf(*pairs))

    private fun launch(transport: HttpTransport, prefs: InMemoryPreferences, profile: SelectedPlayer? = null) {
        val debug = DebugLaunch(profile = profile, stillBackground = true)
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

    private val isBucketHeader = SemanticsMatcher("Songs bucket header") {
        val tag = it.config.getOrNull(SemanticsProperties.TestTag).orEmpty()
        tag.startsWith("fst.songs.section.") || tag.startsWith("fst.songs.shop-section.")
    }

    /** Bounds of the bucket headers fully inside the list, clear of the bottom toolbar, waiting until at least [min] exist. */
    private fun headers(min: Int = 2): List<Rect> {
        val density = rule.activity.resources.displayMetrics.density
        fun visible(): List<Rect> {
            val list = rule.onNodeWithTag("fst.songs.list").fetchSemanticsNode().boundsInRoot
            return rule.onAllNodes(isBucketHeader, useUnmergedTree = true).fetchSemanticsNodes().map { it.boundsInRoot }
                .filter { it.top >= list.top - 1 && it.bottom <= list.bottom - TOOLBAR_CLEARANCE_DP * density }
        }
        rule.waitUntil(20_000) { settle(100); visible().size >= min }
        return visible()
    }

    private fun window(): Bitmap {
        val root = rule.activity.window.decorView
        val bitmap = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
        rule.runOnUiThread { root.draw(Canvas(bitmap)) }
        return bitmap
    }

    /**
     * The empty trailing end of the header at [bounds] matches the list's start padding at the
     * same height: no band and no row behind the title.
     */
    private fun assertBare(bitmap: Bitmap, bounds: Rect, what: String) {
        val density = rule.activity.resources.displayMetrics.density
        val y = bounds.center.y.toInt()
        val inside = bitmap.getPixel(bounds.right.toInt() - 2, y)
        val outside = bitmap.getPixel((8 * density).toInt(), y)
        val diff = listOf(16, 8, 0).maxOf { shift -> abs((inside shr shift and 0xFF) - (outside shr shift and 0xFF)) }
        assertTrue(
            "$what: header end #${Integer.toHexString(inside)} differs from the background #${Integer.toHexString(outside)}",
            diff <= 6,
        )
    }

    private fun assertHeadersBare(what: String, min: Int = 2) {
        val bounds = headers(min)
        val bitmap = window()
        bounds.forEach { assertBare(bitmap, it, what) }
    }

    @Test
    fun durationHeadersHaveNoBackingAtRestAndPinned() {
        launch(largeTransport(), prefs(stringPreferencesKey(SettingsRegistry.SONG_SORT) to "Duration"))
        assertHeadersBare("Duration at rest", min = 1)
        // Row 5 of the first section at the top: rows 1–5 are scrolled under the pinned header.
        rule.onNodeWithTag("fst.songs.list").performScrollToIndex(5)
        settle()
        assertHeadersBare("Duration pinned", min = 1)
    }

    @Test
    fun yearHeadersHaveNoBackingAtRestAndPinned() {
        launch(largeTransport(), prefs(stringPreferencesKey(SettingsRegistry.SONG_SORT) to "Year"))
        assertHeadersBare("Year at rest", min = 1)
        // The last rows of the 1970s under the pinned header, with the 1980s header coming up below.
        rule.onNodeWithTag("fst.songs.list").performScrollToIndex(9)
        settle()
        assertHeadersBare("Year pinned", min = 1)
    }

    @Test
    fun shopHeadersHaveNoBacking() {
        launch(smallTransport(), prefs(stringPreferencesKey(SettingsRegistry.SONG_SORT) to "Shop"))
        rule.waitUntil(20_000) { settle(100); rule.onAllNodesWithTag("fst.songs.shop-section.leaving-tomorrow").fetchSemanticsNodes().isNotEmpty() }
        assertHeadersBare("Item Shop")
    }

    @Test
    fun scoreHeadersHaveNoBacking() = assertSingleChartHeadersBare("Score")

    @Test
    fun percentileHeadersHaveNoBacking() = assertSingleChartHeadersBare("Percentile")

    @Test
    fun starsHeadersHaveNoBacking() = assertSingleChartHeadersBare("Stars")

    /** A selected player's single-chart (Lead) sort: the scored song and the unscored rest are two buckets. */
    private fun assertSingleChartHeadersBare(mode: String) {
        launch(
            smallTransport(),
            prefs(
                stringPreferencesKey(SettingsRegistry.SONG_SORT) to mode,
                stringPreferencesKey(SettingsRegistry.SONG_FILTERS) to """{"instrument":"Solo_Guitar"}""",
            ),
            profile = player,
        )
        assertHeadersBare(mode)
    }

    private companion object {
        /** Keeps sampled headers above the phone's pinned floating toolbar. */
        const val TOOLBAR_CLEARANCE_DP = 120
    }
}
