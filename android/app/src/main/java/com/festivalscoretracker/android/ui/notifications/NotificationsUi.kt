package com.festivalscoretracker.android.ui.notifications

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.NotificationsOff
import androidx.compose.material3.Badge
import androidx.compose.material3.Button
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsPropertyKey
import androidx.compose.ui.semantics.SemanticsPropertyReceiver
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImage
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.FullRankingsRoute
import com.festivalscoretracker.android.core.nav.LeaderboardsRoute
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import com.festivalscoretracker.android.core.notifications.NotificationDestination
import com.festivalscoretracker.android.core.notifications.NotificationFlagKind
import com.festivalscoretracker.android.core.notifications.NotificationMedia
import com.festivalscoretracker.android.core.notifications.NotificationMessagePart
import com.festivalscoretracker.android.presentation.notifications.NotificationRow
import com.festivalscoretracker.android.presentation.notifications.NotificationsState
import com.festivalscoretracker.android.presentation.notifications.NotificationsViewModel
import com.festivalscoretracker.android.ui.common.FestivalLoading
import com.festivalscoretracker.android.ui.common.FestivalMarqueeText
import com.festivalscoretracker.android.ui.common.ServiceStatusInline
import com.festivalscoretracker.android.ui.common.fadeInStagger
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import com.festivalscoretracker.android.ui.common.festivalSheetTop
import com.festivalscoretracker.android.ui.common.rememberRevealed
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.design.popupTestTags
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
    // The badge is a sibling of the button, not inside it: IconButton clips its content to
    // its circular state layer, which cut a two-digit badge off at the top (batch 6.23).
    Box {
        IconButton(
            onClick = onOpen,
            modifier = Modifier.testTag("fst.shell.notifications").semantics { contentDescription = NotificationsViewModel.bellLabel(unread) },
        ) {
            Icon(Icons.Outlined.Notifications, contentDescription = null)
        }
        if (unread > 0) {
            Badge(
                containerColor = BrandTokens.gold,
                contentColor = BrandTokens.cardBackground,
                // M3 large badge: starts at the icon's horizontal centre, top 2 dp above the glyph.
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .offset(x = BELL_BADGE_START_DP.dp, y = BELL_BADGE_TOP_DP.dp)
                    .clearAndSetSemantics { }
                    .testTag("fst.shell.notifications.badge"),
            ) { Text(NotificationsViewModel.badgeText(unread)) }
        }
    }
}

/** Badge start inside the 48 dp bell button (the 24 dp glyph spans 12–36 dp). */
private const val BELL_BADGE_START_DP = 22

/** Badge top inside the 48 dp bell button. */
private const val BELL_BADGE_TOP_DP = 6

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
    // Rows fade in once the refresh lands (web fadeInUp stagger).
    val revealed = rememberRevealed(state is NotificationsState.Loaded)
    ModalBottomSheet(
        onDismissRequest = close,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = BrandTokens.cardBackground,
        modifier = Modifier.festivalSheetTop().popupTestTags().testTag("fst.notifications.sheet").semantics { paneTitle = "Notifications" },
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
                FestivalLoading("Loading notifications", Modifier.testTag("fst.notifications.loading"))
            }
            is NotificationsState.Failed -> ServiceStatusInline(
                current.issue, "Notifications unavailable", null, viewModel::refresh, Modifier.padding(16.dp).testTag("fst.notifications.failed"),
            )
            is NotificationsState.Empty -> EmptyState(current.body)
            is NotificationsState.Loaded -> LazyColumn(
                Modifier.fillMaxWidth().testTag("fst.notifications.list"),
                contentPadding = PaddingValues(start = 24.dp, end = 24.dp, top = 8.dp, bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                val olderOffset = if (current.newRows.isNotEmpty()) current.newRows.size + 1 else 0
                if (current.newRows.isNotEmpty()) {
                    item(key = "new") { Box(Modifier.festivalFadeIn(revealed)) { SectionTitle("New") } }
                    itemsIndexed(current.newRows, key = { _, row -> row.id }) { index, row ->
                        Box(Modifier.festivalFadeIn(revealed, fadeInStagger(index + 1))) { NotificationItem(row) { activate(viewModel, row, onDismiss, onNavigate) } }
                    }
                }
                if (current.olderRows.isNotEmpty()) {
                    item(key = "older") { Box(Modifier.festivalFadeIn(revealed, fadeInStagger(olderOffset))) { SectionTitle("Older") } }
                    itemsIndexed(current.olderRows, key = { _, row -> row.id }) { index, row ->
                        Box(Modifier.festivalFadeIn(revealed, fadeInStagger(olderOffset + index + 1))) { NotificationItem(row) { activate(viewModel, row, onDismiss, onNavigate) } }
                    }
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

/** Web section heading: small, semibold, upper case, 74% white. */
@Composable
private fun SectionTitle(text: String) {
    Text(
        text.uppercase(),
        style = MaterialTheme.typography.labelSmall,
        fontWeight = FontWeight.SemiBold,
        color = Color.White.copy(alpha = 0.74f),
        modifier = Modifier
            .padding(start = 2.dp, top = 8.dp, bottom = 2.dp)
            .semantics {
                heading()
                contentDescription = text
            },
    )
}

/** Web flag colours (`MobileNotificationsModal.FLAG_COLORS`). */
internal fun NotificationFlagKind.color(): Color = when (this) {
    NotificationFlagKind.Improvement -> Color(0xFF4B5563)
    NotificationFlagKind.FirstPlay -> Color(0xFF6D28D9)
    NotificationFlagKind.NewHighScore -> Color(0xFF0F766E)
    NotificationFlagKind.FullCombo -> Color(0xFF7C2D12)
    NotificationFlagKind.RankUp -> Color(0xFF1D4ED8)
    NotificationFlagKind.GoldStars -> Color(0xFF92400E)
    NotificationFlagKind.StarsUp -> Color(0xFFBE123C)
    NotificationFlagKind.DifficultyUp -> Color(0xFF047857)
    NotificationFlagKind.Progress -> Color(0xFF4338CA)
}

/** Media kind exposed to tests (the row clears its children's semantics). */
internal val NotificationMediaKind = SemanticsPropertyKey<String>("NotificationMediaKind")

/** Semantics accessor for [NotificationMediaKind]. */
internal var SemanticsPropertyReceiver.notificationMediaKind by NotificationMediaKind

/**
 * One web-style notification card: 64 dp media rail, marquee title, message with bold
 * values, coloured flag pill, and a trailing unread dot above the chevron. The relative time
 * is spoken but not drawn (the web row shows none).
 */
@Composable
private fun NotificationItem(row: NotificationRow, onClick: () -> Unit) {
    val presentation = row.presentation
    val navigable = presentation.destination != null
    val shape = RoundedCornerShape(10.dp)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 64.dp)
            .clip(shape)
            .background(BrandTokens.surfaceSubtle, shape)
            .border(1.dp, BORDER_SUBTLE, shape)
            .clickable(onClick = onClick)
            .padding(10.dp)
            .testTag("fst.notifications.row.${row.id}")
            .clearAndSetSemantics {
                contentDescription = row.accessibleText + if (navigable) " Open notification." else ""
                notificationMediaKind = presentation.media.kindName
                if (navigable) role = Role.Button
            },
    ) {
        MediaRail(presentation.media)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            FestivalMarqueeText(presentation.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = Color.White)
            Text(presentation.messageParts.toAnnotated(), style = MaterialTheme.typography.bodySmall, color = Color.White)
            val kind = presentation.flagKind
            if (kind != null) {
                Text(
                    kind.label,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.White,
                    modifier = Modifier
                        .background(kind.color(), RoundedCornerShape(8.dp))
                        .border(2.dp, Color.White.copy(alpha = 0.18f), RoundedCornerShape(8.dp))
                        .padding(horizontal = 6.dp, vertical = 2.dp),
                )
            }
        }
        if (row.unread || navigable) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.width(20.dp)) {
                if (row.unread) Box(Modifier.size(9.dp).background(UNREAD_DOT, CircleShape))
                if (navigable) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = Color.White.copy(alpha = 0.72f), modifier = Modifier.size(18.dp))
                }
            }
        }
    }
}

