package com.festivalscoretracker.android.ui.songs

import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.core.shop.ShopPulse
import com.festivalscoretracker.android.core.songs.SongInstrumentStatus
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.SongsFixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import com.festivalscoretracker.android.ui.theme.BrandTokens
import java.io.ByteArrayOutputStream
import java.time.Duration
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Songs rows and the Paths image drawn with native graphics, so draw-phase pulses and decoding run. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SongsDrawUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")

    private val profileJson = """
        {"accountId":"${Fixtures.ACCOUNT_A}","displayName":"Synthetic Player","totalScores":2,"scores":[
          {"si":"s-alpha","ins":"01","sc":95198,"acc":987,"fc":true,"st":6,"sn":15,"dif":3,"rk":42,"te":1000,"lp":"2026-09-01T12:00:00Z"},
          {"si":"s-beta","ins":"02","sc":5000,"acc":500,"fc":false,"st":2,"sn":9,"dif":1,"rk":900,"te":1000,"lp":"2026-09-20T12:00:00Z"}
        ]}
    """.trimIndent()

    private fun realPng(): ByteArray {
        val bitmap = Bitmap.createBitmap(100, 200, Bitmap.Config.ARGB_8888).apply { eraseColor(android.graphics.Color.BLUE) }
        return ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    }

    private fun transport() = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        on("/api/shop", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.shopJson.replace("\"b.jpg\"", "null") }
        on("/api/player/${Fixtures.ACCOUNT_A}", headers = mapOf("X-FST-Publication-Id" to "7")) { profileJson }
        val png = realPng()
        onRaw("/api/paths/s-alpha/Solo_Guitar/expert") { HttpResult(200, png, mapOf("X-FST-Publication-Id" to "7")) }
        on("/api/paths/s-alpha/Solo_Guitar/expert/data", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.pathJson }
    }

    private fun launch(debug: DebugLaunch, prefs: InMemoryPreferences = InMemoryPreferences()) {
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport(), settingsStore = prefs)
        rule.setContent { FestivalApp(container, debug) }
        settle()
    }

    private fun settle(millis: Long = 400) {
        repeat(4) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
            rule.waitForIdle()
        }
    }

    private fun waitForTag(tag: String, unmerged: Boolean = false) {
        rule.waitUntil(10_000) {
            settle(100)
            rule.onAllNodesWithTag(tag, useUnmergedTree = unmerged).fetchSemanticsNodes().isNotEmpty()
        }
    }

    /** Draw the window into a bitmap (runs every draw lambda on screen); true when something was painted. */
    private fun draw(): Boolean {
        val root = rule.activity.window.decorView
        val bitmap = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
        rule.runOnUiThread { root.draw(Canvas(bitmap)) }
        return (0 until bitmap.height step 16).any { y -> (0 until bitmap.width step 16).any { x -> bitmap.getPixel(x, y) != 0 } }
    }

    @Test
    fun lastPlayedRowsDrawShopPulsesAndBadges() {
        launch(DebugLaunch(profile = player, stillBackground = true), InMemoryPreferences(mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.SONG_SORT) to "LastPlayed")))
        waitForTag("fst.songs.last-played.s-alpha", unmerged = true)
        waitForTag("fst.songs.shop-badge.s-beta", unmerged = true)
        assertTrue(draw())
    }

    @Test
    fun pathsImageDecodesAndDraws() {
        launch(DebugLaunch(songQuery = "s-alpha", stillBackground = true))
        waitForTag("fst.song-detail.list")
        rule.onNodeWithTag("fst.song-detail.list").performScrollToNode(hasTestTag("fst.song-detail.paths.open"))
        rule.onNodeWithTag("fst.song-detail.paths.open").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.paths.image")
        waitForTag("fst.paths.zoom-in")
        rule.waitUntil(10_000) { settle(100); rule.onAllNodesWithTag("fst.paths.image-error").fetchSemanticsNodes().isEmpty() }
        assertTrue(draw())
    }

    @Test
    fun shopTokensMatchTheStatusColors() {
        assertEquals(BrandTokens.statusGreen, SongsTokens.pulse(ShopPulse.InShop))
        assertEquals(BrandTokens.gold, SongsTokens.pulse(ShopPulse.New))
        assertEquals(BrandTokens.statusRed, SongsTokens.pulse(ShopPulse.LeavingTomorrow))
        assertEquals(SongsTokens.breatheBase, SongsTokens.breathe(ShopPulse.InShop, 0f))
        assertEquals(SongsTokens.statusGreenStroke, SongsTokens.breathe(ShopPulse.InShop, 1f))
        assertEquals(SongsTokens.goldStroke, SongsTokens.breathe(ShopPulse.New, 2f))
        assertEquals(BrandTokens.statusRed, SongsTokens.breathe(ShopPulse.LeavingTomorrow, 1f))
        assertEquals(SongsTokens.statusAmber to SongsTokens.statusAmberStroke, SongsTokens.chip(SongInstrumentStatus.InconsistentFullCombo))
        assertEquals(Color(red = 34, green = 139, blue = 34), SongsTokens.maxScore(120.0))
        assertNotEquals(SongsTokens.maxScore(0.0), SongsTokens.maxScore(100.0))
    }
}
