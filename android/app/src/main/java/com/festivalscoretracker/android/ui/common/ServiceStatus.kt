package com.festivalscoretracker.android.ui.common

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.outlined.HourglassTop
import androidx.compose.material.icons.outlined.SearchOff
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material.icons.outlined.WifiOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.foundation.layout.absolutePadding
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.isSpecified
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility

// region Formatting

/**
 * Countdown as `m:ss`.
 *
 * @param seconds Remaining seconds.
 * @return Formatted text.
 */
fun formatCountdown(seconds: Int): String = "${seconds / 60}:${(seconds % 60).toString().padStart(2, '0')}"

/**
 * Spoken countdown label (spec: "Trying again automatically in N seconds"), shared by the
 * full page and inline rows so screen readers never hear the `m:ss` clock.
 *
 * @param seconds Remaining seconds.
 * @return Accessible label.
 */
fun countdownLabel(seconds: Int): String = "Trying again automatically in $seconds seconds"

// endregion

// region Presentation rules

/** Font scale at which an inline row stacks Retry under its text instead of beside it. */
const val INLINE_STACK_FONT_SCALE = 1.5f

/**
 * Decorative icon for an issue; mirrors the iOS symbol set (sync, cloud alert, hourglass,
 * search miss, Wi-Fi off, warning).
 *
 * @param issue Classified failure.
 * @return Material outlined icon.
 */
fun serviceStatusIcon(issue: ServiceIssue): ImageVector = when (issue) {
    is ServiceIssue.ScrapeInProgress -> Icons.Outlined.Sync
    is ServiceIssue.Unavailable -> Icons.Outlined.CloudOff
    ServiceIssue.Syncing -> Icons.Outlined.HourglassTop
    ServiceIssue.NotFound -> Icons.Outlined.SearchOff
    ServiceIssue.Offline -> Icons.Outlined.WifiOff
    is ServiceIssue.Other -> Icons.Outlined.WarningAmber
}

/**
 * Icon tint: gold while the page retries by itself (matching the gold countdown), primary text otherwise.
 *
 * @param issue Classified failure.
 * @return Tint color.
 */
fun serviceStatusIconTint(issue: ServiceIssue): Color = if (issue.retriesAutomatically) BrandTokens.gold else BrandTokens.textPrimary

/**
 * Whether the full-page icon pulses: only while retrying automatically and never under
 * Reduce Motion (system animator scale 0 or the in-app toggle).
 *
 * @param issue Classified failure.
 * @param reduceMotion Effective reduce-motion preference.
 * @return True to pulse.
 */
fun serviceStatusPulses(issue: ServiceIssue, reduceMotion: Boolean): Boolean = issue.retriesAutomatically && !reduceMotion

/**
 * Whether an inline row stacks Retry under its text: beside it at 200% type, a phone-width
 * card left the heading a word or two per line.
 *
 * @param fontScale System font scale.
 * @return True to stack.
 */
fun inlineStacks(fontScale: Float): Boolean = fontScale >= INLINE_STACK_FONT_SCALE

/** Viewport height below which the full page drops its decorative icon (phone landscape is ~220 dp). */
val COMPACT_STATUS_HEIGHT = 320.dp

/**
 * Whether the full page is in a short viewport, where the icon would push Retry below the fold.
 *
 * @param height Viewport height inside the shell's padding.
 * @return True for the compact layout.
 */
fun isCompactStatusHeight(height: Dp): Boolean = height < COMPACT_STATUS_HEIGHT

/**
 * Absolute padding (px) around the full page.
 *
 * @property left Left padding.
 * @property top Top padding.
 * @property right Right padding.
 * @property bottom Bottom padding.
 */
data class HingeSide(val left: Float = 0f, val top: Float = 0f, val right: Float = 0f, val bottom: Float = 0f)

/**
 * Padding along one axis that confines a page of [size] to one side of a hinge spanning
 * [hingeStart]…[hingeEnd] (page coordinates): the larger side, or [preferEnd]'s side on a tie.
 *
 * @param size Page extent on this axis.
 * @param hingeStart Hinge's near edge.
 * @param hingeEnd Hinge's far edge.
 * @param preferEnd Tie-break toward the end (trailing / lower) side.
 * @return (start padding, end padding); zeros when the hinge misses the page.
 */
