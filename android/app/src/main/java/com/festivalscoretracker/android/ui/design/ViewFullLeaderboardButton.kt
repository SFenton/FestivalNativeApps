package com.festivalscoretracker.android.ui.design

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region View full leaderboard

/**
 * The one "View full leaderboard" call to action used everywhere (operator batch 6,
 * item 6.29): a full-width, 48 dp, filled brand-purple button with white semibold
 * text, so song, instrument and ranking cards all end the same way. Web source:
 * `ViewFullLeaderboardCta` (same label and placement; the operator chose purple over
 * the web's frosted fill).
 *
 * @param onClick Open the full leaderboard.
 * @param modifier Modifier (callers add padding inside their card).
 * @param label Visible label, for example "View full leaderboard" or "View all rankings (1,234)".
 * @param testTag Test tag.
 */
@Composable
fun ViewFullLeaderboardButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    label: String = VIEW_FULL_LEADERBOARD,
    testTag: String = "fst.view-full-leaderboard",
) {
    Button(
        onClick = onClick,
        shape = RoundedCornerShape(12.dp),
        colors = ButtonDefaults.buttonColors(containerColor = BrandTokens.accentPurple, contentColor = BrandTokens.textPrimary),
        modifier = modifier.fillMaxWidth().heightIn(min = 48.dp).testTag(testTag),
    ) {
        Text(label, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
    }
}

/** Default label (web `leaderboard.viewFullShort`, Title Case per the capitalization rule). */
const val VIEW_FULL_LEADERBOARD = "View Full Leaderboard"

// endregion
