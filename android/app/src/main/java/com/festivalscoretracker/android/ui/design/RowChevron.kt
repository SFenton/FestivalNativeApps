package com.festivalscoretracker.android.ui.design

import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Row chevron

/**
 * The in-card chevron (›) that marks a navigable row or tile (operator batch 7, 7.3; web
 * `StatBox` / `sectionHeaderClickable` `IoChevronForward`). Decorative: the row itself
 * carries the button role and action label.
 *
 * @param modifier Modifier (placement).
 */
@Composable
fun RowChevron(modifier: Modifier = Modifier) {
    Icon(
        Icons.AutoMirrored.Filled.KeyboardArrowRight,
        contentDescription = null,
        tint = BrandTokens.textSecondary,
        modifier = modifier.size(20.dp),
    )
}

// endregion
