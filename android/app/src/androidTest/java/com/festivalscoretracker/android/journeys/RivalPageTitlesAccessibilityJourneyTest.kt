package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.rivals.RivalRoutes
import com.festivalscoretracker.android.core.rivals.RivalScope
import com.festivalscoretracker.android.core.rivals.RivalScopes
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.RivalsFixtures
import com.festivalscoretracker.android.ui.common.FestivalMarquee
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Rival page title hierarchy, decorative icons and TalkBack order at 100% and 200% text (#604). */
@DeviceCi
@RunWith(AndroidJUnit4::class)
class RivalPageTitlesAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    // region Journeys

    /** Common detail names the rival over Rivals; its section page names the section over the rival. */
    @Test
    fun commonDetailAndSectionKeepTheirTitleHierarchyAtLargeText() {
        var scale by mutableFloatStateOf(1f)
        launch(RivalScopes.song(listOf(Instrument.Lead, Instrument.Bass))) { scale }
        for (fontScale in listOf(1f, 2f)) {
            scale = fontScale
            rule.waitForIdle()
            assertBar("common-detail-$fontScale", NAME, "Rivals", fontScale)
            assertFalse(h.exists("fst.nav.subtitle-icon"))
        }
        h.tap("fst.rival-detail.see-all.closest_battles")
        h.waitForTag("fst.rivalry.list")
        for (fontScale in listOf(1f, 2f)) {
            scale = fontScale
            rule.waitForIdle()
            assertBar("rival-section-$fontScale", "Closest Battles", NAME, fontScale)
            assertFalse(h.exists("fst.nav.subtitle-icon"))
        }
        h.assertAccessible()
    }

    /** A song-scope instrument detail puts its icon before the subtitle, never before the name. */
    @Test
    fun songInstrumentDetailLeadsItsSubtitleWithTheIconAtLargeText() =
        instrumentJourney(RivalScopes.song(listOf(Instrument.Lead)), "song")

    /** The leaderboard-scope instrument detail has the same hierarchy as a song-scope detail. */
    @Test
    fun leaderboardInstrumentDetailLeadsItsSubtitleWithTheIconAtLargeText() =
        instrumentJourney(RivalScope.Leaderboard(Instrument.Lead), "leaderboard")

    /** Remove animations may truncate the visual name, but TalkBack still gets the full hierarchy. */
    @Test
    fun longRivalNameRemainsSpokenWhenReducedMotionTruncatesIt() {
        val name = "Synthetic Rival With A Very Long Name"
        val preferences = MemoryPreferences(mutablePreferencesOf(booleanPreferencesKey(SettingsRegistry.REDUCE_MOTION) to true))
        launch(RivalScopes.song(listOf(Instrument.Lead)), name, preferences) { 2f }
        assertBar("rival-long-name-reduced-motion", name, "Lead Rivals", 2f)
        val title = rule.onNode(hasTestTag("fst.nav.title") and hasText(name), useUnmergedTree = true).fetchSemanticsNode()
        assertEquals(FestivalMarquee.Mode.Truncated, title.config.getOrNull(FestivalMarquee.ModeKey))
        h.assertAccessible()
    }

    // endregion

    // region Assertions

    /** Launches a named synthetic rival, resolving its name from the read rather than the route. */
    private fun launch(scope: RivalScope, name: String = NAME, preferences: MemoryPreferences = MemoryPreferences(), scale: () -> Float) {
        h.enableAccessibilityChecks()
        val transport = RivalsFixtures.transport().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
            for (path in listOf("rivals/Solo_Guitar", "rivals/Solo_Bass", "leaderboard-rivals/Solo_Guitar")) {
                on("/api/player/${RivalsFixtures.PLAYER}/$path/${RivalsFixtures.RIVALS[0]}") {
                    RivalsFixtures.detail(RivalsFixtures.RIVALS[0], name = name)
                }
            }
        }
        h.launch(
            DebugLaunch(
                route = RivalRoutes.detail(RivalsFixtures.RIVALS[0], "Route Name", scope),
                profile = SelectedPlayer(RivalsFixtures.PLAYER, "Synthetic Player"),
                stillBackground = true,
            ),
            transport,
            preferences,
            fontScale = scale,
        )
        h.waitForTag("fst.rival-detail.category.closest_battles")
        h.publishTalkBackTree()
    }

    /** Checks geometry, font scaling, one merged noninteractive TalkBack stop and the Back target. */
    private fun assertBar(screen: String, title: String, subtitle: String, scale: Float) {
        rule.onNodeWithTag("fst.nav.title-block").assertTextEquals(title, subtitle)
        rule.onNodeWithTag("fst.nav.subtitle", useUnmergedTree = true).assertTextEquals(subtitle)
        val titleBounds = bounds("fst.nav.title")
        val subtitleBounds = bounds("fst.nav.subtitle")
        val bar = bounds("fst.nav.top-bar")
        assertTrue("$screen: subtitle above or overlapping the title", subtitleBounds.top >= titleBounds.bottom - 1)
        assertTrue("$screen: subtitle outside the bar", subtitleBounds.bottom <= bar.bottom + 1)
        h.assertTextUnclipped(screen, "fst.nav.title-block", subtitle, scale)
        h.assertTouchTarget(screen, "fst.nav.back")
        val stops = h.readingStops(screen, fresh = true)
        val titleIndex = stops.indexOfFirst { it.id == "fst.nav.title-block" }
        val backIndex = stops.indexOfFirst { it.label == "Back" }
        val contentIndex = stops.indexOfFirst { it.id == "fst.rival-detail.title" || it.id == "fst.rivalry.title" }
        assertTrue("$screen: missing or unordered Back, title, content: ${stops.map { it.label }}",
            backIndex >= 0 && titleIndex > backIndex && contentIndex > titleIndex)
        val stop = stops[titleIndex]
        assertFalse("$screen: the title is actionable", stop.isClickable)
        assertEquals("$screen: title should be one TalkBack stop", 1, stops.count { it.id == "fst.nav.title-block" })
        assertTrue("$screen: title/subtitle read out of order: ${stop.label}",
            stop.label.indexOf(title) >= 0 && stop.label.indexOf(subtitle) > stop.label.indexOf(title))
        assertFalse("$screen: unlabelled TalkBack stop", stops.any { it.label == "<unlabelled>" })
        h.assertAccessible()
    }

    private fun bounds(tag: String): Rect =
        rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot

    /** Verifies the icon follows the subtitle line's scaling and adds no spoken label. */
    private fun instrumentJourney(scope: RivalScope, screen: String) {
        var scale by mutableFloatStateOf(1f)
        launch(scope) { scale }
        val heights = mutableListOf<Float>()
        for (fontScale in listOf(1f, 2f)) {
            scale = fontScale
            rule.waitForIdle()
            assertBar("$screen-detail-$fontScale", NAME, "Lead Rivals", fontScale)
            assertFalse("The rival name must not have an instrument icon", h.exists("fst.nav.title-icon"))
            val icon = rule.onNode(
                hasTestTag(ICON) and hasAnyAncestor(hasTestTag("fst.nav.subtitle-icon")),
                useUnmergedTree = true,
            ).fetchSemanticsNode()
            assertEquals(null, icon.config.getOrNull(SemanticsProperties.ContentDescription))
            val subtitle = bounds("fst.nav.subtitle")
            val tolerance = with(rule.density) { 2.dp.toPx() }
            assertTrue("Icon must lead the subtitle", icon.boundsInRoot.right <= subtitle.left)
            assertTrue("Icon must fit the subtitle line", icon.boundsInRoot.height <= subtitle.height + tolerance)
            assertEquals(subtitle.center.y, icon.boundsInRoot.center.y, tolerance)
            heights += icon.boundsInRoot.height
        }
        assertTrue("The icon must grow with text: $heights", heights[1] > heights[0])
        h.assertAccessible()
    }

    // endregion

    private companion object {
        const val NAME = "Rival"
        const val ICON = "fst.rival-detail.subtitle-icon.Solo_Guitar"
    }
}
