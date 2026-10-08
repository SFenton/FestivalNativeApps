package com.festivalscoretracker.android.ui.shop

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.festivalscoretracker.android.core.shop.ShopSortChoice
import com.festivalscoretracker.android.ui.songs.LiveSheet
import com.festivalscoretracker.android.ui.songs.RadioRow
import com.festivalscoretracker.android.ui.songs.SortDirectionSection

// region Sort sheet

/**
 * Sort Item Shop (issue #379): the Songs Sort sheet's frame, mode rows and direction section
 * (shared `LiveSheet`, `RadioRow`, `SortDirectionSection`) with the catalogue modes Title,
 * Artist, Year and Duration. Every change applies at once and is saved, like Songs; Reset
 * restores Title ascending.
 *
 * @param sort Applied sort (the sheet always reflects it, including after reopening).
 * @param onChange Apply and save a sort.
 * @param onDismiss Close.
 */
@Composable
fun ShopSortSheet(sort: ShopSortChoice, onChange: (ShopSortChoice) -> Unit, onDismiss: () -> Unit) {
    LiveSheet(title = "Sort Item Shop", tag = "fst.shop.sort", onReset = { onChange(ShopSortChoice()) }, onDismiss = onDismiss, titleTag = "fst.shop.sort.heading") {
        Column(Modifier.selectableGroup().testTag("fst.shop.sort.mode")) {
            ShopSortChoice.modes.forEach { mode ->
                RadioRow(mode.label, mode == sort.mode, "fst.shop.sort.${mode.name.lowercase()}") { onChange(sort.copy(mode = mode)) }
            }
        }
        SortDirectionSection(sort.ascending, "fst.shop.sort") { onChange(sort.copy(ascending = it)) }
    }
}

// endregion
