package com.festivalscoretracker.android.ui.shop

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.text.style.TextOverflow
import com.festivalscoretracker.android.ui.design.festivalFilledButtonColors
import com.festivalscoretracker.android.ui.common.FestivalEmptyState
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.ShoppingCart
import com.festivalscoretracker.android.ui.common.FestivalMarqueeText
import com.festivalscoretracker.android.ui.common.fadeInStagger
import com.festivalscoretracker.android.ui.common.rememberRevealed
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.itemsIndexed
import com.festivalscoretracker.android.ui.common.festivalFadeIn
import androidx.compose.material3.ButtonDefaults
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import com.festivalscoretracker.android.core.shop.ShopPulse
import com.festivalscoretracker.android.ui.songs.SongsTokens
import com.festivalscoretracker.android.ui.songs.pulseOutline
import com.festivalscoretracker.android.ui.songs.rememberShopBreathe
import com.festivalscoretracker.android.ui.songs.rememberShopPulse
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.automirrored.filled.ViewList
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Info
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import coil3.compose.AsyncImage
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import com.festivalscoretracker.android.core.shop.ShopHighlight
import com.festivalscoretracker.android.data.songs.ShopViewMode
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.ShellViewModel
import com.festivalscoretracker.android.presentation.shop.ShopOfferItem
import com.festivalscoretracker.android.presentation.shop.ShopUiState
import com.festivalscoretracker.android.presentation.shop.ShopViewModel
import com.festivalscoretracker.android.ui.common.FestivalScreen
import com.festivalscoretracker.android.ui.common.LoadingView
import com.festivalscoretracker.android.ui.common.LocalShellActions
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.theme.BrandTokens
import kotlinx.coroutines.launch
import com.festivalscoretracker.android.ui.common.oneLineUnlessLarge

// region Route

/**
 * Item Shop route wiring: shared Shop feed, best-effort catalogue for Details
 * links and the persisted grid/list preference.
 *
 * @param container Process dependencies.
 * @param shellViewModel Shell (effective settings).
 */
@Composable
fun ShopRouteScreen(container: AppContainer, shellViewModel: ShellViewModel) {
    val api = container.api
    val viewModel: ShopViewModel = viewModel {
        ShopViewModel(container.shop.state, { api.catalog(it) }, shellViewModel.settings, container.backoff)
    }
    LaunchedEffect(Unit) { container.shop.ensureStarted() }
    val prefs by container.songsPreferences.state.collectAsStateWithLifecycle(null)
    val scope = rememberCoroutineScope()
    ShopScreen(
        viewModel = viewModel,
        viewMode = prefs?.shopViewMode ?: ShopViewMode.Grid,
        onViewMode = { mode -> scope.launch { container.songsPreferences.setShopViewMode(mode) } },
        artworkUrl = api::artworkUrl,
        onRetry = container.shop::retry,
    )
}

// endregion

// region Screen

/**
 * Item Shop: title-ordered offers with New / Leaving Tomorrow badges, the official
 * Shop link and an in-app Details action for catalogue songs. Compact widths
 * always use the list; wider windows offer a grid/list toggle.
 *
 * @param viewModel Shop logic.
 * @param viewMode Saved layout.
 * @param onViewMode Persist a layout.
 * @param artworkUrl Artwork resolver.
 * @param onRetry Retry the Shop read.
 */
@Composable
fun ShopScreen(
    viewModel: ShopViewModel,
    viewMode: ShopViewMode,
    onViewMode: (ShopViewMode) -> Unit,
    artworkUrl: (String?) -> String?,
    onRetry: () -> Unit,
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val compact = maxWidth < COMPACT_WIDTH
        val effective = if (compact) ShopViewMode.List else viewMode
        FestivalScreen(
            title = "Item Shop",
            isRoot = false,
            actions = {
                if (!compact && !state.hidden) {
                    val next = if (effective == ShopViewMode.Grid) ShopViewMode.List else ShopViewMode.Grid
                    IconButton(onClick = { onViewMode(next) }, modifier = Modifier.testTag("fst.shop.view-toggle")) {
                        Icon(
                            if (next == ShopViewMode.List) Icons.AutoMirrored.Filled.ViewList else Icons.Filled.GridView,
                            contentDescription = if (next == ShopViewMode.List) "List View" else "Grid View",
                        )
                    }
                }
            },
        ) { padding ->
            val loadedRevealed = rememberRevealed(state.shop is LoadState.Loaded)
            when {
                state.hidden -> HiddenView(padding)
                else -> when (val shop = state.shop) {
                    LoadState.Loading -> LoadingView("Loading Item Shop", Modifier.padding(padding))
                    is LoadState.Failed -> Box(Modifier.testTag("fst.shop.error")) {
                        ServiceStatusView(shop.issue, "Item Shop unavailable", shop.countdown, onRetry, contentPadding = padding)
                    }
                    // A List ↔ Grid switch recomposes the new layout from the top with the web's
                    // fade/stagger again (web `useViewTransition`, operator 6.10).
                    is LoadState.Loaded -> key(effective) {
                        val switched = rememberViewSwitch(effective)
                        ShopContent(state, effective, artworkUrl, viewModel::retryCatalog, padding, loadedRevealed && switched)
                    }
                }
            }
        }
    }
}

