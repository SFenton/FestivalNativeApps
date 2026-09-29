package com.festivalscoretracker.android.ui.design

import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region See all

/**
 * A section header's "See All" link (web `rivals.seeAll` / `player.seeAll`): bold white
 * text followed by a chevron, like the web's `seeAll` span and `IoChevronForward`.
 *
 * @param onClick Open the full list.
 * @param modifier Modifier (test tag).
 * @param label Visible text.
 * @param spokenLabel Screen-reader label naming the section ("See All: Common Rivals").
 */
@Composable
fun SeeAllButton(onClick: () -> Unit, modifier: Modifier = Modifier, label: String = "See All", spokenLabel: String = label) {
    TextButton(
        onClick = onClick,
        colors = ButtonDefaults.textButtonColors(contentColor = BrandTokens.textPrimary),
        modifier = modifier.heightIn(min = 48.dp).semantics { contentDescription = spokenLabel },
    ) {
        // The button's description ("See All: <section>") is what TalkBack reads; the visible text would repeat it.
        Text(label, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, modifier = Modifier.clearAndSetSemantics { })
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, modifier = Modifier.padding(start = 2.dp).size(20.dp))
    }
}

// endregion
