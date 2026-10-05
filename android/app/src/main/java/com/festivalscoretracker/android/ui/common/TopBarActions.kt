package com.festivalscoretracker.android.ui.common

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.platform.testTag
import com.festivalscoretracker.android.ui.design.popupTestTags

// region Top bar actions

/**
 * Pure rule for the top app bar's page actions.
 *
 * M3 top app bars keep a few trailing actions and move the rest into an overflow menu; the
 * title must not be truncated while page actions could overflow instead. The bar collapses the
 * page actions at the pane width where the title first truncated, and tries inline again only
 * once the pane is wider than that.
 */
object TopBarActionFit {
    /**
     * Whether the page actions sit inline.
     *
     * @param widthPx Current pane width.
     * @param collapsedAtPx Pane width at which the title truncated with inline actions, or null.
     * @return True when inline.
     */
    fun inline(widthPx: Int, collapsedAtPx: Int?): Boolean = collapsedAtPx == null || widthPx > collapsedAtPx

    /**
     * Pane width to remember after a title layout, or the unchanged value.
     *
     * @param titleTruncated The title just laid out truncated.
     * @param inline Page actions are inline now.
     * @param hasPageActions The page has actions to move.
     * @param widthPx Current pane width.
     * @param collapsedAtPx Current collapse width.
     * @return New collapse width.
     */
    fun afterTitleLayout(titleTruncated: Boolean, inline: Boolean, hasPageActions: Boolean, widthPx: Int, collapsedAtPx: Int?): Int? =
        if (titleTruncated && inline && hasPageActions && widthPx > 0) widthPx else collapsedAtPx
}

/**
 * Trailing top-bar actions: the page's actions (Quick Links, Sort, Filter…) inline, or behind a
 * ⋮ overflow button whose menu shows them as a row; the global actions (search, bell, profile)
 * always stay. The page actions are composed exactly once (inline or in the menu), so an action's
 * own dropdown or sheet state is never duplicated.
 *
 * @param inline Show page actions inline ([TopBarActionFit.inline]).
 * @param onPageWidth Measured width of the inline page actions (0 when there are none).
 * @param page Page actions.
 * @param global Search, notifications and profile.
 */
@Composable
fun AdaptiveTopBarActions(inline: Boolean, onPageWidth: (Int) -> Unit, page: @Composable RowScope.() -> Unit, global: @Composable RowScope.() -> Unit) {
    var overflowOpen by rememberSaveable { mutableStateOf(false) }
    Row(verticalAlignment = Alignment.CenterVertically) {
        if (inline) {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.onSizeChanged { onPageWidth(it.width) }, content = page)
        } else {
            Box {
                IconButton(onClick = { overflowOpen = true }, modifier = Modifier.testTag("fst.nav.overflow")) {
                    Icon(Icons.Filled.MoreVert, contentDescription = "More actions")
                }
                DropdownMenu(expanded = overflowOpen, onDismissRequest = { overflowOpen = false }, modifier = Modifier.popupTestTags()) {
                    CloseWhenRefocused { overflowOpen = false }
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.testTag("fst.nav.overflow-menu"), content = page)
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, content = global)
    }
}

/**
 * When the overflow menu should close after a window-focus change.
 *
 * The menu's actions own their sheets and menus (Quick Links keeps its open state inside the
 * action), so closing the menu as soon as an action is tapped would dispose them. Instead the menu
 * closes when its own popup window gets focus back after a sheet, dialog or nested menu that one of
 * its actions opened has closed: M3 menus close once an item has done its work.
 */
class OverflowRefocusRule {
    private var focusedOnce = false
    private var lostFocus = false

    /**
     * Records the menu window's focus.
     *
     * @param focused The menu's popup window has focus now.
     * @return True when the menu should close (focus came back after the menu had lost it).
     */
    fun onFocusChanged(focused: Boolean): Boolean = when {
        focused && lostFocus -> true
        focused -> {
            focusedOnce = true
            false
        }
        else -> {
            lostFocus = focusedOnce
            false
        }
    }
}

/** Calls [onClose] when the hosting popup window regains focus ([OverflowRefocusRule]). */
@Composable
private fun CloseWhenRefocused(onClose: () -> Unit) {
    val focused = LocalWindowInfo.current.isWindowFocused
    val rule = remember { OverflowRefocusRule() }
    val close by rememberUpdatedState(onClose)
    LaunchedEffect(focused) {
        if (rule.onFocusChanged(focused)) close()
    }
}

// endregion