/** Widths below this always use the list. */
private val COMPACT_WIDTH = 600.dp

/**
 * False for one frame when [mode] differs from the last shown layout, so a freshly
 * switched layout fades in again; true otherwise (first visit uses the load fade).
 *
 * @param mode Layout now shown.
 * @return Value to AND into the reveal flag.
 */
@Composable
private fun rememberViewSwitch(mode: ShopViewMode): Boolean {
    var last by rememberSaveable { mutableStateOf<ShopViewMode?>(null) }
    val switching = last != null && last != mode
    var shown by remember { mutableStateOf(!switching) }
    LaunchedEffect(mode) {
        last = mode
        shown = true
    }
    return shown
}

/**
 * Web grid columns (`ShopPage`): 5 from 1100, 4 from 860, 3 from 600 CSS px, else 2.
 *
 * @param widthDp Content width.
 * @return Columns.
 */
internal fun shopGridColumns(widthDp: Float): Int = when {
    widthDp >= 1100f -> 5
    widthDp >= 860f -> 4
    widthDp >= 600f -> 3
    else -> 2
}

@Composable
private fun HiddenView(padding: PaddingValues) {
    val shell = LocalShellActions.current
    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.fillMaxSize().padding(padding).padding(24.dp).testTag("fst.shop.hidden"),
    ) {
        Text("Item Shop Is Hidden", style = MaterialTheme.typography.titleMedium, color = BrandTokens.textPrimary, modifier = Modifier.semantics { heading() })
        Text("Turn off Hide Item Shop in Settings to see today's Jam Tracks.", color = BrandTokens.textSecondary, textAlign = TextAlign.Center)
        OutlinedButton(onClick = shell.back) { Text("Go Back") }
    }
}

@Composable
private fun ShopContent(
    state: ShopUiState,
    mode: ShopViewMode,
    artworkUrl: (String?) -> String?,
    onRetryCatalog: () -> Unit,
    padding: PaddingValues,
    revealed: Boolean,
) {
    val shell = LocalShellActions.current
    val uri = LocalUriHandler.current
    val openOfficial: (ShopOfferItem) -> Unit = { item -> item.officialUrl?.let(uri::openUri) }
    val openDetail: (ShopOfferItem) -> Unit = { item -> item.detailSongId?.let { shell.navigate(SongDetailRoute(it)) } }
    val contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding() + 16.dp)
    val pulse = rememberShopPulse(active = state.offers.any { it.highlight != null })
    val header: @Composable () -> Unit = {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (state.detailsUnavailable) DetailsUnavailable(onRetryCatalog)
        }
    }
    if (state.offers.isEmpty()) {
        Column(Modifier.fillMaxSize().padding(contentPadding)) {
            header()
            EmptyShop(Modifier.weight(1f))
        }
        return
    }
    if (mode == ShopViewMode.Grid) BoxWithConstraints(Modifier.fillMaxSize()) {
        val columns = shopGridColumns((maxWidth - 32.dp).value)
        LazyVerticalGrid(
            columns = GridCells.Fixed(columns),
            contentPadding = contentPadding,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.fillMaxSize().testTag("fst.shop.grid"),
        ) {
            item(key = "header", span = { GridItemSpan(maxLineSpan) }) { header() }
            itemsIndexed(state.offers, key = { _, item -> item.offer.songId }) { index, item ->
                Box(Modifier.festivalFadeIn(revealed, fadeInStagger(index))) {
                    ShopGridCard(item, artworkUrl(item.offer.albumArt), pulse, { openOfficial(item) }, { openDetail(item) })
                }
            }
        }
    } else {
        LazyColumn(
            contentPadding = contentPadding,
            verticalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier.fillMaxSize().testTag("fst.shop.list"),
        ) {
            item(key = "header") { header() }
            itemsIndexed(state.offers, key = { _, item -> item.offer.songId }) { index, item ->
                Box(Modifier.festivalFadeIn(revealed, fadeInStagger(index))) {
                    ShopListRow(item, artworkUrl(item.offer.albumArt), pulse, { openOfficial(item) }, { openDetail(item) })
                }
            }
        }
    }
}

