package com.festivalscoretracker.android.ui.common

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
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

// region Formatting

/**
 * Countdown as `m:ss`.
 *
 * @param seconds Remaining seconds.
 * @return Formatted text.
 */
fun formatCountdown(seconds: Int): String = "${seconds / 60}:${(seconds % 60).toString().padStart(2, '0')}"

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
    Box(
        modifier
            .fillMaxSize()
            .padding(contentPadding)
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.semantics(mergeDescendants = false) { liveRegion = LiveRegionMode.Polite },
        ) {
            Icon(
                if (issue is ServiceIssue.ScrapeInProgress) Icons.Outlined.HourglassTop else Icons.Outlined.CloudOff,
                contentDescription = null,
                tint = BrandTokens.textSecondary,
            )
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
                        .semantics { contentDescription = "Trying again automatically in $countdown seconds" },
                )
            }
            FilledTonalButton(onClick = onRetry, modifier = Modifier.heightIn(min = 48.dp).testTag("fst.service-status.retry")) {
                Text(if (countdown != null) "Retry Now" else "Retry")
            }
        }
    }
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
    Row(
        modifier.fillMaxWidth().testTag("fst.service-status.inline"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Column(Modifier.weight(1f)) {
            Text(issue.title ?: fallbackTitle, style = MaterialTheme.typography.labelLarge, color = BrandTokens.textPrimary)
            Text(
                if (countdown != null) "Trying again in ${formatCountdown(countdown)}" else issue.message,
                style = MaterialTheme.typography.bodySmall,
                color = BrandTokens.textSecondary,
            )
        }
        TextButton(onClick = onRetry, modifier = Modifier.heightIn(min = 48.dp).then(if (retryTag != null) Modifier.testTag(retryTag) else Modifier)) {
            Text(if (countdown != null) "Retry Now" else "Retry")
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
