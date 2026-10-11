package com.festivalscoretracker.android.ui.rivals

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.festivalscoretracker.android.ui.design.RowChevron
import com.festivalscoretracker.android.ui.design.ViewFullLeaderboardButton
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.rivals.RivalDirection
import com.festivalscoretracker.android.core.rivals.RivalEntry
import com.festivalscoretracker.android.core.rivals.RivalHeadToHead
import com.festivalscoretracker.android.core.rivals.RivalSentiment
import com.festivalscoretracker.android.core.rivals.RivalSongComparison
import com.festivalscoretracker.android.core.rivals.RivalSongStanding
import com.festivalscoretracker.android.core.rivals.RivalText
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.ui.common.FestivalEmptyState
import com.festivalscoretracker.android.ui.common.FestivalLoading
import com.festivalscoretracker.android.ui.common.FestivalMarqueeText
import com.festivalscoretracker.android.ui.common.ServiceStatusInline
import com.festivalscoretracker.android.ui.common.fadeInStagger
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import com.festivalscoretracker.android.ui.common.isLargeText
import com.festivalscoretracker.android.ui.design.CardSegment
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.GlassCardSegment
import com.festivalscoretracker.android.ui.songdetail.RowSeparator
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.design.SeeAllButton
import com.festivalscoretracker.android.ui.theme.BrandTokens
import java.text.NumberFormat

// region Colors

/** Rivals tints (web `rivalGreen*` / `rivalRed*`), lightened for text contrast on dark glass. */
internal object RivalColors {
    val winText = Color(0xFF4ADE80)
    val loseText = Color(0xFFFF8A80)
    val winBackground = Color(0x2E2ECC71)
    val loseBackground = Color(0x2EC62828)
    val winBorder = Color(0x662ECC71)
    val loseBorder = Color(0x66C62828)
    val neutralBackground = Color(0x1FFFFFFF)
}

private fun sentimentColor(sentiment: RivalSentiment): Color = when (sentiment) {
    RivalSentiment.Positive -> RivalColors.winText
    RivalSentiment.Negative -> RivalColors.loseText
    RivalSentiment.Neutral -> BrandTokens.textPrimary
}

// endregion

// region Pills

/**
 * Tinted status capsule (`rival-rows` R2, iOS `RivalStatusPill`): the hub rows' "N songs ahead /
 * behind" counts and the song rows' "#rank Name" sides. The text always carries the meaning, so
 * colour is never the only signal. One line, ellipsized; at large text it wraps instead.
 *
 * @param text Label.
 * @param win Green when true, red when false, neutral when null.
 * @param modifier Modifier.
 */
@Composable
internal fun RivalPill(text: String, win: Boolean?, modifier: Modifier = Modifier) {
    val (fg, bg, border) = when (win) {
        true -> Triple(RivalColors.winText, RivalColors.winBackground, RivalColors.winBorder)
        false -> Triple(RivalColors.loseText, RivalColors.loseBackground, RivalColors.loseBorder)
        null -> Triple(BrandTokens.textPrimary, RivalColors.neutralBackground, BrandTokens.glassBorder)
    }
    val large = isLargeText()
    Text(
        text,
        style = MaterialTheme.typography.labelMedium,
        fontWeight = FontWeight.SemiBold,
        color = fg,
        maxLines = if (large) Int.MAX_VALUE else 1,
        overflow = TextOverflow.Ellipsis,
        modifier = modifier
            .clip(CircleShape)
            .background(bg)
            .border(1.dp, border, CircleShape)
            .padding(horizontal = 8.dp, vertical = 3.dp),
    )
}

// endregion

// region Rival row

