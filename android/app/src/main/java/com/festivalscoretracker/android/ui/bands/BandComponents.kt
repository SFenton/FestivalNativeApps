package com.festivalscoretracker.android.ui.bands

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.FirstPage
import androidx.compose.material.icons.filled.LastPage
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.adaptive.currentWindowSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
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
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Layout

/** Widest single-column reading width for band pages. */
internal val BAND_CONTENT_MAX = 840.dp

/**
 * The first vertical fold/hinge from Jetpack WindowManager, in content coordinates.
 *
 * @param contentLeftPx Content box's leading edge in the window (px).
 * @param contentWidth Content width.
 * @return Hinge, or null when there is none or it sits too close to an edge.
 */
@Composable
internal fun rememberBandHinge(contentLeftPx: Float, contentWidth: Dp): BandLayout.Hinge? {
    val density = LocalDensity.current
    val hinge = currentWindowAdaptiveInfo().windowPosture.hingeList.firstOrNull { it.isVertical } ?: return null
    return with(density) {
        BandLayout.hingeInContent(
            hinge.bounds.left.toDp().value,
            hinge.bounds.right.toDp().value,
            contentLeftPx.toDp().value,
            contentWidth.value,
            hinge.isSeparating,
        )
    }
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
    FlowRow(modifier, horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        BandMember.distinct(members).forEach { member ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                member.chartedInstruments.forEach { InstrumentIcon(it, size = iconSize, decorative = true) }
                Text(
                    member.resolvedName,
                    style = MaterialTheme.typography.bodyMedium,
                    color = BrandTokens.textPrimary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
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
 * A player-band card: members with icons, band-size pill and appearances; the
 * whole card opens Band Detail (no chevron, per the glass-card rule).
 *
 * @param entry Wire row.
 * @param onClick Open action.
 * @param modifier Modifier.
 */
@Composable
internal fun PlayerBandCard(entry: PlayerBandEntry, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val size = BandType.fromWireId(entry.bandType)?.label ?: "Band"
    val appearances = BandFormatting.appearances(entry.appearanceCount)
    GlassCard(
        modifier
            .fillMaxWidth()
            .testTag("fst.player-bands.row.${entry.key}")
            .semantics(mergeDescendants = true) { contentDescription = "View band ${entry.membersLabel}, $size, $appearances" },
        onClick = onClick,
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            BandMemberChips(entry.members)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Pill(size)
                Text(appearances, style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary)
            }
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

/**
 * Material 3 single-choice segmented control (fixed short option sets: band
 * sizes, player-band groups, rank-by metrics).
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
    SingleChoiceSegmentedButtonRow(modifier.fillMaxWidth()) {
        options.forEachIndexed { index, option ->
            SegmentedButton(
                selected = option == selected,
                onClick = { onSelect(option) },
                shape = SegmentedButtonDefaults.itemShape(index, options.size),
                modifier = Modifier.heightIn(min = 48.dp).testTag(tag(option)),
                label = { Text(label(option), maxLines = 1, overflow = TextOverflow.Ellipsis) },
            )
        }
    }
}

// endregion

// region Pager

/**
 * First/Previous/`page / pages`/Next/Last paging, hidden for a single page.
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
    Row(
        modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = { onGo(1) }, enabled = page > 1, modifier = Modifier.testTag("$tagPrefix.page-first")) {
            Icon(Icons.Filled.FirstPage, contentDescription = "First page")
        }
        IconButton(onClick = { onGo(page - 1) }, enabled = page > 1, modifier = Modifier.testTag("$tagPrefix.page-previous")) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = "Previous page")
        }
        Text(
            "${BandFormatting.count(page.toLong())} / ${BandFormatting.count(pageCount.toLong())}",
            color = BrandTokens.textPrimary,
            modifier = Modifier
                .padding(horizontal = 12.dp)
                .testTag("$tagPrefix.page-info")
                .clearAndSetSemantics { contentDescription = "Page $page of $pageCount" },
        )
        IconButton(onClick = { onGo(page + 1) }, enabled = page < pageCount, modifier = Modifier.testTag("$tagPrefix.page-next")) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = "Next page")
        }
        IconButton(onClick = { onGo(pageCount) }, enabled = page < pageCount, modifier = Modifier.testTag("$tagPrefix.page-last")) {
            Icon(Icons.Filled.LastPage, contentDescription = "Last page")
        }
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
        Modifier.fillMaxWidth().padding(vertical = 32.dp, horizontal = 16.dp).testTag(tag),
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
