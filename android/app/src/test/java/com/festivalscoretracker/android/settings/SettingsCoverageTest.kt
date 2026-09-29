package com.festivalscoretracker.android.settings

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Column
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.licenses.LicenseManifest
import com.festivalscoretracker.android.core.licenses.LicensedPackage
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.data.SettingsRepository
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.presentation.settings.ServiceVersionState
import com.festivalscoretracker.android.presentation.settings.SettingsViewModel
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.firstrun.FIRST_RUN_DEMO_IDS
import com.festivalscoretracker.android.ui.firstrun.FirstRunDemo
import com.festivalscoretracker.android.ui.shell.FestivalApp
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import java.time.Duration
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** Pure model gaps: service check failure and manifest repair. */
@OptIn(ExperimentalCoroutinesApi::class)
class SettingsLogicCoverageTest {
    @Test
    fun serviceVersionLoadsOnceAndRetriesAfterFailure() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler) + Job())
        var fail = true
        var reads = 0
        val vm = SettingsViewModel(SettingsRepository(InMemoryPreferences()), readServiceInfo = { error("unused") }, readServiceVersion = {
            reads++
            if (fail) throw FestivalApiException.Unavailable("30") else "1.2.3"
        }, scope = scope)
        assertEquals(ServiceVersionState.Loading, vm.serviceVersion.value)
        vm.loadServiceVersion()
        vm.loadServiceVersion() // ignored while loading
        advanceUntilIdle()
        assertEquals(ServiceVersionState.Unavailable, vm.serviceVersion.value)
        fail = false
        vm.loadServiceVersion()
        advanceUntilIdle()
        assertEquals(ServiceVersionState.Loaded("1.2.3"), vm.serviceVersion.value)
        vm.loadServiceVersion() // already loaded
        advanceUntilIdle()
        assertEquals(2, reads)
        vm.setVisualOrder(emptyList())
        vm.setPathColumnOrder(emptyList())
        vm.moveVisualOrder(0, 1)
        vm.setDisableShopHighlighting(true)
        advanceUntilIdle()
        scope.cancel()
    }

    @Test
    fun manifestParsingRepairsAndDropsRows() {
        assertTrue(LicenseManifest.parse(null).packages.isEmpty())
        assertTrue(LicenseManifest.parse("not json").packages.isEmpty())
        val raw = """{"version":1,"source":"x","texts":{"MIT":"mit text","Apache-2.0":"apache"},"packages":[
            {"group":"g","artifact":"b","version":"1","name":"beta","licenses":["MIT","Apache-2.0"],"url":"http://insecure"},
            {"group":"g","artifact":"a","version":"1","name":"Alpha","licenses":["MIT"],"url":"https://ok"},
            {"group":"g","artifact":"a","version":"2","name":"Alpha dup","licenses":["MIT"]},
            {"group":"g","artifact":"c","version":"1","name":"Gamma","licenses":["GPL"]},
            {"group":"g","artifact":"d","version":"1","name":"Delta","licenses":[]}]}"""
        val manifest = LicenseManifest.parse(raw)
        assertEquals(listOf("Alpha", "beta"), manifest.packages.map { it.name })
        assertNull(manifest.packages[1].url)
        assertEquals("https://ok", manifest.packages[0].url)
        assertTrue(manifest.text(manifest.packages[1]).contains("mit text") && manifest.text(manifest.packages[1]).contains("apache"))
        assertEquals("Maven · g:a 1", LicensedPackage("g", "a", "1", "n", listOf("MIT")).subtitle)
    }
}

/** Every first-run demo composes (with and without motion). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class FirstRunDemoRenderTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun everyDemoRenders() {
        rule.setContent {
            FestivalTheme {
                Column {
                    (FIRST_RUN_DEMO_IDS + "unknown-slide").forEach { id -> FirstRunDemo(id, active = true) }
                }
            }
        }
        repeat(3) { shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(300)); rule.waitForIdle() }
    }

    @Test
    fun demosRenderStillUnderReduceMotion() {
        rule.setContent {
            FestivalTheme(appReduceMotion = true) {
                Column { FIRST_RUN_DEMO_IDS.forEach { id -> FirstRunDemo(id, active = false) } }
            }
        }
        rule.waitForIdle()
    }
}

/** Medium window: the Quick Links entry opens an anchored menu instead of a sheet. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w700dp-h1000dp-xhdpi")
class MediumSettingsUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun quickLinksMenuJumps() {
        val debug = DebugLaunch(section = FestivalSection.Settings, stillBackground = true)
        val transport = FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        }
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        fun settle() = repeat(4) { shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100)); rule.waitForIdle() }
        rule.waitUntil(10_000) { settle(); rule.onAllNodesWithTag("fst.quick-links.open").fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithTag("fst.quick-links.open").performClick()
        rule.waitUntil(10_000) { settle(); rule.onAllNodesWithTag("fst.quick-links.menu").fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithTag("fst.quick-links.item.version").performSemanticsAction(SemanticsActions.OnClick)
        rule.waitUntil(10_000) { settle(); rule.onAllNodesWithTag("fst.settings.app-version").fetchSemanticsNodes().isNotEmpty() }
    }
}
