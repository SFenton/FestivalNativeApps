package com.festivalscoretracker.android.ui.bands

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.currentWindowSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick as onClickAction
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.bands.BandFormatting
import com.festivalscoretracker.android.core.bands.BandLayout
import com.festivalscoretracker.android.core.bands.BandMember
import com.festivalscoretracker.android.core.bands.BandType
import com.festivalscoretracker.android.core.bands.PlayerBandEntry
import com.festivalscoretracker.android.ui.common.FestivalMarqueeText
import com.festivalscoretracker.android.ui.common.isLargeText
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.design.RowChevron
import com.festivalscoretracker.android.ui.leaderboards.RankingsPager
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.common.shellPosture

// region Layout

/** Widest single-column reading width for band pages. */
internal val BAND_CONTENT_MAX = 840.dp

/**
 * The most central vertical fold/hinge from Jetpack WindowManager, in content coordinates.
 *
 * @param contentLeftPx Content box's leading edge in the window (px).
 * @param contentWidth Content width.
 * @return Hinge, or null when there is none or it sits too close to an edge.
 */
@Composable
internal fun rememberBandHinge(contentLeftPx: Float, contentWidth: Dp): BandLayout.Hinge? {
    val density = LocalDensity.current
    val hinges = shellPosture().hingeList.filter { it.isVertical }.mapNotNull { hinge ->
        with(density) {
            BandLayout.hingeInContent(
                hinge.bounds.left.toDp().value,
                hinge.bounds.right.toDp().value,
                contentLeftPx.toDp().value,
                contentWidth.value,
                hinge.isSeparating,
            )
        }
    }
    return BandLayout.central(hinges, contentWidth.value)
}

/**
 * A separating horizontal fold (tabletop posture) in content coordinates. [BandLayout.Hinge]'s
 * `left`/`right` hold the fold's top and bottom here.
 *
 * @param contentTopPx Content box's top edge in the window (px).
 * @param contentHeight Content height.
 * @return Hinge, or null when there is none or it leaves less than 200 dp above or below.
 */
@Composable
internal fun rememberBandTabletopHinge(contentTopPx: Float, contentHeight: Dp): BandLayout.Hinge? {
    val density = LocalDensity.current
    val hinges = shellPosture().hingeList.filter { !it.isVertical && it.isSeparating }.mapNotNull { hinge ->
        with(density) {
            BandLayout.hingeInContent(
                hinge.bounds.top.toDp().value,
                hinge.bounds.bottom.toDp().value,
                contentTopPx.toDp().value,
                contentHeight.value,
                separating = true,
            )
        }
    }
    return BandLayout.central(hinges, contentHeight.value)
}

/**
 * Current window width (window size class input, not the content width).
 *
 * @return Width in dp.
 */
@Composable
internal fun windowWidthDp(): Float = with(LocalDensity.current) { currentWindowSize().width.toDp().value }

/**
 * Center content at [BAND_CONTENT_MAX] on wide single-pane windows.
 *
 * @param modifier Modifier.
 * @param content Content.
 */
@Composable
internal fun BandReadableWidth(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
        Box(Modifier.widthIn(max = BAND_CONTENT_MAX).fillMaxWidth()) { content() }
    }
}

// endregion

// region Members

/**
 * Member names with their observed instrument icons, one entry per distinct member.
 *
 * @param members Band members.
 * @param modifier Modifier.
 * @param iconSize Icon size.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun BandMemberChips(members: List<BandMember>, modifier: Modifier = Modifier, iconSize: Dp = 20.dp) {
    val largeText = isLargeText()
    FlowRow(modifier, horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        BandMember.distinct(members).forEach { member ->
            val icons: @Composable () -> Unit = { member.chartedInstruments.forEach { InstrumentIcon(it, size = iconSize, decorative = true) } }
            val name: @Composable () -> Unit = {
                FestivalMarqueeText(member.resolvedName, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textPrimary)
            }
            if (largeText) {
                // 200% text in a narrow card: the name moves under its icons rather than breaking mid-word.
                FlowRow(horizontalArrangement = Arrangement.spacedBy(4.dp), itemVerticalAlignment = Alignment.CenterVertically) {
                    icons()
                    name()
                }
            } else {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    icons()
                    name()
                }
            }
        }
    }
}

/**
 * Spoken summary of a member: `Name, Lead, Bass`.
 *
 * @param member Member.
 * @return Announcement.
 */
internal fun memberAnnouncement(member: BandMember): String {
    val instruments = member.chartedInstruments.joinToString(", ") { it.label }.ifEmpty { "No observed instrument" }
    return "${member.resolvedName}, $instruments"
}

// endregion

// region Band card

/**
 * TalkBack announcement of a player-band card: `Members, Size, N appearances`.
 *
 * @param entry Wire row.
 * @return Announcement.
 */
internal fun playerBandAnnouncement(entry: PlayerBandEntry): String {
    val size = BandType.fromWireId(entry.bandType)?.label ?: "Band"
    return "${entry.membersLabel}, $size, ${BandFormatting.appearances(entry.appearanceCount)}"
}