/** Test-visible name of a media kind. */
private val NotificationMedia.kindName: String
    get() = when (this) {
        is NotificationMedia.Song -> "song"
        is NotificationMedia.SongInstrumentGrid -> "songInstrumentGrid"
        is NotificationMedia.SoloInstrument -> "soloInstrument"
    }

/** Web media rail: 64 dp square; art 54 dp (44 dp above an icon grid), or a 36 dp instrument icon. */
@Composable
private fun MediaRail(media: NotificationMedia) {
    when (media) {
        is NotificationMedia.Song -> Box(Modifier.size(64.dp), contentAlignment = Alignment.Center) { RowArt(media.artUrl, 54) }
        is NotificationMedia.SoloInstrument -> Box(Modifier.size(64.dp), contentAlignment = Alignment.Center) {
            InstrumentIcon(media.instrument, size = 36.dp, decorative = true)
        }
        is NotificationMedia.SongInstrumentGrid -> Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier.width(64.dp),
        ) {
            RowArt(media.artUrl, 44)
            media.instruments.chunked(2).forEach { pair ->
                Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                    pair.forEach { InstrumentIcon(it, size = 18.dp, decorative = true) }
                }
            }
        }
    }
}

/** Decorative album art through the shared in-process Coil loader. */
@Composable
private fun RowArt(url: String, size: Int) {
    AsyncImage(
        model = url,
        contentDescription = null,
        contentScale = ContentScale.Crop,
        modifier = Modifier.size(size.dp).clip(RoundedCornerShape(8.dp)).background(BrandTokens.surfaceMuted),
    )
}

/** Message runs with the web's bold values. */
private fun List<NotificationMessagePart>.toAnnotated(): AnnotatedString = buildAnnotatedString {
    forEach { part ->
        if (part.emphasis) withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(part.text) } else append(part.text)
    }
}

/** Web empty state: muted bell-off glyph, bold title, short centred body. */
@Composable
private fun EmptyState(body: String) {
    Column(
        Modifier.fillMaxWidth().heightIn(min = 240.dp).padding(horizontal = 12.dp, vertical = 24.dp).testTag("fst.notifications.empty"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically),
    ) {
        Icon(Icons.Outlined.NotificationsOff, contentDescription = null, tint = Color.White.copy(alpha = 0.72f), modifier = Modifier.size(48.dp))
        Text(
            "No notifications available",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = Color.White,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 4.dp).semantics { heading() },
        )
        Text(body, style = MaterialTheme.typography.bodySmall, color = Color.White.copy(alpha = 0.68f), textAlign = TextAlign.Center, modifier = Modifier.widthIn(max = 240.dp))
    }
}

/** Web `borderSubtle`. */
private val BORDER_SUBTLE = Color(0xFF1E2A3A)

/** Web unread dot (`#facc15`). */
private val UNREAD_DOT = Color(0xFFFACC15)

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
