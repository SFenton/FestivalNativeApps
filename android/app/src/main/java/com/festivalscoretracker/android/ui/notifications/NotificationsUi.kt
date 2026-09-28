package com.festivalscoretracker.android.ui.notifications

import com.festivalscoretracker.android.ui.design.popupTestTags
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.FullRankingsRoute
import com.festivalscoretracker.android.core.nav.LeaderboardsRoute
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import com.festivalscoretracker.android.core.notifications.NotificationDestination
import com.festivalscoretracker.android.presentation.notifications.NotificationRow
import com.festivalscoretracker.android.presentation.notifications.NotificationsState
import com.festivalscoretracker.android.presentation.notifications.NotificationsViewModel
import com.festivalscoretracker.android.ui.common.ServiceStatusInline
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Routing

/**
 * The app route for a notification destination: Song Detail, full rankings
 * for one instrument, or the Leaderboards hub.
 *
 * @param destination Destination.
 * @return Route.
 */
fun NotificationDestination.route(): AppRoute = when (this) {
    is NotificationDestination.Song -> SongDetailRoute(songId)
    is NotificationDestination.Rankings -> instrument?.let { FullRankingsRoute(it.wireId, rankBy) } ?: LeaderboardsRoute
}

// endregion

// region Bell

/**
 * Top-app-bar bell with an unread badge (99+), placed before the profile avatar.
 *
 * @param viewModel Notifications state.
 * @param onOpen Opens the sheet.
 */
@Composable
fun NotificationsBell(viewModel: NotificationsViewModel, onOpen: () -> Unit) {
    val unread by viewModel.unreadCount.collectAsStateWithLifecycle()
    IconButton(
        onClick = onOpen,
        modifier = Modifier.testTag("fst.shell.notifications").semantics { contentDescription = NotificationsViewModel.bellLabel(unread) },
    ) {
        BadgedBox(badge = { if (unread > 0) Badge(containerColor = BrandTokens.gold, contentColor = BrandTokens.cardBackground) { Text(NotificationsViewModel.badgeText(unread)) } }) {
            Icon(Icons.Outlined.Notifications, contentDescription = null)
        }
    }
}

// endregion

// region Sheet

/**
 * Notifications modal bottom sheet (M3 sheets are width-capped on large
 * windows). Refreshes on open; closing marks every loaded row seen. Tapping a
 * row with a destination marks it seen, closes the sheet and navigates.
 *
 * @param viewModel Notifications state.
 * @param onDismiss Sheet closed.
 * @param onNavigate Navigate to a route on the current tab.
 * @param onChooseProfile Opens profile selection (no-player state).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NotificationsSheet(viewModel: NotificationsViewModel, onDismiss: () -> Unit, onNavigate: (AppRoute) -> Unit, onChooseProfile: () -> Unit) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val close = {
        viewModel.markAllSeen()
        onDismiss()
    }
    androidx.compose.runtime.LaunchedEffect(Unit) { viewModel.refresh() }
    ModalBottomSheet(
        onDismissRequest = close,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = BrandTokens.cardBackground,
        modifier = Modifier.popupTestTags().testTag("fst.notifications.sheet").semantics { paneTitle = "Notifications" },
    ) {
        Text(
            "Notifications",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
            color = BrandTokens.textPrimary,
            modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp).semantics { heading() },
        )
        when (val current = state) {
            NotificationsState.NoPlayer -> Message(
                "Select a player profile to see notifications about new high scores and rank changes.", "fst.notifications.no-player",
            ) { Button(onClick = { onDismiss(); onChooseProfile() }) { Text("Select Player Profile") } }
            NotificationsState.Loading -> Box(Modifier.fillMaxWidth().padding(48.dp), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(Modifier.testTag("fst.notifications.loading"))
            }
            is NotificationsState.Failed -> ServiceStatusInline(
                current.issue, "Notifications unavailable", null, viewModel::refresh, Modifier.padding(16.dp).testTag("fst.notifications.failed"),
            )
            is NotificationsState.Empty -> Message(current.body, "fst.notifications.empty", title = "No notifications available")
            is NotificationsState.Loaded -> LazyColumn(Modifier.fillMaxWidth().testTag("fst.notifications.list"), contentPadding = PaddingValues(bottom = 24.dp)) {
                if (current.newRows.isNotEmpty()) {
                    item(key = "new") { SectionTitle("New") }
                    items(current.newRows, key = { it.id }) { row -> NotificationItem(row) { activate(viewModel, row, onDismiss, onNavigate) } }
                }
                if (current.olderRows.isNotEmpty()) {
                    item(key = "older") { SectionTitle("Older") }
                    items(current.olderRows, key = { it.id }) { row -> NotificationItem(row) { activate(viewModel, row, onDismiss, onNavigate) } }
                }
            }
        }
    }
}

private fun activate(viewModel: NotificationsViewModel, row: NotificationRow, onDismiss: () -> Unit, onNavigate: (AppRoute) -> Unit) {
    val destination = viewModel.activate(row) ?: return
    viewModel.markAllSeen()
    onDismiss()
    onNavigate(destination.route())
}

@Composable
private fun SectionTitle(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.Bold,
        color = BrandTokens.textSecondary,
        modifier = Modifier.padding(start = 24.dp, top = 12.dp, bottom = 4.dp).semantics { heading() },
    )
}

@Composable
private fun NotificationItem(row: NotificationRow, onClick: () -> Unit) {
    val presentation = row.presentation
    val navigable = presentation.destination != null
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 64.dp)
            .clickable(enabled = true, onClick = onClick)
            .padding(horizontal = 24.dp, vertical = 10.dp)
            .testTag("fst.notifications.row.${row.id}")
            .clearAndSetSemantics {
                contentDescription = row.accessibleText
                if (navigable) role = Role.Button
            },
    ) {
        Box(Modifier.size(10.dp).background(if (row.unread) BrandTokens.gold else androidx.compose.ui.graphics.Color.Transparent, CircleShape))
        Column(Modifier.weight(1f).padding(start = 12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(presentation.title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary, modifier = Modifier.weight(1f))
                Text(row.timeText, style = MaterialTheme.typography.labelSmall, color = BrandTokens.textMuted, modifier = Modifier.padding(start = 8.dp))
            }
            Text(presentation.message, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textSecondary)
            presentation.flag?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.labelSmall,
                    color = BrandTokens.textPrimary,
                    modifier = Modifier.padding(top = 2.dp).background(BrandTokens.accentPurple.copy(alpha = 0.5f), RoundedCornerShape(6.dp)).padding(horizontal = 8.dp, vertical = 2.dp),
                )
            }
        }
        if (navigable) Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = BrandTokens.textSecondary)
    }
}

@Composable
private fun Message(body: String, tag: String, title: String? = null, action: (@Composable () -> Unit)? = null) {
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 32.dp).testTag(tag),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (title != null) Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary, textAlign = TextAlign.Center)
        Text(body, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textSecondary, textAlign = TextAlign.Center)
        action?.invoke()
    }
}

// endregion
