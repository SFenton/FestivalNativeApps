package com.festivalscoretracker.android.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Explore
import androidx.compose.material.icons.outlined.FilterList
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.SwapVert
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.LocalShellActions
import com.festivalscoretracker.android.ui.common.ShellActions
import com.festivalscoretracker.android.ui.common.TopBarActionFit
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Page actions overflow instead of truncating the title on narrow panes (book half-open list pane ≈ 430 dp). Native graphics for real text widths. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w900dp-h900dp-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class TopBarActionsUiTest {
    @get:Rule
    val rule = createComposeRule()

    private fun show(width: Dp, title: String = "Leaderboards") {
        rule.setContent {
            FestivalTheme {
                CompositionLocalProvider(
                    LocalShellActions provides ShellActions(
                        openDrawer = {},
                        selectedPlayer = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"),
                        notifications = { IconButton(onClick = {}, modifier = Modifier.testTag("bell")) { Icon(Icons.Outlined.Notifications, "Notifications") } },
                    ),
                ) {
                    Box(Modifier.width(width).fillMaxHeight()) {
                        FestivalScreen(title = title, isRoot = true, actions = {
                            IconButton(onClick = {}, modifier = Modifier.testTag("page.quick-links")) { Icon(Icons.Outlined.Explore, "Quick Links") }
                            IconButton(onClick = {}, modifier = Modifier.testTag("page.sort")) { Icon(Icons.Outlined.SwapVert, "Sort") }
                            IconButton(onClick = {}, modifier = Modifier.testTag("page.filter")) { Icon(Icons.Outlined.FilterList, "Filter") }
                        }) {}
                    }
                }
            }
        }
        rule.waitForIdle()
    }

    private fun titleOverflows(): Boolean {
        val results = mutableListOf<TextLayoutResult>()
        rule.onNode(hasText("Leaderboards")).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(results) }
        return results.single().let { it.hasVisualOverflow || it.isLineEllipsized(0) }
    }

    private fun androidx.compose.ui.test.SemanticsNodeInteraction.performSemanticsAction(
        key: androidx.compose.ui.semantics.SemanticsPropertyKey<androidx.compose.ui.semantics.AccessibilityAction<(MutableList<TextLayoutResult>) -> Boolean>>,
        invoke: ((MutableList<TextLayoutResult>) -> Boolean) -> Unit,
    ) {
        invoke(fetchSemanticsNode().config[key].action!!)
    }

    @Test
    fun narrowPaneMovesPageActionsToOverflow() {
        show(430.dp)
        rule.onNodeWithTag("fst.nav.overflow").assertIsDisplayed()
        assertEquals(0, rule.onAllNodesWithTag("page.sort").fetchSemanticsNodes().size)
        rule.onNodeWithTag("fst.global-search.open").assertIsDisplayed()
        rule.onNodeWithTag("bell").assertIsDisplayed()
        rule.onNodeWithTag("fst.nav.profile").assertIsDisplayed()
        assertFalse(titleOverflows())
        rule.onNodeWithTag("fst.nav.overflow").performClick()
        rule.onNodeWithTag("fst.nav.overflow-menu").assertIsDisplayed()
        rule.onNodeWithTag("page.sort").assertIsDisplayed()
    }

    @Test
    fun widePaneKeepsEverythingInline() {
        show(700.dp)
        assertEquals(0, rule.onAllNodesWithTag("fst.nav.overflow").fetchSemanticsNodes().size)
        rule.onNodeWithTag("page.quick-links").assertIsDisplayed()
        rule.onNodeWithTag("page.filter").assertIsDisplayed()
        assertFalse(titleOverflows())
    }

    @Test
    fun fitRule() {
        assertTrue(TopBarActionFit.inline(widthPx = 430, collapsedAtPx = null))
        assertFalse(TopBarActionFit.inline(widthPx = 430, collapsedAtPx = 430))
        assertTrue(TopBarActionFit.inline(widthPx = 700, collapsedAtPx = 430))
        assertEquals(430, TopBarActionFit.afterTitleLayout(true, inline = true, hasPageActions = true, widthPx = 430, collapsedAtPx = null))
        assertEquals(null, TopBarActionFit.afterTitleLayout(true, inline = true, hasPageActions = false, widthPx = 430, collapsedAtPx = null))
        assertEquals(300, TopBarActionFit.afterTitleLayout(true, inline = false, hasPageActions = true, widthPx = 430, collapsedAtPx = 300))
        assertEquals(null, TopBarActionFit.afterTitleLayout(false, inline = true, hasPageActions = true, widthPx = 430, collapsedAtPx = null))
    }
}