/** Web Item Shop `EmptyState` (`shop.empty` / `shop.emptyHint`), centred in the page (6.33). */
@Composable
private fun EmptyShop(modifier: Modifier = Modifier) {
    FestivalEmptyState(
        "No Songs in the Item Shop",
        modifier.fillMaxSize().testTag("fst.shop.empty"),
        subtitle = "Check back later — the shop updates regularly.",
    )
}

@Composable
private fun DetailsUnavailable(onRetry: () -> Unit) {
    GlassCard(Modifier.fillMaxWidth().testTag("fst.shop.song-details-error")) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp)) {
            Icon(Icons.Filled.Info, contentDescription = null, tint = BrandTokens.gold, modifier = Modifier.size(20.dp))
            Text("Song details unavailable", color = BrandTokens.textPrimary, modifier = Modifier.weight(1f).padding(start = 10.dp))
            TextButton(onClick = onRetry) { Text("Retry") }
        }
    }
}

// endregion

// region Offer views

/**
 * New / Leaving Tomorrow badge (visible text, never color alone).
 *
 * @param highlight Accent.
 * @param songId Song (test tag).
 */
@Composable
fun ShopBadgeLabel(highlight: ShopHighlight, songId: String, modifier: Modifier = Modifier) {
    val leaving = highlight == ShopHighlight.LeavingTomorrow
    Text(
        highlight.label,
        style = MaterialTheme.typography.labelMedium,
        fontWeight = FontWeight.Bold,
        color = if (leaving) BrandTokens.textPrimary else BrandTokens.gold,
        modifier = modifier
            .clip(RoundedCornerShape(6.dp))
            .background(if (leaving) BrandTokens.statusRed else BrandTokens.appBackground)
            .padding(horizontal = 8.dp, vertical = 2.dp)
            .testTag(if (leaving) "fst.shop.badge.leaving.$songId" else "fst.shop.badge.new.$songId"),
    )
}

/**
 * Shop card outline pulse (web `ShopCard`: red Leaving Tomorrow, gold New; every
 * card is in the Shop, so there is no green).
 *
 * @param highlight Accent.
 * @param pulse Shared alpha.
 * @return Modifier.
 */
private fun Modifier.shopPulse(highlight: ShopHighlight?, pulse: () -> Float): Modifier = when (highlight) {
    ShopHighlight.LeavingTomorrow -> pulseOutline(SongsTokens.pulse(ShopPulse.LeavingTomorrow), pulse)
    ShopHighlight.New -> pulseOutline(SongsTokens.pulse(ShopPulse.New), pulse)
    null -> this
}