/**
 * One rival as a bare row of its list's card (`rival-rows`, iOS `RivalRowContent`): a status
 * dot (green when you lead, red when the rival is ahead), the name and "songs ahead / songs
 * behind" pills, then a chevron. Anonymous rows are not tappable. Unlike the web, there is no
 * shared-song count (owner decision, issues #40/#67): it is always ahead + behind, so it only
 * repeated the pills. Place it in one [GlassCard] with its siblings ([RivalPreviewRows]) or a
 * [GlassCardSegment] (All Rivals), never in a card of its own (#603).
 *
 * @param entry Row data and side.
 * @param onClick Opens Rival Detail; ignored for anonymous rows. Null draws a decorative,
 *   non-interactive row (First Run demos, issue #380) with the same look.
 * @param modifier Modifier.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun RivalRow(entry: RivalEntry, onClick: (() -> Unit)?, modifier: Modifier = Modifier) {
    val rival = entry.rival
    val winning = entry.direction == RivalDirection.Below
    val format = NumberFormat.getIntegerInstance()
    val ahead = "${format.format(rival.behindCount)} songs ahead"
    val behind = "${format.format(rival.aheadCount)} songs behind"
    val description = "${rival.shownName}, ${if (winning) "you lead" else "ahead of you"}, $ahead, $behind"
    val open = onClick?.takeIf { rival.isNavigable }
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .testTag(if (rival.isNavigable) "fst.rivals.row.${rival.accountId}" else "fst.rivals.row.anonymous")
            .clearAndSetSemantics {
                contentDescription = description
                if (open != null) {
                    role = Role.Button
                    onClick(label = "Open rival") { open(); true }
                }
            }
            .then(if (open != null) Modifier.clickable(onClick = open) else Modifier)
            .padding(start = 14.dp, end = 10.dp, top = 12.dp, bottom = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(8.dp).background(if (winning) BrandTokens.statusGreen else BrandTokens.statusRed, CircleShape))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            val nameColor = if (rival.isNavigable) BrandTokens.textPrimary else BrandTokens.textMuted
            if (isLargeText()) {
                // Large text: the name wraps instead of being squeezed to an ellipsis.
                Text(rival.shownName, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = nameColor)
            } else {
                // Web `RivalRow` truncates names with an ellipsis (operator 7.14: never marquee
                // every name on Compete/Rivals).
                Text(
                    rival.shownName,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = nameColor,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                RivalPill(ahead, win = true)
                RivalPill(behind, win = false)
            }
        }
        if (rival.isNavigable) RowChevron()
    }
}

// endregion

// region Section card

/**
 * A titled group with a "View All" link (web section header card).
 *
 * @param title Title Case heading.
 * @param modifier Modifier.
 * @param instrument Leading chart icon.
 * @param description Secondary line.
 * @param titleColor Heading color (category sentiment).
 * @param onSeeAll "View All" action, or null to hide it.
 * @param seeAllTag Test tag for "View All".
 */
@Composable
fun RivalSectionHeader(
    title: String,
    modifier: Modifier = Modifier,
    instrument: Instrument? = null,
    description: String? = null,
    titleColor: Color = BrandTokens.textPrimary,
    onSeeAll: (() -> Unit)? = null,
    seeAllTag: String? = null,
) {
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        if (instrument != null) InstrumentIcon(instrument, size = 36.dp, decorative = true)
        // Traversal group: TalkBack reads the title and its description before the
        // vertically centred View All, which otherwise sorts between them.
        Column(Modifier.weight(1f).semantics { isTraversalGroup = true }) {
            Text(
                title,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = titleColor,
                modifier = Modifier.semantics { heading() },
            )
            if (description != null) Text(description, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textSecondary)
        }
        if (onSeeAll != null) {
            SeeAllButton(
                onClick = onSeeAll,
                section = title,
                modifier = if (seeAllTag != null) Modifier.testTag(seeAllTag) else Modifier,
            )
        }
    }
}

/**
 * The hub's and Compete's per-scope rivals card (`rival-rows`, iOS `FestivalGlassSection`): one
 * [GlassCard] of hairline-separated [RivalRow]s ending in "View all rivals" inside the card
 * (`view-all-cta` R1). The card fades in as one, with all its rows (`load-transition` R11).
 *
 * @param rows Preview rows.
 * @param onRival Row tap.
 * @param onViewAll "View all rivals".
 * @param viewAllLabel Button text.
 * @param revealed Whether the rows have finished loading ([festivalFadeIn]: web `nextStagger`).
 * @param cardName The card's title, spoken after the button label (`view-all-cta` R4).
 * @param firstStagger Entrance index of the card (Compete continues its page-wide order, web
 *   `useStagger().next()`).
 */