/**
 * A player-band card: members with icons, band-size pill, appearances and the
 * operator's trailing chevron (batch 7.3); the whole card is one "Open band" button.
 *
 * Global search reuses it for band results (web `SearchModal` renders the same `PlayerBandCard`).
 *
 * @param entry Wire row.
 * @param onClick Open action.
 * @param modifier Modifier.
 * @param tag Test tag (player-bands rows by default).
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun PlayerBandCard(
    entry: PlayerBandEntry,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    tag: String = "fst.player-bands.row.${entry.key}",
) {
    val size = BandType.fromWireId(entry.bandType)?.label ?: "Band"
    val appearances = BandFormatting.appearances(entry.appearanceCount)
    val announcement = playerBandAnnouncement(entry)
    GlassCard(
        modifier
            .fillMaxWidth()
            .testTag(tag)
            .semantics(mergeDescendants = true) {
                contentDescription = announcement
                role = Role.Button
                onClickAction(label = "Open band") { onClick(); true }
            },
        onClick = onClick,
    ) {
        // The card's description is the announcement; the chips and texts would repeat it.
        Row(Modifier.padding(14.dp).clearAndSetSemantics { }, verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                BandMemberChips(entry.members)
                // Large text wraps the appearances under the pill instead of splitting "142 / appearances".
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                    itemVerticalAlignment = Alignment.CenterVertically,
                ) {
                    Pill(size)
                    Text(appearances, style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary)
                }
            }
            RowChevron(Modifier.padding(start = 8.dp))
        }
    }
}

/**
 * Small rounded label.
 *
 * @param text Label.
 * @param modifier Modifier.
 */
@Composable
internal fun Pill(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        style = MaterialTheme.typography.labelMedium,
        color = BrandTokens.textPrimary,
        modifier = modifier
            .background(BrandTokens.surfaceMuted, RoundedCornerShape(50))
            .padding(horizontal = 10.dp, vertical = 3.dp),
    )
}

// endregion

// region Selectors

/** Segment padding at large text: 4 dp sides (default 12 dp), 48 dp height kept by the button. */
internal val LARGE_TEXT_SEGMENT_PADDING = PaddingValues(horizontal = 4.dp)

/**
 * Material 3 single-choice segmented control (fixed short option sets: band
 * sizes, player-band groups, rank-by metrics). With large text the selected checkmark
 * and most of the side padding give way to the label, so four short labels still fit a
 * phone at 200% (selection stays visible as the filled secondary container).
 *
 * @param T Option type.
 * @param options Options in order.
 * @param selected Current option.
 * @param label Option label.
 * @param tag Test tag for an option.
 * @param onSelect Selection action.
 * @param modifier Modifier.
 */
@Composable
internal fun <T> BandSegmentedControl(
    options: List<T>,
    selected: T,
    label: (T) -> String,
    tag: (T) -> String,
    onSelect: (T) -> Unit,
    modifier: Modifier = Modifier,
) {
    val largeText = isLargeText()
    SingleChoiceSegmentedButtonRow(modifier.fillMaxWidth()) {
        options.forEachIndexed { index, option ->
            val isSelected = option == selected
            SegmentedButton(
                selected = isSelected,
                onClick = { onSelect(option) },
                shape = SegmentedButtonDefaults.itemShape(index, options.size),
                modifier = Modifier.heightIn(min = 48.dp).testTag(tag(option)),
                contentPadding = if (largeText) LARGE_TEXT_SEGMENT_PADDING else SegmentedButtonDefaults.ContentPadding,
                icon = { if (!largeText) SegmentedButtonDefaults.Icon(isSelected) },
                label = { Text(label(option), maxLines = 1, overflow = TextOverflow.Ellipsis) },
            )
        }
    }
}

// endregion

// region Pager

/**
 * The shared web pager (frosted « ‹ page / pages › » buttons, [RankingsPager]) centred
 * under a band list, hidden for a single page (7.4: one pager everywhere boards page).
 *
 * @param page Current page.
 * @param pageCount Pages.
 * @param tagPrefix Test-tag prefix (`fst.player-bands`).
 * @param onGo Load a page.
 * @param modifier Modifier.
 */
@Composable
internal fun BandPager(page: Int, pageCount: Int, tagPrefix: String, onGo: (Int) -> Unit, modifier: Modifier = Modifier) {
    if (pageCount <= 1) return
    Box(modifier.fillMaxWidth().padding(vertical = 8.dp), contentAlignment = Alignment.Center) {
        RankingsPager(page, pageCount, tagPrefix, onGo)
    }
}

// endregion

// region Text

/**
 * Page title + subtitle block; the title is announced as a heading.
 *
 * @param title Heading text, or null when the top app bar already shows it.
 * @param subtitle Secondary line.
 * @param tag Test-tag prefix.
 */
@Composable
internal fun BandPageHeader(title: String?, subtitle: String?, tag: String) {
    Column(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
        if (title != null) Text(
            title,
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            color = BrandTokens.textPrimary,
            modifier = Modifier.testTag("$tag.title").semantics { heading() },
        )
        if (!subtitle.isNullOrEmpty()) {
            Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textSecondary, modifier = Modifier.testTag("$tag.subtitle"))
        }
    }
}

/**
 * Centered empty-state text.
 *
 * @param title Title.
 * @param message Explanation.
 * @param tag Test tag.
 */
@Composable
internal fun BandEmptyState(title: String, message: String, tag: String) {
    Column(
        // One TalkBack stop for the title and its explanation.
        Modifier.fillMaxWidth().padding(vertical = 32.dp, horizontal = 16.dp).semantics(mergeDescendants = true) { }.testTag(tag),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(title, style = MaterialTheme.typography.titleMedium, color = BrandTokens.textPrimary)
        Text(message, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textSecondary)
    }
}

/**
 * A tappable text link with a 48 dp target.
 *
 * @param text Link text.
 * @param tag Test tag.
 * @param onClick Action.
 */
@Composable
internal fun BandTextLink(text: String, tag: String, onClick: () -> Unit) {
    Box(
        Modifier
            .heightIn(min = 48.dp)
            .clickable(role = Role.Button, onClick = onClick)
            .testTag(tag),
        contentAlignment = Alignment.CenterStart,
    ) {
        Text(text, style = MaterialTheme.typography.labelLarge, color = BrandTokens.accentBlue, fontWeight = FontWeight.SemiBold)
    }
}

// endregion
