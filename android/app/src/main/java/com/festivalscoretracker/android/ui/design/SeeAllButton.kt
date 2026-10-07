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
import androidx.compose.ui.semantics.SemanticsPropertyKey
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region See all

/** The link's visible label, which leaves the accessibility tree (TalkBack reads [SeeAllButton]'s spoken label); exposed for tests only. */
internal val SeeAllVisibleLabelKey = SemanticsPropertyKey<String>("SeeAllVisibleLabel")

/**
 * Copy for the title-row link (issue #321): the app says "View All", never "See All", so the
 * link matches the purple View All buttons (`view-all-cta`).
 */
object ViewAllLinkText {
    /** Visible label. */
    const val LABEL = "View All"

    /**
     * Spoken label: the visible label first, then the list it opens (WCAG 2.5.3).
     *
     * @param section List or section name ("Common Rivals").
     * @return "View All: Common Rivals".
     */
    fun spoken(section: String) = "$LABEL: $section"
}

/**
 * A section header's "View All" link (web `rivals.seeAll` / `player.seeAll` header link):
 * bold white text followed by a chevron, like the web's `seeAll` span and `IoChevronForward`.
 *
 * @param onClick Open the full list.
 * @param modifier Modifier (test tag).
 * @param section List or section the link opens, appended to the spoken label.
 */
@Composable
fun SeeAllButton(onClick: () -> Unit, section: String, modifier: Modifier = Modifier) {
    val label = ViewAllLinkText.LABEL
    val spokenLabel = ViewAllLinkText.spoken(section)
    TextButton(
        onClick = onClick,
        colors = ButtonDefaults.textButtonColors(contentColor = BrandTokens.textPrimary),
        modifier = modifier.heightIn(min = 48.dp).semantics {
            contentDescription = spokenLabel
            set(SeeAllVisibleLabelKey, label)
        },
    ) {
        // The button's description ("View All: <section>") is what TalkBack reads; the visible text would repeat it.
        Text(label, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, modifier = Modifier.clearAndSetSemantics { })
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, modifier = Modifier.padding(start = 2.dp).size(20.dp))
    }
}

// endregion
