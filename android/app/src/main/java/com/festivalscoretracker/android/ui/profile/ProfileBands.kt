package com.festivalscoretracker.android.ui.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.bands.PlayerBandEntry
import com.festivalscoretracker.android.core.bands.PlayerBandGroup
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.PlayerBandsRoute
import com.festivalscoretracker.android.core.profile.ProfileFormatting
import com.festivalscoretracker.android.presentation.profile.BandsLoad
import com.festivalscoretracker.android.presentation.profile.PlayerProfileUiState
import com.festivalscoretracker.android.ui.bands.PlayerBandCard
import com.festivalscoretracker.android.ui.bands.bandRouteFor
import com.festivalscoretracker.android.ui.common.FestivalLoading
import com.festivalscoretracker.android.ui.common.ServiceStatusInline
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.RowChevron
import com.festivalscoretracker.android.ui.design.SectionHeader
import com.festivalscoretracker.android.ui.design.SeeAllButton
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Bands

/*
 * "{name}'s Bands" (web `PlayerBandsSection` / `buildPlayerBandsItems`): a heading with See All, then
 * Duos, Trios and Quads, each with up to six band cards from the keyless
 * `GET /api/player/{id}/bands?group=` (the web fills them from player-stats, which natives must not
 * call), "No Bands Yet" when empty and "View All Bands (N)" when the group has more. Each part is
 * its own grid row (`ProfileSections.bandRows`), so cards sit in the profile's columns like the web.
 */

/**
 * The section heading row: "{name}'s Bands" outside any card (`section-headers` R2) with See All,
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
                modifier = Modifier.testTag("fst.player.bands-link"),
                label = "See All",
                spokenLabel = "See All ${state.displayName}'s Bands",
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
 * A band-size group's header (web `BandGroupHeader`): "Duos", "Trios" or "Quads", subordinate to the section heading.
 *
 * @param group Group.
 */
@Composable
internal fun ProfileBandGroupHeader(group: PlayerBandGroup) {
    Text(
        group.label,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.Bold,
        color = BrandTokens.textPrimary,
        modifier = Modifier.fillMaxWidth().padding(top = 4.dp, bottom = 2.dp).semantics { heading() }.testTag("fst.player.bands.header.${group.wireId}"),
    )
}

/**
 * One band card (the Bands lane's canonical `PlayerBandCard`), opening Band Detail.
 *
 * @param entry Band.
 * @param onNavigate Open the band.
 */
@Composable
internal fun ProfileBandCard(entry: PlayerBandEntry, onNavigate: (AppRoute) -> Unit) {
    PlayerBandCard(entry, onClick = { onNavigate(bandRouteFor(entry)) })
}

/**
 * "No Bands Yet" for an empty group (web `InstrumentEmptyState`), styled like the page's Top Songs empty card.
 *
 * @param group Group.
 */
@Composable
internal fun ProfileBandsEmpty(group: PlayerBandGroup) {
    GlassCard(Modifier.fillMaxWidth().testTag("fst.player.bands.empty.${group.wireId}")) {
        ProfileEmptyMessage("No Bands Yet", "Band lineups will appear here once this player posts band scores.", Modifier.padding(16.dp))
    }
}

/**
 * "View All Bands (N)" (web `BandViewAllCard`): a full-width frosted card on the canonical
 * [GlassCard] (`surface-materials` R1/R5), 48 dp tall (web `Layout.entryRowHeight`), with a
 * centred white semibold label and the in-card chevron, opening the full list on [group].
 * Not the purple `ViewFullLeaderboardButton`: that operator variant (6.29) is for leaderboard
 * and rivals cards; the web frosts this card (issue #312 design review).
 *
 * @param state Page state.
 * @param group Group.
 * @param total Bands in the group.
 * @param onNavigate Open the list.
 */
@Composable
internal fun ProfileBandsViewAll(state: PlayerProfileUiState, group: PlayerBandGroup, total: Int, onNavigate: (AppRoute) -> Unit) {
    GlassCard(
        modifier = Modifier.fillMaxWidth().semantics { role = Role.Button }.testTag("fst.player.bands.view-all.${group.wireId}"),
        onClick = { onNavigate(PlayerBandsRoute(state.accountId, state.displayName, group.wireId)) },
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 16.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "View All Bands (${ProfileFormatting.count(total.toLong())})",
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                color = BrandTokens.textPrimary,
                textAlign = TextAlign.Center,
                modifier = Modifier.weight(1f, fill = false),
            )
            RowChevron()
        }
    }
}

// endregion
