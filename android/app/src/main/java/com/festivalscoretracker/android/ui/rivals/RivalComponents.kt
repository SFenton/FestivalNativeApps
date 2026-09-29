package com.festivalscoretracker.android.ui.rivals

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.FilledTonalButton
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
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.rivals.RivalDirection
import com.festivalscoretracker.android.core.rivals.RivalEntry
import com.festivalscoretracker.android.core.rivals.RivalHeadToHead
import com.festivalscoretracker.android.core.rivals.RivalSentiment
import com.festivalscoretracker.android.core.rivals.RivalSongComparison
import com.festivalscoretracker.android.core.rivals.RivalText
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.ui.common.FestivalLoading
import com.festivalscoretracker.android.ui.common.FestivalMarqueeText
import com.festivalscoretracker.android.ui.common.ServiceStatusInline
import com.festivalscoretracker.android.ui.common.fadeInStagger
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
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
 * Tinted count pill.
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
        null -> Triple(BrandTokens.textSecondary, RivalColors.neutralBackground, BrandTokens.glassBorder)
    }
    Text(
        text,
        style = MaterialTheme.typography.labelLarge,
        fontWeight = FontWeight.SemiBold,
        color = fg,
        maxLines = 1,
        modifier = modifier
            .clip(RoundedCornerShape(6.dp))
            .background(bg)
            .border(1.dp, border, RoundedCornerShape(6.dp))
            .padding(horizontal = 8.dp, vertical = 4.dp),
    )
}

// endregion

// region Rival row

/**
 * One rival (web `RivalRow`): tint bar (red when the rival is ahead), name, shared
 * songs and "songs ahead / songs behind" pills. Anonymous rows are not tappable.
 *
 * @param entry Row data and side.
 * @param onClick Opens Rival Detail; ignored for anonymous rows.
 * @param modifier Modifier.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun RivalRow(entry: RivalEntry, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val rival = entry.rival
    val winning = entry.direction == RivalDirection.Below
    val format = NumberFormat.getIntegerInstance()
    val ahead = "${format.format(rival.behindCount)} songs ahead"
    val behind = "${format.format(rival.aheadCount)} songs behind"
    val shared = RivalText.sharedSongs(rival.sharedSongCount)
    val description = "${rival.shownName}, ${if (winning) "you lead" else "ahead of you"}, $shared, $ahead, $behind"
    GlassCard(
        modifier = modifier
            .fillMaxWidth()
            .testTag(if (rival.isNavigable) "fst.rivals.row.${rival.accountId}" else "fst.rivals.row.anonymous")
            .clearAndSetSemantics {
                contentDescription = description
                if (rival.isNavigable) {
                    role = Role.Button
                    onClick(label = "Open rival") { onClick(); true }
                }
            },
        onClick = if (rival.isNavigable) onClick else null,
    ) {
        Row(Modifier.height(IntrinsicSize.Min)) {
            Box(Modifier.width(4.dp).fillMaxHeight().background(if (winning) BrandTokens.statusGreen else BrandTokens.statusRed))
            Column(Modifier.padding(horizontal = 14.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    FestivalMarqueeText(
                        rival.shownName,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = if (rival.isNavigable) BrandTokens.textPrimary else BrandTokens.textMuted,
                        modifier = Modifier.weight(1f, fill = false),
                    )
                    Text(shared, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textSecondary, maxLines = 1)
                }
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    RivalPill(ahead, win = true)
                    RivalPill(behind, win = false)
                }
            }
        }
    }
}

// endregion

// region Section card

/**
 * A titled group with a "See All" action (web section header card).
 *
 * @param title Title Case heading.
 * @param modifier Modifier.
 * @param instrument Leading chart icon.
 * @param description Secondary line.
 * @param titleColor Heading color (category sentiment).
 * @param onSeeAll "See All" action, or null to hide it.
 * @param seeAllTag Test tag for "See All".
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
        Column(Modifier.weight(1f)) {
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
            TextButton(
                onClick = onSeeAll,
                modifier = Modifier
                    .heightIn(min = 48.dp)
                    .let { if (seeAllTag != null) it.testTag(seeAllTag) else it }
                    .semantics { contentDescription = "${RivalText.SEE_ALL}: $title" },
            ) { Text(RivalText.SEE_ALL) }
        }
    }
}

/**
 * The hub's per-scope card body: loading, inline failure, or preview rows plus
 * "View all rivals".
 *
 * @param rows Preview rows.
 * @param onRival Row tap.
 * @param onViewAll "View all rivals".
 * @param viewAllLabel Button text.
 * @param revealed Whether the rows have finished loading ([festivalFadeIn]: web `nextStagger`).
 */
@Composable
fun RivalPreviewRows(
    rows: List<RivalEntry>,
    onRival: (RivalEntry) -> Unit,
    onViewAll: (() -> Unit)?,
    viewAllLabel: String = RivalText.VIEW_ALL_RIVALS,
    revealed: Boolean = true,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        rows.forEachIndexed { index, entry ->
            androidx.compose.runtime.key(entry.key(index)) {
                RivalRow(entry, onClick = { onRival(entry) }, modifier = Modifier.festivalFadeIn(revealed, fadeInStagger(index + 1)))
            }
        }
        if (onViewAll != null) {
            OutlinedButton(
                onClick = onViewAll,
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).festivalFadeIn(revealed, fadeInStagger(rows.size + 1)),
            ) { Text(viewAllLabel) }
        }
    }
}

/**
 * A card-sized loading placeholder.
 *
 * @param label Accessible description.
 */
