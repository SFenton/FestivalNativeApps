package com.festivalscoretracker.android.ui.settings

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import com.festivalscoretracker.android.core.serviceinfo.ServiceInfoRows
import com.festivalscoretracker.android.core.serviceinfo.ServiceInfoText
import com.festivalscoretracker.android.core.serviceinfo.ServiceProcessState
import com.festivalscoretracker.android.presentation.settings.ServiceInfoPoller
import com.festivalscoretracker.android.ui.common.FestivalLoading
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility

// region Section

/**
 * Settings "Service Info" card (web `SettingsServiceProgressCard`, Apple
 * `SettingsServiceInfoSection`): live leaderboard update state with the process state and a
 * spinner, the current phase with its progress bar, a public-read freeze notice, and the last
 * successful publication. Loading and failure show only the state row, like the web.
 *
 * Polls the keyless operational `/api/service-info` every 5 s only while this section is
 * composed **and** the app is at least STARTED (`repeatOnLifecycle`), so leaving Settings or
 * backgrounding the app stops the requests.
 *
 * @param poller Poller owned by the Settings view model.
 */
@Composable
internal fun ServiceInfoSection(poller: ServiceInfoPoller) {
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(poller, lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) { poller.poll() }
    }
    val phase by poller.phase.collectAsStateWithLifecycle()
    val rows = remember(phase) { ServiceInfoRows.make(phase) }
    // Same header treatment as the other Settings sections.
    Text(
        ServiceInfoText.TITLE,
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.Bold,
        color = BrandTokens.textPrimary,
        modifier = Modifier.semantics { heading() },
    )
    Text(ServiceInfoText.HINT, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textSecondary, modifier = Modifier.padding(top = 4.dp, bottom = 8.dp))
    GlassCard(Modifier.fillMaxWidth().testTag("fst.settings.service-info")) {
        // Live summary: TalkBack hears state changes politely, like the web's aria-live block.
        Column(Modifier.semantics { liveRegion = LiveRegionMode.Polite }) {
            StateRow(rows)
            rows.phaseTitle?.let { title ->
                HorizontalDivider(color = BrandTokens.glassBorder)
                PhaseRow(title, rows)
            }
        }
        rows.freezeNotice?.let { notice ->
            HorizontalDivider(color = BrandTokens.glassBorder)
            InfoRow(ServiceInfoText.FREEZE_TITLE, notice, "fst.settings.service-info.freeze")
        }
        rows.lastPublished?.let { published ->
            HorizontalDivider(color = BrandTokens.glassBorder)
            InfoRow(ServiceInfoText.LAST_PUBLISHED_TITLE, published, "fst.settings.service-info.last-published")
        }
    }
}

// endregion

// region Rows

@Composable
private fun StateRow(rows: ServiceInfoRows) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .testTag("fst.settings.service-info.state")
            .semantics(mergeDescendants = true) {},
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(ServiceInfoText.SERVICE_STATE_TITLE, color = BrandTokens.textPrimary, style = MaterialTheme.typography.bodyLarge)
            Text(rows.stateDescription, color = BrandTokens.textSecondary, style = MaterialTheme.typography.bodyMedium)
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                rows.processState.label,
                color = BrandTokens.textPrimary,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.testTag("fst.settings.service-info.process"),
            )
            if (rows.processState == ServiceProcessState.Loading || rows.processState == ServiceProcessState.Updating) {
                FestivalLoading(null, Modifier.clearAndSetSemantics { }, size = 20.dp)
            }
        }
    }
}

@Composable
private fun PhaseRow(title: String, rows: ServiceInfoRows) {
    val spoken = listOfNotNull(rows.progressText, rows.unitsText).joinToString(". ")
    Column(
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp)
            .testTag("fst.settings.service-info.phase")
            .clearAndSetSemantics {
                contentDescription = title
                if (spoken.isNotEmpty()) stateDescription = spoken
                rows.barPercent?.let { progressBarRangeInfo = ProgressBarRangeInfo((it / 100).toFloat(), 0f..1f) }
            },
    ) {
        Text(title, color = BrandTokens.textPrimary, style = MaterialTheme.typography.bodyLarge)
        if (rows.showBar) {
            ProgressBar(rows.barPercent)
            rows.progressText?.let { Caption(it) }
            rows.unitsText?.let { Caption(it) }
        }
    }
}

/**
 * Web-style capsule bar: purple fill on a muted track. An unknown total shows Material's
 * indeterminate sweep (the web's looping shimmer), or the still empty track under reduced motion.
 */
@Composable
private fun ProgressBar(percent: Double?) {
    val reduceMotion = LocalFestivalAccessibility.current.reduceMotion
    val modifier = Modifier.fillMaxWidth().height(8.dp).testTag("fst.settings.service-info.bar")
    when {
        percent != null -> {
            val shown by animateFloatAsState((percent / 100).toFloat(), if (reduceMotion) tween(0) else tween(180), label = "service-progress")
            LinearProgressIndicator(
                progress = { shown },
                modifier = modifier,
                color = BrandTokens.accentPurple,
                trackColor = BrandTokens.surfaceMuted,
                strokeCap = StrokeCap.Round,
                gapSize = 0.dp,
                drawStopIndicator = {},
            )
        }
        reduceMotion -> Box(modifier.background(BrandTokens.surfaceMuted, CircleShape))
        else -> LinearProgressIndicator(
            modifier = modifier,
            color = BrandTokens.accentPurple,
            trackColor = BrandTokens.surfaceMuted,
            strokeCap = StrokeCap.Round,
            gapSize = 0.dp,
        )
    }
}

@Composable
private fun Caption(text: String) {
    Text(text, color = BrandTokens.textSecondary, style = MaterialTheme.typography.bodySmall)
}

@Composable
private fun InfoRow(title: String, detail: String, tag: String) {
    Column(
        verticalArrangement = Arrangement.spacedBy(4.dp),
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .testTag(tag)
            .semantics(mergeDescendants = true) {},
    ) {
        Text(title, color = BrandTokens.textPrimary, style = MaterialTheme.typography.bodyLarge)
        Text(detail, color = BrandTokens.textSecondary, style = MaterialTheme.typography.bodyMedium)
    }
}

// endregion
