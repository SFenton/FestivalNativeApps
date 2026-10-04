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
    BoxWithConstraints(modifier.fillMaxSize().padding(contentPadding)) {
        val compact = isCompactStatusHeight(maxHeight)
        Box(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(if (compact) 16.dp else 24.dp),
            contentAlignment = Alignment.Center,
        ) {
            ServiceStatusContent(issue, fallbackTitle, countdown, onRetry, compact)
        }
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