fun hingeSidePadding(size: Float, hingeStart: Float, hingeEnd: Float, preferEnd: Boolean): Pair<Float, Float> {
    if (size <= 0f || hingeEnd <= 0f || hingeStart >= size) return 0f to 0f
    val before = hingeStart.coerceAtLeast(0f)
    val after = (size - hingeEnd).coerceAtLeast(0f)
    val useEnd = if (before == after) preferEnd else after > before
    return if (useEnd) hingeEnd.coerceAtMost(size) to 0f else 0f to (size - before)
}

// endregion

// region Full page

/**
 * Full-page failed-read state (`.agents/controls/service-status/spec.md`).
 *
 * @param issue Classified failure.
 * @param fallbackTitle Screen's own "… unavailable" title.
 * @param countdown Seconds until the automatic retry, for a scrape freeze.
 * @param onRetry Retry action.
 * @param modifier Modifier.
 * @param contentPadding Padding to clear shell chrome.
 */
@Composable
fun ServiceStatusView(
    issue: ServiceIssue,
    fallbackTitle: String,
    countdown: Int?,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
    contentPadding: PaddingValues = PaddingValues(),
) {
    var origin by remember { mutableStateOf(Offset.Unspecified) }
    BoxWithConstraints(modifier.fillMaxSize().padding(contentPadding).onGloballyPositioned { origin = it.positionInWindow() }) {
        val side = rememberHingeSide(origin, constraints.maxWidth.toFloat(), constraints.maxHeight.toFloat())
        val density = LocalDensity.current
        val compact = isCompactStatusHeight(maxHeight - with(density) { (side.top + side.bottom).toDp() })
        Box(
            Modifier
                .fillMaxSize()
                .then(with(density) { Modifier.absolutePadding(side.left.toDp(), side.top.toDp(), side.right.toDp(), side.bottom.toDp()) })
                .verticalScroll(rememberScrollState())
                .padding(if (compact) 16.dp else 24.dp),
            contentAlignment = Alignment.Center,
        ) {
            ServiceStatusContent(issue, fallbackTitle, countdown, onRetry, compact)
        }
    }
}

/**
 * Padding (px) that keeps the full page on one side of the window's separating hinge, if it
 * crosses this page: Material 3 "Never place interactive content or critical information across
 * the hinge area". Book posture uses the wider side (leading on a tie), tabletop the lower half,
 * matching [festivalSheetHingeSide].
 *
 * @param origin Page's top-left in the window, or unspecified before the first layout.
 * @param width Page width (px).
 * @param height Page height (px).
 * @return Side padding.
 */
@Composable
private fun rememberHingeSide(origin: Offset, width: Float, height: Float): HingeSide {
    if (!origin.isSpecified) return HingeSide()
    val posture = LocalShellPosture.current ?: currentWindowAdaptiveInfo().windowPosture
    val hinge = posture.hingeList.firstOrNull { it.isSeparating } ?: return HingeSide()
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    return if (hinge.isVertical) {
        val (before, after) = hingeSidePadding(width, hinge.bounds.left - origin.x, hinge.bounds.right - origin.x, preferEnd = rtl)
        HingeSide(left = before, right = after)
    } else {
        val (before, after) = hingeSidePadding(height, hinge.bounds.top - origin.y, hinge.bounds.bottom - origin.y, preferEnd = true)
        HingeSide(top = before, bottom = after)
    }
}

/**
 * The full page's column: icon (unless [compact]), heading, message, countdown and Retry.
 *
 * @param issue Classified failure.
 * @param fallbackTitle Screen's own "… unavailable" title.
 * @param countdown Seconds until the automatic retry.
 * @param onRetry Retry action.
 * @param compact Short viewport: drop the decorative icon and tighten spacing.
 */
@Composable
private fun ServiceStatusContent(issue: ServiceIssue, fallbackTitle: String, countdown: Int?, onRetry: () -> Unit, compact: Boolean) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(if (compact) 8.dp else 12.dp),
        modifier = Modifier.semantics(mergeDescendants = false) { liveRegion = LiveRegionMode.Polite },
    ) {
        if (!compact) ServiceStatusIcon(issue)
        Text(
            issue.title ?: fallbackTitle,
            style = MaterialTheme.typography.titleLarge,
            color = BrandTokens.textPrimary,
            textAlign = TextAlign.Center,
            modifier = Modifier.testTag("fst.service-status.title").semantics { heading() },
        )
        Text(issue.message, color = BrandTokens.textSecondary, textAlign = TextAlign.Center)
        if (countdown != null) {
            Text(
                "Trying again in ${formatCountdown(countdown)}",
                style = MaterialTheme.typography.labelLarge,
                color = BrandTokens.gold,
                modifier = Modifier
                    .testTag("fst.service-status.countdown")
                    .semantics { contentDescription = countdownLabel(countdown) },
            )
        }
        FilledTonalButton(onClick = onRetry, modifier = Modifier.heightIn(min = 48.dp).testTag("fst.service-status.retry")) {
            Text(if (countdown != null) "Retry Now" else "Retry")
        }
    }
}