/**
 * Web `ShopCard`: square artwork filling the card, title and artist on a bottom scrim,
 * a "Leaving Tomorrow" pill top-right, and the red/gold outline pulse. The card opens
 * the official Shop page (or the song when there is none); Song Details is a custom
 * accessibility action and a long press.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ShopGridCard(item: ShopOfferItem, artUrl: String?, pulse: () -> Float, onOfficial: () -> Unit, onDetail: () -> Unit) {
    val offer = item.offer
    val shape = RoundedCornerShape(12.dp)
    val open = if (item.officialUrl != null) onOfficial else onDetail
    Box(
        Modifier
            .fillMaxWidth()
            .aspectRatio(1f)
            .shopPulse(item.highlight, pulse)
            .clip(shape)
            .background(BrandTokens.accentPurple.copy(alpha = 0.35f))
            .combinedClickable(onClick = open, onLongClick = if (item.detailSongId != null) onDetail else null)
            .semantics {
                contentDescription = item.announcement + if (item.officialUrl != null) ". Opens the Fortnite Item Shop" else ""
                if (item.detailSongId != null) customActions = listOf(CustomAccessibilityAction("Song Details") { onDetail(); true })
            }
            .testTag("fst.shop.song.${offer.songId}"),
    ) {
        if (artUrl != null) {
            AsyncImage(model = artUrl, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        }
        Column(
            Modifier
                .align(Alignment.BottomStart)
                .fillMaxWidth()
                .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.85f))))
                .padding(horizontal = 12.dp, vertical = 10.dp)
                .clearAndSetSemantics { },
        ) {
            Text(offer.title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = BrandTokens.textPrimary, maxLines = oneLineUnlessLarge(), overflow = TextOverflow.Ellipsis)
            Text(offer.artist, style = MaterialTheme.typography.bodySmall, color = BrandTokens.textSecondary, maxLines = oneLineUnlessLarge(), overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 2.dp))
        }
        if (item.highlight == ShopHighlight.LeavingTomorrow) {
            // The card's description already says "Leaving Tomorrow".
            ShopBadgeLabel(ShopHighlight.LeavingTomorrow, offer.songId, Modifier.align(Alignment.TopEnd).padding(10.dp).clearAndSetSemantics { })
        }
        if (item.officialUrl != null) Box(Modifier.size(0.dp).testTag("fst.shop.external.${offer.songId}"))
    }
}

@Composable
private fun ShopListRow(item: ShopOfferItem, artUrl: String?, pulse: () -> Float, onOfficial: () -> Unit, onDetail: () -> Unit) {
    val offer = item.offer
    GlassCard(
        onClick = if (item.detailSongId != null) onDetail else onOfficial,
        modifier = Modifier
            .fillMaxWidth()
            .shopPulse(item.highlight, pulse)
            // TalkBack reads the title, subtitle and badge texts themselves (a description repeated them).
            .testTag("fst.shop.song.${offer.songId}"),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.padding(start = 12.dp, top = 8.dp, bottom = 8.dp, end = 4.dp),
        ) {
            AsyncImage(
                model = artUrl,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(48.dp).clip(RoundedCornerShape(8.dp)).background(BrandTokens.surfaceMuted),
            )
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                FestivalMarqueeText(offer.title, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold), color = BrandTokens.textPrimary)
                FestivalMarqueeText(offer.subtitle, style = MaterialTheme.typography.bodyMedium, color = BrandTokens.textSecondary)
                item.highlight?.let { ShopBadgeLabel(it, offer.songId) }
            }
            if (item.officialUrl != null) {
                IconButton(
                    onClick = onOfficial,
                    modifier = Modifier.heightIn(min = 48.dp).testTag("fst.shop.external.${offer.songId}"),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.ShoppingCart, contentDescription = "Open ${offer.title} in the Fortnite Item Shop", modifier = Modifier.size(20.dp))
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, modifier = Modifier.size(18.dp))
                    }
                }
            }
        }
    }
}

// endregion

// region Detail action

/**
 * Official Shop action for Song Detail: the "Item Shop" pill (its status is in the
 * spoken label; no separate New / Leaving chip, operator rule). With a
 * pulse the button breathes between the dark surface and green (in Shop), gold
 * (New) or red (Leaving Tomorrow) every 3 s (web `shopBreathe*`); reduced motion
 * holds the target color. The color is read only while drawing.
 *
 * @param highlight Effective badge.
 * @param url Validated official URL.
 * @param songId Song (test tag).
 * @param pulse Effective Shop pulse.
 */
@Composable
fun ShopDetailAction(highlight: ShopHighlight?, url: String, songId: String, pulse: ShopPulse? = null) {
    val uri = LocalUriHandler.current
    val fraction = rememberShopBreathe(active = pulse != null)
    val breathe: (() -> Color)? = pulse?.let { status -> { SongsTokens.breathe(status, fraction()) } }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.testTag("fst.song-detail.shop")) {
        Button(
            onClick = { uri.openUri(url) },
            colors = if (breathe != null) ButtonDefaults.buttonColors(containerColor = Color.Transparent, contentColor = BrandTokens.textPrimary) else festivalFilledButtonColors(),
            modifier = Modifier
                .semantics { contentDescription = listOfNotNull("Item Shop", highlight?.label, "opens the Fortnite Item Shop").joinToString(", ") }
                .then(
                    if (breathe != null) {
                        Modifier.testTag("fst.song-detail.shop-breathe.${pulse!!.name}").drawBehind { drawRoundRect(breathe(), cornerRadius = CornerRadius(size.height / 2)) }
                    } else {
                        Modifier
                    },
                ),
        ) {
            Icon(Icons.AutoMirrored.Filled.OpenInNew, contentDescription = null, modifier = Modifier.size(18.dp))
            // The button's description already says "Item Shop".
            Text("Item Shop", modifier = Modifier.padding(start = 6.dp).clearAndSetSemantics {})
        }
    }
}

// endregion
