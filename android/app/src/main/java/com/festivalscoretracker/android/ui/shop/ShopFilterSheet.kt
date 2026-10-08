package com.festivalscoretracker.android.ui.shop

import androidx.compose.runtime.Composable
import com.festivalscoretracker.android.core.shop.ShopOfferFilter
import com.festivalscoretracker.android.ui.songs.Hint
import com.festivalscoretracker.android.ui.songs.LiveSheet
import com.festivalscoretracker.android.ui.songs.ToggleRow

// region Filter sheet

/**
 * Filter Item Shop (issues #19, #376): New, Available and Leaving Tomorrow include switches
 * in the Songs filter sheet's frame and rows (shared header Close, red Reset). They start on
 * (every offer shows) and turning one off hides that group. Every change applies at once,
 * like Songs.
 *
 * @param filter Applied filter (the sheet always reflects it, including after reopening).
 * @param onChange Apply a filter.
 * @param onDismiss Close.
 */
@Composable
fun ShopFilterSheet(filter: ShopOfferFilter, onChange: (ShopOfferFilter) -> Unit, onDismiss: () -> Unit) {
    LiveSheet(title = "Filter Item Shop", tag = "fst.shop.filter", onReset = { onChange(ShopOfferFilter()) }, onDismiss = onDismiss) {
        Hint("Turn a switch off to hide those Item Shop songs. With every switch on, all songs show.")
        ToggleRow("New", "Songs that are new in the Item Shop today.", filter.new, enabled = true, tag = "fst.shop.filter.new") {
            onChange(filter.copy(new = it))
        }
        ToggleRow(
            "Available",
            "Songs in the Item Shop today that aren't new or leaving tomorrow.",
            filter.available,
            enabled = true,
            tag = "fst.shop.filter.available",
        ) { onChange(filter.copy(available = it)) }
        ToggleRow("Leaving Tomorrow", "Songs that are leaving the Item Shop tomorrow.", filter.leavingTomorrow, enabled = true, tag = "fst.shop.filter.leaving") {
            onChange(filter.copy(leavingTomorrow = it))
        }
    }
}

// endregion
