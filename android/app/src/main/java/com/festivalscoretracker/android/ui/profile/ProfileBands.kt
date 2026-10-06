package com.festivalscoretracker.android.ui.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.ui.design.ViewFullLeaderboardButton
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.PlayerBandsRoute
import com.festivalscoretracker.android.core.profile.ProfileFormatting
import com.festivalscoretracker.android.presentation.profile.BandsLoad
import com.festivalscoretracker.android.presentation.profile.PlayerProfileUiState
import com.festivalscoretracker.android.ui.bands.PlayerBandCard
import com.festivalscoretracker.android.ui.bands.bandRouteFor
import com.festivalscoretracker.android.ui.common.FestivalLoading
import com.festivalscoretracker.android.ui.common.ServiceStatusInline
import com.festivalscoretracker.android.ui.common.fadeInStagger
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import com.festivalscoretracker.android.ui.common.rememberRevealed
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.SeeAllButton
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Bands

/**
 * "{name}'s Bands" (web `PlayerBandsSection`): the first few bands from the keyless
 * `GET /api/player/{id}/bands`, each opening Band Detail, plus "View All" and "View All
 * Bands (N)" into Player Bands. The web fills this from player-stats (blocked); one
 * All-group page replaces its per-size previews.
 *
 * @param state Page state.
 * @param bands Preview load, or null before the section is shown.
 * @param onRetry Retry after a failure.
 * @param onNavigate Open a band or the full list.
 */
@Composable
internal fun ProfileBandsSection(state: PlayerProfileUiState, bands: BandsLoad?, onRetry: () -> Unit, onNavigate: (AppRoute) -> Unit) {
    val all = PlayerBandsRoute(state.accountId, state.displayName)
    val revealed = rememberRevealed(bands is BandsLoad.Loaded)
    GlassCard(Modifier.fillMaxWidth().testTag("fst.player.bands")) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "${state.displayName}'s Bands",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = BrandTokens.textPrimary,
                    modifier = Modifier.weight(1f).semantics { heading() },
                )
                SeeAllButton(onClick = { onNavigate(all) }, section = "${state.displayName}'s Bands", modifier = Modifier.testTag("fst.player.bands-link"))
            }
            when (bands) {
                null, BandsLoad.Loading -> FestivalLoading("Loading bands", Modifier.testTag("fst.player.bands.loading"), size = 24.dp)
                is BandsLoad.Failed -> ServiceStatusInline(bands.issue, "Bands unavailable", null, onRetry)
                is BandsLoad.Loaded -> if (bands.bands.entries.isEmpty()) {
                    Column(Modifier.testTag("fst.player.bands.empty")) {
                        Text("No Bands Yet", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary)
                        Text("Band lineups will appear here once this player posts band scores.", style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textPrimary)
                    }
                } else {
                    bands.bands.entries.forEachIndexed { index, entry ->
                        PlayerBandCard(entry, onClick = { onNavigate(bandRouteFor(entry)) }, modifier = Modifier.festivalFadeIn(revealed, fadeInStagger(index)))
                    }
                    if (bands.bands.totalCount > bands.bands.entries.size) {
                        ViewFullLeaderboardButton(
                            onClick = { onNavigate(all) },
                            label = "View All Bands (${ProfileFormatting.count(bands.bands.totalCount.toLong())})",
                            testTag = "fst.player.bands.view-all",
                        )
                    }
                }
            }
        }
    }
}

// endregion
