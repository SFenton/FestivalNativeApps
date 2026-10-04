package com.festivalscoretracker.android.ui.profile

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import androidx.compose.ui.unit.width
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.PlayerSearchResult
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.data.RequestGate
import com.festivalscoretracker.android.presentation.ProfileSearchViewModel
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.ui.theme.FestivalAccessibility
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import java.time.Duration
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

// region Sheet states

/**
 * Issue #133: every reachable `fst.profile.*` sheet state (contract `profile-selection`)
 * on the real [ProfileSheet] with a scripted search: anonymous, debouncing, loading,
 * results, empty envelope, HTTP error, band-blocked, selected player, deselect confirm and
 * 200% text.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class ProfileSelectionSheetStatesUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val queries = mutableListOf<String>()
    private var answer: suspend (String) -> List<PlayerSearchResult> = { listOf(PlayerSearchResult(Fixtures.ACCOUNT_A, "Synthetic Player")) }
    private val viewModel = ProfileSearchViewModel { query -> queries += query; answer(query) }
    private val viewed = mutableListOf<Pair<String, String>>()
    private var dismissed = 0
    private var deselected = 0

    private fun show(player: SelectedPlayer? = null, fontScale: Float = 1f) {
        // The sheet is its own window, so the scale must come from the configuration.
        if (fontScale != 1f) RuntimeEnvironment.setFontScale(fontScale)
        rule.setContent {
            FestivalTheme {
                val density = LocalDensity.current
                CompositionLocalProvider(
                    LocalDensity provides Density(density.density, fontScale),
                    LocalFestivalAccessibility provides FestivalAccessibility(reduceMotion = true),
                ) {
                    ProfileSheet(
                        player = player,
                        searchViewModel = viewModel,
                        onViewPlayer = { id, name -> viewed += id to name },
                        onDeselect = { deselected++ },
                        onDismiss = { dismissed++ },
                    )
                }
            }
        }
        settle()
    }

    private fun settle(millis: Long = 400) {
        repeat(4) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
            rule.waitForIdle()
        }
    }

    private fun waitForTag(tag: String) {
        rule.waitUntil(5_000) {
            settle(100)
            rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun waitGone(tag: String) {
        rule.waitUntil(5_000) {
            settle(100)
            rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isEmpty()
        }
    }

    private fun tap(tag: String) {
        waitForTag(tag)
        rule.onNodeWithTag(tag).performSemanticsAction(SemanticsActions.OnClick)
        settle()
    }

    private fun heightOf(tag: String) = rule.onNodeWithTag(tag).getUnclippedBoundsInRoot().height

    private fun assertTarget(tag: String) {
        // Touch bounds include Material's minimum interactive size padding.
        val touch = rule.onNodeWithTag(tag).fetchSemanticsNode().touchBoundsInRoot
        val (w, h) = with(rule.density) { touch.width.toDp() to touch.height.toDp() }
        assertTrue("$tag touch target is $w x $h", w >= 48.dp && h >= 48.dp)
    }

    private fun isHeading(text: String) = rule.onNodeWithText(text).assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))

    @Test
    fun anonymousShowsTheHintAndPlayersTarget() {
        show()
        waitForTag("fst.profile.hint")
        assertEquals(0, rule.onAllNodesWithTag("fst.profile.selected").fetchSemanticsNodes().size)
        rule.onNodeWithText("Enter at least 2 characters").assert(hasText("Enter at least 2 characters"))
        rule.onNodeWithTag("fst.profile.scope.players").assertIsSelected()
        rule.onNodeWithTag("fst.profile.scope.bands").assertIsNotSelected()
        isHeading("Profiles")
        isHeading("Find a Profile")
        rule.onNodeWithTag("fst.profile.sheet").assert(SemanticsMatcher.expectValue(SemanticsProperties.PaneTitle, "Profiles"))
        // One character keeps the hint and never searches.
        rule.onNodeWithTag("fst.profile.search").performTextInput("s")
        settle(600)
        waitForTag("fst.profile.hint")
        assertTrue(queries.isEmpty())
        tap("fst.profile.close")
        rule.waitUntil(5_000) { settle(100); dismissed == 1 }
    }

    @Test
    fun debounceThenLoadingThenResultsOpenTheViewedPlayer() {
        val gate = CompletableDeferred<List<PlayerSearchResult>>()
        answer = { gate.await() }
        show()
        rule.onNodeWithTag("fst.profile.search").performTextInput("syn")
        // Debouncing: 250 ms must pass before the GET; the hint stays.
        assertTrue(queries.isEmpty())
        rule.onNodeWithTag("fst.profile.hint").assert(hasText("Enter at least 2 characters"))
        settle(400)
        waitForTag("fst.profile.loading")
        rule.onNodeWithTag("fst.profile.loading").assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("Searching")))
        assertEquals(listOf("syn"), queries)
        gate.complete(listOf(PlayerSearchResult(Fixtures.ACCOUNT_A, "Synthetic Player"), PlayerSearchResult(Fixtures.ACCOUNT_B, "Other Player")))
        waitForTag("fst.profile.result.${Fixtures.ACCOUNT_B}")
        waitGone("fst.profile.loading")
        assertTarget("fst.profile.result.${Fixtures.ACCOUNT_A}")
        // Clear is a labelled 48 dp icon button.
        rule.onNodeWithTag("fst.profile.clear").assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("Clear search")))
        assertTarget("fst.profile.clear")
        tap("fst.profile.result.${Fixtures.ACCOUNT_B}")
        assertEquals(listOf(Fixtures.ACCOUNT_B to "Other Player"), viewed)
        assertEquals(1, dismissed)
    }

    @Test
    fun emptyEnvelopeOffersRetry() {
        answer = { emptyList() }
        show()
        rule.onNodeWithTag("fst.profile.search").performTextInput("zzqx")
        settle(400)
        waitForTag("fst.profile.retry")
        rule.onNodeWithText("No players found").assert(hasText("No players found"))
        assertTarget("fst.profile.retry")
        tap("fst.profile.retry")
        rule.waitUntil(5_000) { settle(100); queries.size == 2 }
        // Clearing returns to the hint without another search.
        tap("fst.profile.clear")
        settle(400)
        waitForTag("fst.profile.hint")
        assertEquals(2, queries.size)
    }

    @Test
    fun httpErrorShowsInlineStatusAndRetrySearchesAgain() {
        var fail = true
        answer = { if (fail) throw FestivalApiException.HttpStatus(403) else listOf(PlayerSearchResult(Fixtures.ACCOUNT_A, "Synthetic Player")) }
        show()
        rule.onNodeWithTag("fst.profile.search").performTextInput("syn")
        settle(400)
        waitForTag("fst.service-status.inline")
        rule.onNodeWithText("Player search unavailable").assert(hasText("Player search unavailable"))
        // An error is not an empty result.
        assertEquals(0, rule.onAllNodesWithText("No players found").fetchSemanticsNodes().size)
        assertTarget("fst.profile.retry")
        fail = false
        tap("fst.profile.retry")
        waitForTag("fst.profile.result.${Fixtures.ACCOUNT_A}")
        assertEquals(2, queries.size)
    }

    @Test
    fun bandsTargetIsBlockedWithoutARequest() {
        show()
        rule.onNodeWithTag("fst.profile.search").performTextInput("syn")
        settle(400)
        waitForTag("fst.profile.result.${Fixtures.ACCOUNT_A}")
        tap("fst.profile.scope.bands")
        waitForTag("fst.profile.bands-unavailable")
        rule.onNodeWithTag("fst.profile.scope.bands").assertIsSelected()
        rule.onNodeWithTag("fst.profile.search").assertIsNotEnabled()
        assertEquals(0, rule.onAllNodesWithTag("fst.profile.clear").fetchSemanticsNodes().size)
        assertEquals(1, queries.size)
        tap("fst.profile.scope.players")
        waitForTag("fst.profile.result.${Fixtures.ACCOUNT_A}")
    }

    @Test
    fun selectedPlayerViewsAndDeselectConfirms() {
        show(SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"))
        waitForTag("fst.profile.selected")
        isHeading("Selected Profile")
        rule.onNodeWithText("Synthetic Player").assert(hasText("Synthetic Player"))
        assertTarget("fst.profile.view-selected")
        assertTarget("fst.profile.deselect")
        // Deselect confirms; Cancel keeps the player.
        tap("fst.profile.deselect")
        waitForTag("fst.profile.deselect-confirm")
        rule.onNodeWithText("Deselect Profile?").assert(hasText("Deselect Profile?"))
        tap("fst.profile.deselect-confirm.cancel")
        waitGone("fst.profile.deselect-confirm")
        assertEquals(0, deselected)
        tap("fst.profile.deselect")
        tap("fst.profile.deselect-confirm.ok")
        waitGone("fst.profile.deselect-confirm")
        assertEquals(1, deselected)
        tap("fst.profile.view-selected")
        assertEquals(listOf(Fixtures.ACCOUNT_A to "Synthetic Player"), viewed)
        assertEquals(1, dismissed)
    }

    @Test
    fun largeTextKeepsTargetsAndLabels() {
        show(SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player With A Long Name"), fontScale = 2f)
        waitForTag("fst.profile.selected")
        // The title grows with the text size (titleLarge 28 sp line; Android 14+ scales large text non-linearly).
        rule.onNodeWithTag("fst.profile.close").assertExists()
        val titleHeight = rule.onNodeWithText("Profiles").getUnclippedBoundsInRoot().height
        assertTrue("title is $titleHeight", titleHeight > 40.dp)
        listOf("fst.profile.view-selected", "fst.profile.deselect", "fst.profile.scope.players", "fst.profile.scope.bands", "fst.profile.close").forEach {
            assertTarget(it)
        }
        rule.onNodeWithTag("fst.profile.search").performTextInput("syn")
        settle(400)
        waitForTag("fst.profile.result.${Fixtures.ACCOUNT_A}")
        assertTarget("fst.profile.result.${Fixtures.ACCOUNT_A}")
        rule.onNodeWithText("Synthetic Player").assert(hasText("Synthetic Player"))
    }
}

// endregion

// region Player page states

/**
 * Issue #133: the selection states reached on the player page and Statistics: viewed,
 * syncing, selected-syncing Retry, unpinned (headerless) profile, switch confirmation,
 * publication changed (with Reload) and the selected profile's reload on a new publication.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class ProfileSelectionPageStatesUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val journey = ProfileJourney(rule)

    /** Move the fake service to publication 8 and adopt it (a later read advanced it). */
    private fun advancePublication() {
        val headers = mapOf("X-FST-Publication-Id" to "8")
        journey.transport.on("/api/publication") { Fixtures.publication(8) }
        journey.transport.on("/api/songs", headers = headers) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        ProfileFixtures.register(journey.transport, headers = headers)
        ProfileFixtures.register(journey.transport, Fixtures.ACCOUNT_B, headers = headers)
        runBlocking { journey.container.api.publication(force = true) }
        journey.settle()
    }

    private fun assertKeyless() {
        journey.transport.requests.forEach { request ->
            RequestGate.validateKeyless(request)
            assertTrue(request.headers.keys.none { it.lowercase().startsWith("x-fst-selected") })
        }
    }

    @Test
    fun viewedPlayerOffersSelectWithoutSelecting() {
        journey.launch(DebugLaunch(route = PlayerRoute(Fixtures.ACCOUNT_B, "Other"), stillBackground = true))
        journey.waitForTag("fst.player.select")
        rule.onNodeWithTag("fst.player.select").assert(hasText("Select Profile"))
        assertEquals(0, rule.onAllNodesWithTag("fst.player.reload").fetchSemanticsNodes().size)
        assertEquals(0, rule.onAllNodesWithTag("fst.nav.tab.statistics").fetchSemanticsNodes().size)
        assertTrue(rule.onNodeWithTag("fst.player.select").getUnclippedBoundsInRoot().height >= 48.dp)
        assertKeyless()
    }

    @Test
    fun syncingProfileCannotBeSelectedAndRetryReads() {
        journey.transport.on("/api/player/${Fixtures.ACCOUNT_B}", status = 202) { ProfileFixtures.syncing(Fixtures.ACCOUNT_B) }
        journey.launch(DebugLaunch(route = PlayerRoute(Fixtures.ACCOUNT_B, "Other"), stillBackground = true))
        journey.waitForTag("fst.player.syncing")
        assertEquals(0, rule.onAllNodesWithTag("fst.player.select").fetchSemanticsNodes().size)
        val before = journey.transport.sent("/api/player/${Fixtures.ACCOUNT_B}").size
        ProfileFixtures.register(journey.transport, Fixtures.ACCOUNT_B)
        journey.tap("fst.player.retry")
        journey.waitForTag("fst.player.select")
        assertEquals(before + 1, journey.transport.sent("/api/player/${Fixtures.ACCOUNT_B}").size)
    }

    @Test
    fun selectedSyncingProfileRetriesOnStatistics() {
        journey.transport.on("/api/player/${Fixtures.ACCOUNT_A}", status = 202) { ProfileFixtures.syncing() }
        journey.launch(DebugLaunch(profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), stillBackground = true))
        journey.tap("fst.nav.tab.statistics")
        journey.waitForTag("fst.player.syncing")
        val before = journey.transport.sent("/api/player/${Fixtures.ACCOUNT_A}").size
        journey.tap("fst.player.retry")
        rule.waitUntil(5_000) { journey.settle(100); journey.transport.sent("/api/player/${Fixtures.ACCOUNT_A}").size == before + 1 }
        journey.waitForTag("fst.player.syncing")
        ProfileFixtures.register(journey.transport)
        journey.tap("fst.player.retry")
        journey.waitForTag("fst.player.overview")
        journey.waitGone("fst.player.syncing")
        assertKeyless()
    }

    @Test
    fun unpinnedProfileIsPreviewedButNotSelectable() {
        ProfileFixtures.register(journey.transport, Fixtures.ACCOUNT_B, headers = emptyMap())
        journey.launch(DebugLaunch(route = PlayerRoute(Fixtures.ACCOUNT_B, "Other"), stillBackground = true))
        journey.waitForTag("fst.player.identity-notice")
        rule.onNodeWithText("These scores have no verified publication. Selection is paused.").assert(hasText("Selection is paused.", substring = true))
        assertEquals(0, rule.onAllNodesWithTag("fst.player.select").fetchSemanticsNodes().size)
        // Reloading cannot add a missing header, so no Reload is offered.
        assertEquals(0, rule.onAllNodesWithTag("fst.player.reload").fetchSemanticsNodes().size)
        journey.waitForTag("fst.player.overview")
    }

    @Test
    fun switchConfirmCancelKeepsTheSelectedPlayer() {
        journey.launch(DebugLaunch(profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), route = PlayerRoute(Fixtures.ACCOUNT_B, "Other"), stillBackground = true))
        journey.waitForTag("fst.player.select")
        rule.onNodeWithText("Switch to This Profile").assert(hasText("Switch to This Profile"))
        journey.tap("fst.player.select")
        journey.waitForTag("fst.player.switch-confirm")
        journey.tap("fst.player.switch-confirm.cancel")
        journey.waitGone("fst.player.switch-confirm")
        journey.waitForTag("fst.player.select")
        assertEquals(Fixtures.ACCOUNT_A, journey.container.selectedProfile.state.value.player?.accountId)
    }

    @Test
    fun publicationChangePausesSelectionUntilReload() {
        journey.launch(DebugLaunch(route = PlayerRoute(Fixtures.ACCOUNT_B, "Other"), stillBackground = true))
        journey.waitForTag("fst.player.select")
        val before = journey.transport.sent("/api/player/${Fixtures.ACCOUNT_B}").size
        advancePublication()
        journey.waitForTag("fst.player.identity-notice")
        rule.onNodeWithText("Published scores changed. Reload this page before selecting.").assert(hasText("Reload this page", substring = true))
        journey.waitGone("fst.player.select")
        assertTrue(rule.onNodeWithTag("fst.player.reload").getUnclippedBoundsInRoot().height >= 48.dp)
        journey.tap("fst.player.reload")
        journey.waitForTag("fst.player.select")
        journey.waitGone("fst.player.identity-notice")
        journey.waitGone("fst.player.reload")
        assertEquals(before + 1, journey.transport.sent("/api/player/${Fixtures.ACCOUNT_B}").size)
        journey.tap("fst.player.select")
        journey.waitForTag("fst.nav.tab.statistics")
        assertKeyless()
    }

    @Test
    fun selectedProfileReloadsOnANewPublication() {
        journey.launch(DebugLaunch(profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), stillBackground = true))
        journey.tap("fst.nav.tab.statistics")
        journey.waitForTag("fst.player.overview")
        val before = journey.transport.sent("/api/player/${Fixtures.ACCOUNT_A}").size
        advancePublication()
        rule.waitUntil(5_000) { journey.settle(100); journey.transport.sent("/api/player/${Fixtures.ACCOUNT_A}").size == before + 1 }
        journey.waitForTag("fst.player.overview")
        rule.waitUntil(5_000) { journey.settle(100); journey.container.selectedProfile.state.value.payload?.observedPublicationId == 8 }
        // A selected page never shows the paused notice or Reload.
        assertEquals(0, rule.onAllNodesWithTag("fst.player.identity-notice").fetchSemanticsNodes().size)
        assertEquals(0, rule.onAllNodesWithTag("fst.player.reload").fetchSemanticsNodes().size)
        assertKeyless()
    }
}

// endregion