@Composable
fun RivalPreviewRows(
    rows: List<RivalEntry>,
    onRival: (RivalEntry) -> Unit,
    onViewAll: (() -> Unit)?,
    viewAllLabel: String = RivalText.VIEW_ALL_RIVALS,
    revealed: Boolean = true,
    cardName: String? = null,
    firstStagger: Int = 1,
) {
    GlassCard(Modifier.fillMaxWidth().testTag(RIVALS_CARD_TAG).festivalFadeIn(revealed, fadeInStagger(firstStagger))) {
        Column(Modifier.padding(vertical = 4.dp)) {
            rows.forEachIndexed { index, entry ->
                androidx.compose.runtime.key(entry.key(index)) {
                    if (index > 0) RowSeparator()
                    RivalRow(entry, onClick = { onRival(entry) })
                }
            }
            if (onViewAll != null) {
                ViewFullLeaderboardButton(
                    onClick = onViewAll,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                    label = viewAllLabel,
                    testTag = "fst.rivals.view-all",
                    cardName = cardName,
                )
            }
        }
    }
}

/** Test tag of every card that groups rival rows (one per list; addressed through its section's tag). */
const val RIVALS_CARD_TAG = "fst.rivals.card"

/** Test tag of each lazy slice of a long list's one card ([RivalCardSegment]). */
const val RIVALS_CARD_SEGMENT_TAG = "fst.rivals.card.segment"

/**
 * One row's slice of a long rival list's single card (All Rivals, Rivalry): a [GlassCardSegment]
 * with the hairline above every row but the first and the card's 4 dp end padding, so lazy rows
 * stacked with no gap read as the one card [RivalPreviewRows] and Rival Detail draw.
 *
 * @param index Row index in the list.
 * @param count Rows in the list.
 * @param modifier Modifier (the card's shared fade).
 * @param content The row.
 */
@Composable
fun RivalCardSegment(index: Int, count: Int, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    GlassCardSegment(CardSegment.of(index, count), modifier.fillMaxWidth().testTag(RIVALS_CARD_SEGMENT_TAG)) {
        if (index > 0) RowSeparator()
        Box(Modifier.padding(top = if (index == 0) 4.dp else 0.dp, bottom = if (index == count - 1) 4.dp else 0.dp)) { content() }
    }
}

/**
 * A card-sized loading placeholder: the Material 3 indeterminate circular progress
 * indicator centred in a glass card.
 *
 * @param label Accessible description.
 * @param modifier Card modifier (for example a test tag).
 */
@Composable
fun RivalCardLoading(label: String, modifier: Modifier = Modifier) {
    GlassCard(modifier.fillMaxWidth().heightIn(min = 120.dp)) {
        Box(Modifier.fillMaxWidth().heightIn(min = 120.dp), contentAlignment = Alignment.Center) {
            FestivalLoading(label, size = 28.dp)
        }
    }
}

/**
 * A card-sized inline failure; siblings keep rendering.
 *
 * @param issue Classified failure.
 * @param title Fallback title.
 * @param countdown Automatic retry countdown.
 * @param onRetry Retry.
 */