@Composable
fun RivalCardLoading(label: String) {
    GlassCard(Modifier.fillMaxWidth().heightIn(min = 120.dp)) {
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
 * Centered full-page message (web `EmptyState fullPage`).
 *
 * @param title Heading.
 * @param subtitle Body.
 * @param tag Test tag.
 * @param action Optional button.
 * @param actionLabel Button text.
 */
@Composable
fun RivalsMessage(title: String, subtitle: String?, tag: String, action: (() -> Unit)? = null, actionLabel: String? = null) {
    Box(Modifier.fillMaxSize().padding(24.dp).testTag(tag), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.widthIn(max = 480.dp)) {
            Text(title, style = MaterialTheme.typography.titleLarge, color = BrandTokens.textPrimary, textAlign = TextAlign.Center, modifier = Modifier.semantics { heading() })
            if (subtitle != null) Text(subtitle, color = BrandTokens.textSecondary, textAlign = TextAlign.Center)
            if (action != null && actionLabel != null) {
                FilledTonalButton(onClick = action, modifier = Modifier.heightIn(min = 48.dp).testTag("$tag.action")) { Text(actionLabel) }
            }
        }
    }
}

// endregion

// region Song comparison row

/**
 * One shared song head to head (web `RivalSongRow`, standalone): art, title, artist ·
 * year and the chart icon(s), then You | rank & score gaps | Them. Tinted by the winner.
 *
 * @param song Comparison.
 * @param catalogSong Catalogue entry for year/art/keys icon, if loaded.
 * @param artUrl Resolved artwork URL.
 * @param playerName Selected player's name.
 * @param rivalName Rival's name.
 * @param onClick Opens Song Detail.
 * @param modifier Modifier.
 */
@Composable
fun RivalSongRow(
    song: RivalSongComparison,
    catalogSong: Song?,
    artUrl: String?,
    playerName: String?,
    rivalName: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val format = NumberFormat.getIntegerInstance()
    val delta = song.rankDelta
    val title = song.title ?: catalogSong?.title ?: song.songId
    val artist = song.artist ?: catalogSong?.artist.orEmpty()
    val year = catalogSong?.year
    val you = playerName ?: "You"
    val them = rivalName ?: "Them"
    val rankText = RivalHeadToHead.formatRankDelta(delta.toLong())
    val scoreText = RivalHeadToHead.formatScoreDiff(song)
    val scoreDiff = RivalHeadToHead.scoreDiff(song)
    val leader = when {
        delta > 0 -> "you lead by $rankText ranks"
        delta < 0 -> "$them leads by ${rankText.removePrefix("−")} ranks"
        else -> "tied"
    }
    val description = "$title, ${song.chart?.label.orEmpty()}, $you rank ${format.format(song.userRank)}, " +
        "$them rank ${format.format(song.rivalRank)}, $leader, score difference $scoreText"
    val keyboard = catalogSong?.usesKeyboardIcon == true
    GlassCard(
        modifier = modifier
            .fillMaxWidth()
            .testTag("fst.rivals.song.${song.songId}.${song.instrument}")
            .clearAndSetSemantics {
                contentDescription = description
                role = Role.Button
                onClick(label = "Open song") { onClick(); true }
            },
        onClick = onClick,
    ) {
        Row(Modifier.height(IntrinsicSize.Min)) {
            Box(
                Modifier.width(4.dp).fillMaxHeight().background(
                    when {
                        delta > 0 -> BrandTokens.statusGreen
                        delta < 0 -> BrandTokens.statusRed
                        else -> Color.Transparent
                    },
                ),
            )
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    AsyncImage(
                        model = artUrl,
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.size(48.dp).clip(RoundedCornerShape(8.dp)).background(BrandTokens.surfaceMuted),
                    )
                    Column(Modifier.weight(1f)) {
                        FestivalMarqueeText(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = BrandTokens.textPrimary)
                        FestivalMarqueeText(
                            listOfNotNull(artist.takeIf { it.isNotEmpty() }, year?.toString()).joinToString(" · "),
                            style = MaterialTheme.typography.bodyMedium,
                            color = BrandTokens.textSecondary,
                        )
                    }
                    val userChart = song.userChart
                    val rivalChart = song.rivalChart
                    if (userChart != null && rivalChart != null && userChart != rivalChart) {
                        Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                            InstrumentIcon(userChart, keyboard = keyboard, size = 28.dp, decorative = true)
                            InstrumentIcon(rivalChart, keyboard = keyboard, size = 28.dp, decorative = true)
                        }
                    } else if (userChart != null) {
                        InstrumentIcon(userChart, keyboard = keyboard, size = 36.dp, decorative = true)
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    CompareEntry(you, song.userRank, song.userScore, win = delta > 0, alignEnd = false, modifier = Modifier.weight(1f))
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        RivalPill(rankText, win = if (delta == 0) null else delta > 0)
                        RivalPill(scoreText, win = if (scoreDiff == 0L) null else scoreDiff > 0)
                    }
                    CompareEntry(them, song.rivalRank, song.rivalScore, win = delta < 0, alignEnd = true, modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun CompareEntry(name: String, rank: Int, score: Long?, win: Boolean, alignEnd: Boolean, modifier: Modifier) {
    val format = NumberFormat.getIntegerInstance()
    Column(modifier, horizontalAlignment = if (alignEnd) Alignment.End else Alignment.Start) {
        FestivalMarqueeText(name, style = MaterialTheme.typography.labelMedium, color = BrandTokens.textSecondary)
        Text(
            "#${format.format(rank)}",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = if (win) FontWeight.Bold else FontWeight.Medium,
            color = if (win) BrandTokens.textPrimary else BrandTokens.textSecondary,
        )
        if (score != null) Text(format.format(score), style = MaterialTheme.typography.bodySmall, color = BrandTokens.textPrimary)
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
