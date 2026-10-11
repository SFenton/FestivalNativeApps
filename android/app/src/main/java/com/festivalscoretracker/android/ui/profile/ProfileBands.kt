package com.festivalscoretracker.android.ui.profile

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.bands.PlayerBandGroup
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.PlayerBandsRoute
import com.festivalscoretracker.android.core.profile.ProfileFormatting
import com.festivalscoretracker.android.core.profile.ProfileRow
import com.festivalscoretracker.android.presentation.profile.BandsLoad
import com.festivalscoretracker.android.presentation.profile.PlayerProfileUiState
import com.festivalscoretracker.android.ui.bands.PlayerBandRow
import com.festivalscoretracker.android.ui.bands.bandRouteFor
import com.festivalscoretracker.android.ui.common.FestivalLoading
import com.festivalscoretracker.android.ui.common.ServiceStatusInline
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.SectionHeader
import com.festivalscoretracker.android.ui.design.SeeAllButton
import com.festivalscoretracker.android.ui.design.ViewFullLeaderboardButton
import com.festivalscoretracker.android.ui.songdetail.RowSeparator
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Bands

/*
 * "{name}'s Bands" (web `PlayerBandsSection` / `buildPlayerBandsItems`): a heading with View All (`section-headers` R8), then
 * Duos, Trios and Quads, each with up to six band cards from the keyless
 * `GET /api/player/{id}/bands?group=` (the web fills them from player-stats, which natives must not
 * call). Each group is one card of band rows ending in the purple "View All Bands (N)", or
 * "No Bands Yet" when empty (owner #596; the web draws a card per band). Each group is one grid
 * row (`ProfileSections.bandRow`), so groups sit in the profile's columns like the Top Songs cards.
 */

/**
 * The section heading row: "{name}'s Bands" outside any card (`section-headers` R2) with View All (R8),
 * then the preview's loading or inline failure state, which never blocks the rest of the page.
 *
 * @param state Page state.
 * @param bands Preview load, or null before the section is shown.
 * @param onRetry Retry after a failure.
 * @param onNavigate Open the full list.
 */
@Composable
internal fun ProfileBandsHeading(state: PlayerProfileUiState, bands: BandsLoad?, onRetry: () -> Unit, onNavigate: (AppRoute) -> Unit) {
    Column(Modifier.fillMaxWidth().testTag("fst.player.bands")) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            SectionHeader("${state.displayName}'s Bands", Modifier.weight(1f))
            SeeAllButton(
                onClick = { onNavigate(PlayerBandsRoute(state.accountId, state.displayName)) },
                section = "${state.displayName}'s Bands",
                modifier = Modifier.testTag("fst.player.bands-link"),
            )
        }
        when (bands) {
            null, BandsLoad.Loading -> FestivalLoading("Loading bands", Modifier.testTag("fst.player.bands.loading"), size = 24.dp)
            is BandsLoad.Failed -> ServiceStatusInline(bands.issue, "Bands unavailable", null, onRetry, retryTag = "fst.player.bands.retry")
            is BandsLoad.Loaded -> Unit
        }
    }
}

/**
 * One band-size group (owner #596): the group header, then one card of its bands, each a bare
 * [PlayerBandRow] (no size pill, the header names it) with the shared hairline between rows,
 * ending in the shared purple [ViewFullLeaderboardButton] "View All Bands (N)" like Song Detail's
 * band cards (`view-all-cta` R1–R4, `leaderboard-row` R10). An empty group shows "No Bands Yet".
 *
 * @param state Page state.
 * @param row The group.
 * @param onNavigate Open a band or the group's full list.
 */
@Composable
internal fun ProfileBandGroupSection(state: PlayerProfileUiState, row: ProfileRow.BandGroup, onNavigate: (AppRoute) -> Unit) {
    Column(Modifier.fillMaxWidth()) {
        ProfileBandGroupHeader(row.group)
        if (row.entries.isEmpty()) {
            ProfileBandsEmpty(row.group)
        } else {
            GlassCard(Modifier.fillMaxWidth().testTag("fst.player.bands.card.${row.group.wireId}")) {
                Column(Modifier.padding(vertical = 4.dp)) {
                    row.entries.forEachIndexed { index, entry ->
                        if (index > 0) RowSeparator()
                        PlayerBandRow(entry, onClick = { onNavigate(bandRouteFor(entry)) })
                    }
                    if (row.showsViewAll) ProfileBandsViewAll(state, row.group, row.total, onNavigate)
                }
            }
        }
    }
}

/**
 * A band-size group's header (web `BandGroupHeader`): "Duos", "Trios" or "Quads", subordinate to the section heading.
 *
 * @param group Group.
 */
@Composable
private fun ProfileBandGroupHeader(group: PlayerBandGroup) {
    Text(
        group.label,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.Bold,
        color = BrandTokens.textPrimary,
        modifier = Modifier.fillMaxWidth().padding(top = 4.dp, bottom = 6.dp).semantics { heading() }.testTag("fst.player.bands.header.${group.wireId}"),
    )
}

/**
 * "No Bands Yet" for an empty group (web `InstrumentEmptyState`), styled like the page's Top Songs empty card.
 *
 * @param group Group.
 */
@Composable
private fun ProfileBandsEmpty(group: PlayerBandGroup) {
    GlassCard(Modifier.fillMaxWidth().testTag("fst.player.bands.empty.${group.wireId}")) {
        ProfileEmptyMessage("No Bands Yet", "Band lineups will appear here once this player posts band scores.", Modifier.padding(16.dp))
    }
}

/**
 * "View All Bands (N)" ending the group card: the shared purple CTA (owner #596 over the web's
 * frosted `BandViewAllCard`, `surface-materials` R7 variant), spoken "View All Bands (N), Duos"
 * (`view-all-cta` R4), opening the full list on [group] (R8).
 *
 * @param state Page state.
 * @param group Group.
 * @param total Bands in the group.
 * @param onNavigate Open the list.
 */
@Composable
private fun ProfileBandsViewAll(state: PlayerProfileUiState, group: PlayerBandGroup, total: Int, onNavigate: (AppRoute) -> Unit) {
    ViewFullLeaderboardButton(
        onClick = { onNavigate(PlayerBandsRoute(state.accountId, state.displayName, group.wireId)) },
        label = "View All Bands (${ProfileFormatting.count(total.toLong())})",
        testTag = "fst.player.bands.view-all.${group.wireId}",
        cardName = group.label,
        modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
    )
}

// endregion