@Composable
fun RivalCardFailure(issue: ServiceIssue, title: String, countdown: Int?, onRetry: () -> Unit) {
    GlassCard(Modifier.fillMaxWidth()) {
        ServiceStatusInline(issue, title, countdown, onRetry, Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
    }
}

// endregion

// region Empty and no-player states

/**
 * Centered full-page message: the shared [FestivalEmptyState] (web `EmptyState fullPage`, #377).
 *
 * @param title Heading.
 * @param subtitle Body.
 * @param tag Test tag.
 * @param action Optional gate button (Select Player).
 * @param actionLabel Button text.
 */
@Composable
fun RivalsMessage(title: String, subtitle: String?, tag: String, action: (() -> Unit)? = null, actionLabel: String? = null) {
    FestivalEmptyState(
        title,
        Modifier.fillMaxSize().testTag(tag),
        subtitle = subtitle,
        action = if (action != null && actionLabel != null) {
            { FilledTonalButton(onClick = action, modifier = Modifier.heightIn(min = 48.dp).testTag("$tag.action")) { Text(actionLabel) } }
        } else {
            null
        },
    )
}

// endregion

// region Song comparison row

/**
 * One shared song head to head as a bare row of its list's card (`rival-rows` R3, iOS
 * `RivalSongRowContent`, #558/#603): album art over the chart icon(s), the title, the artist and
 * the player's and rival's "#rank Name" pills (green for the side that leads, red for the side
 * behind, neutral when tied), then a delta badge with the rank gap. Place it in one [GlassCard]
 * with its siblings (Rival Detail categories) or a [GlassCardSegment] (Rivalry).
 *
 * @param song Comparison.
 * @param catalogSong Catalogue entry for the artist fallback and keys icon, if loaded.
 * @param artUrl Resolved artwork URL.
 * @param playerName Selected player's name.
 * @param rivalName Rival's name.
 * @param onClick Opens Song Detail; null draws a decorative, non-interactive row (First Run
 *   demos, issue #380) with the same look.
 * @param modifier Modifier.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun RivalSongRow(
    song: RivalSongComparison,
    catalogSong: Song?,
    artUrl: String?,
    playerName: String?,
    rivalName: String?,
    onClick: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val delta = song.rankDelta.toLong()
    val standing = RivalHeadToHead.standing(delta)
    val title = song.title ?: catalogSong?.title ?: song.songId
    val artist = song.artist ?: catalogSong?.artist.orEmpty()
    val you = playerName ?: "You"
    val them = rivalName ?: "Them"
    val description = RivalHeadToHead.songRowLabel(song, title, song.chart?.label, you, them)
    val keyboard = catalogSong?.usesKeyboardIcon == true
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .testTag("fst.rivals.song.${song.songId}.${song.instrument}")
            .clearAndSetSemantics {
                contentDescription = description
                if (onClick != null) {
                    role = Role.Button
                    onClick(label = "Open song") { onClick(); true }
                }
            }
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            AsyncImage(
                model = artUrl,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(RIVAL_SONG_ART).clip(RoundedCornerShape(8.dp)).background(BrandTokens.surfaceMuted),
            )
            val userChart = song.userChart
            val rivalChart = song.rivalChart
            if (userChart != null) {
                Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    InstrumentIcon(userChart, keyboard = keyboard, size = RIVAL_SONG_ICON, decorative = true)
                    if (rivalChart != null && rivalChart != userChart) InstrumentIcon(rivalChart, keyboard = keyboard, size = RIVAL_SONG_ICON, decorative = true)
                }
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            FestivalMarqueeText(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = BrandTokens.textPrimary)
            if (artist.isNotEmpty()) FestivalMarqueeText(artist, style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary)
            // One line when both fit, else one pill per line (iOS `ViewThatFits`).
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                RivalPill(RivalHeadToHead.standingPill(song.userRank, you), win = standing.playerWins)
                RivalPill(RivalHeadToHead.standingPill(song.rivalRank, them), win = standing.rivalWins)
            }
        }
        RivalDeltaBadge(delta, standing)
    }
}

/** Album art edge in a song row (`rival-rows` R4: the Songs list's 48 dp). */
private val RIVAL_SONG_ART = 48.dp

/** Chart icon edge under the art (iOS 22 pt). */
private val RIVAL_SONG_ICON = 22.dp

/**
 * The song row's trailing rank gap: an up arrow (you lead), down arrow (the rival leads) or "="
 * over the unsigned gap, coloured like the leader's pill. Decorative: the row's label speaks it.
 *
 * @param delta Signed rank delta.
 * @param standing Who leads.
 */
@Composable
private fun RivalDeltaBadge(delta: Long, standing: RivalSongStanding) {
    val color = when (standing.playerWins) {
        true -> RivalColors.winText
        false -> RivalColors.loseText
        null -> BrandTokens.textPrimary
    }
    Column(Modifier.widthIn(min = 28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        when (standing) {
            RivalSongStanding.PlayerAhead -> Icon(Icons.Filled.ArrowUpward, contentDescription = null, tint = color, modifier = Modifier.size(16.dp))
            RivalSongStanding.RivalAhead -> Icon(Icons.Filled.ArrowDownward, contentDescription = null, tint = color, modifier = Modifier.size(16.dp))
            RivalSongStanding.Tied -> Text("=", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold, color = color)
        }
        Text(RivalHeadToHead.deltaMagnitude(delta), style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold, color = color, maxLines = 1)
    }
}
/**
 * Category heading color by sentiment.
 *
 * @param sentiment Tone.
 * @return Text color.
 */
internal fun categoryColor(sentiment: RivalSentiment): Color = sentimentColor(sentiment)

// endregion