/**
 * Decorative 40 dp issue icon; pulses (alpha 1 → 0.4, 1 s, reversing) while the page retries
 * automatically unless Reduce Motion is on.
 *
 * @param issue Classified failure.
 */
@Composable
private fun ServiceStatusIcon(issue: ServiceIssue) {
    val iconModifier = if (serviceStatusPulses(issue, LocalFestivalAccessibility.current.reduceMotion)) {
        val alpha = rememberInfiniteTransition(label = "service-status-pulse").animateFloat(
            initialValue = 1f,
            targetValue = 0.4f,
            animationSpec = infiniteRepeatable(tween(durationMillis = 1000), RepeatMode.Reverse),
            label = "service-status-pulse-alpha",
        )
        Modifier.graphicsLayer { this.alpha = alpha.value }
    } else {
        Modifier
    }
    Icon(serviceStatusIcon(issue), contentDescription = null, tint = serviceStatusIconTint(issue), modifier = iconModifier.size(40.dp))
}

// endregion

// region Inline

/**
 * Compact inline status for one section; siblings keep rendering. Silent to
 * screen readers beyond its own text (no live region) so failing sections don't flood.
 *
 * @param issue Classified failure.
 * @param fallbackTitle Section's own "… unavailable" title.
 * @param countdown Seconds until automatic retry.
 * @param onRetry Retry action.
 * @param modifier Modifier.
 * @param retryTag Optional Retry button test tag.
 */
@Composable
fun ServiceStatusInline(issue: ServiceIssue, fallbackTitle: String, countdown: Int?, onRetry: () -> Unit, modifier: Modifier = Modifier, retryTag: String? = null) {
    val text: @Composable () -> Unit = {
        Text(issue.title ?: fallbackTitle, style = MaterialTheme.typography.labelLarge, color = BrandTokens.textPrimary)
        if (countdown != null) {
            Text(
                "Trying again in ${formatCountdown(countdown)}",
                style = MaterialTheme.typography.bodySmall,
                color = BrandTokens.textSecondary,
                modifier = Modifier.semantics { contentDescription = countdownLabel(countdown) },
            )
        } else {
            Text(issue.message, style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary)
        }
    }
    val retry: @Composable () -> Unit = {
        TextButton(onClick = onRetry, modifier = Modifier.heightIn(min = 48.dp).then(if (retryTag != null) Modifier.testTag(retryTag) else Modifier)) {
            Text(if (countdown != null) "Retry Now" else "Retry")
        }
    }
    if (inlineStacks(LocalDensity.current.fontScale)) {
        Column(modifier.fillMaxWidth().testTag("fst.service-status.inline")) {
            text()
            retry()
        }
    } else {
        Row(
            modifier.fillMaxWidth().testTag("fst.service-status.inline"),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Column(Modifier.weight(1f)) { text() }
            retry()
        }
    }
}

/**
 * Centered loading indicator ([FestivalLoading]); no visible caption.
 *
 * @param label Accessible description.
 * @param modifier Modifier.
 */
@Composable
fun LoadingView(label: String, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        FestivalLoading(label)
    }
}

/**
 * The app's one loading indicator (cross-platform standard, 2026-09-28): a white indeterminate
 * arc on a 10% white track (web `ArcSpinner` track), 36 dp with a 3 dp stroke by default, never
 * the theme's blue primary and never with a subtitle.
 *
 * @param label Accessible description, or null when a parent already announces the state.
 * @param modifier Modifier.
 * @param size Diameter (web `Spinner` SM 24 / MD 36 / LG 48).
 */
@Composable
fun FestivalLoading(label: String?, modifier: Modifier = Modifier, size: Dp = 36.dp) {
    CircularProgressIndicator(
        modifier = modifier
            .size(size)
            .then(if (label != null) Modifier.semantics { contentDescription = label } else Modifier),
        color = BrandTokens.textPrimary,
        trackColor = BrandTokens.textPrimary.copy(alpha = 0.1f),
        strokeWidth = if (size >= 48.dp) 4.dp else 3.dp,
    )
}

// endregion
