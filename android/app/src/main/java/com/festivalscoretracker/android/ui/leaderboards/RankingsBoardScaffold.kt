package com.festivalscoretracker.android.ui.leaderboards

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.constrainHeight
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.rankings.BoardFooterEdgeFade
import com.festivalscoretracker.android.core.rankings.FooterFade
import com.festivalscoretracker.android.core.songs.SongHeaderEdgeFade
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility

// region Board scaffold

/**
 * Layout shared by the paginated boards (Full Rankings, Band Rankings, Song
 * Leaderboard). View options (instrument, band size, Rank By) live in the top app
 * bar, so the content is the rows plus page-level information.
 *
 * Every width: the "your rank" row and the floating pager are anchored to the
 * bottom of the content, just above the bottom bar (the web's floating paginator;
 * Material 3 anchors page-level actions to the bottom edge within thumb reach), and
 * the rows scroll underneath with enough bottom padding to clear them. Around a
 * separating vertical hinge the rows keep the leading side, and the page
 * information, "your rank" row and pager sit on the other side of the fold,
 * bottom-anchored there, so nothing straddles the hinge.
 *
 * @param padding Screen padding from [com.festivalscoretracker.android.ui.common.FestivalScreen].
 * @param listState Row list state (the caller scrolls it on page changes).
 * @param idPrefix Test-tag prefix.
 * @param controls Page information shown above the rows (population, errors).
 * @param footer Anchored "your rank" content (may emit nothing).
 * @param pager Pager.
 * @param fadeAboveFooter Hide rows beneath the bottom-anchored footer and fade them out just
 *   above it ([BoardFooterEdgeFade], the web's scroll mask; issue #93); hidden rows also leave
 *   touch and TalkBack (issue #104).
 * @param rows Row items.
 */
@Composable
fun RankingsBoardScaffold(
    padding: PaddingValues,
    listState: LazyListState,
    idPrefix: String,
    controls: @Composable ColumnScope.() -> Unit,
    footer: @Composable ColumnScope.() -> Unit,
    pager: @Composable () -> Unit,
    fadeAboveFooter: Boolean = false,
    rows: LazyListScope.() -> Unit,
) {
    val (hinge, measure) = rememberHingeSplit()
    RankingsBoardLayout(hinge, measure, padding, listState, idPrefix, controls, footer, pager, fadeAboveFooter, rows)
}

/**
 * [RankingsBoardScaffold] for a known hinge split (tests pass one directly).
 *
 * @param hinge Separating vertical hinge relative to the board, or null.
 * @param measure Modifier that measures the board for [rememberHingeSplit].
 * @param padding Screen padding.
 * @param listState Row list state.
 * @param idPrefix Test-tag prefix.
 * @param controls Page information shown above the rows.
 * @param footer Anchored "your rank" content.
 * @param pager Pager.
 * @param fadeAboveFooter Fade rows out above the bottom-anchored footer (single pane only:
 *   around a hinge the footer sits in the other pane, clear of the rows).
 * @param rows Row items.
 */
@Composable
internal fun RankingsBoardLayout(
    hinge: HingeSplit?,
    measure: Modifier,
    padding: PaddingValues,
    listState: LazyListState,
    idPrefix: String,
    controls: @Composable ColumnScope.() -> Unit,
    footer: @Composable ColumnScope.() -> Unit,
    pager: @Composable () -> Unit,
    fadeAboveFooter: Boolean = false,
    rows: LazyListScope.() -> Unit,
) {
    val bottom = padding.calculateBottomPadding()
    Box(Modifier.fillMaxSize().padding(top = padding.calculateTopPadding()).then(measure)) {
        if (hinge != null) {
            Row(Modifier.fillMaxSize()) {
                Box(Modifier.width(hinge.start).fillMaxHeight()) {
                    BoardList(listState, idPrefix, PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = bottom + 24.dp), rows = rows)
                }
                Spacer(Modifier.width(hinge.end - hinge.start))
                Column(
                    Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = bottom + 12.dp)
                        .testTag("$idPrefix.supporting-pane"),
                ) {
                    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp), content = controls)
                    AnchoredFooter(idPrefix, footer, pager)
                }
            }
        } else {
            val density = LocalDensity.current
            var anchoredHeight by remember { mutableIntStateOf(0) }
            val anchoredDp = with(density) { anchoredHeight.toDp() }
            val accessibility = LocalFestivalAccessibility.current
            val fades = fadeAboveFooter && BoardFooterEdgeFade.isEnabled(accessibility.increaseContrast, accessibility.reduceTransparency)
            val depth = with(density) { BoardFooterEdgeFade.DEPTH_DP.dp.toPx() }
            // Read in the draw phase only, so scrolling never recomposes.
            val edge: () -> FooterFade? = {
                if (!fades) {
                    null
                } else {
                    val info = listState.layoutInfo
                    val last = info.visibleItemsInfo.lastOrNull()
                    val remaining = BoardFooterEdgeFade.remainingScroll(
                        totalItems = info.totalItemsCount,
                        lastVisibleIndex = last?.index ?: -1,
                        lastOffset = last?.offset ?: 0,
                        lastSize = last?.size ?: 0,
                        afterContentPadding = info.afterContentPadding,
                        viewportEnd = info.viewportEndOffset,
                    )
                    BoardFooterEdgeFade.edge(info.viewportSize.height, anchoredHeight, remaining, depth)
                }
            }
            Box(Modifier.fillMaxSize()) {
                BoardList(
                    listState,
                    idPrefix,
                    // The list ends one item gap above the footer, so the pinned row or pager follows
                    // the last row like another item (issue #293).
                    PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = anchoredDp + ROW_GAP_DP.dp),
                    Modifier
                        .then(if (fades) Modifier.clipAboveFooter { anchoredHeight } else Modifier)
                        .footerEdgeFade(edge, depth),
                ) {
                    item(key = "controls") { Column(verticalArrangement = Arrangement.spacedBy(8.dp), content = controls) }
                    rows()
                }
                AnchoredFooter(
                    idPrefix,
                    footer,
                    pager,
                    Modifier
                        .align(Alignment.BottomCenter)
                        .onSizeChanged { anchoredHeight = it.height }
                        .padding(start = 16.dp, end = 16.dp, bottom = bottom + 12.dp),
                )
            }
        }
    }
}

/**
 * The bottom-anchored "your rank" row and floating pager.
 *
 * @param idPrefix Test-tag prefix (`<prefix>.bottom-bar`).
 * @param footer "Your rank" content.
 * @param pager Pager.
 * @param modifier Modifier (alignment and insets).
 */
@Composable
private fun AnchoredFooter(idPrefix: String, footer: @Composable ColumnScope.() -> Unit, pager: @Composable () -> Unit, modifier: Modifier = Modifier) {
    Column(
        modifier.widthIn(max = MAX_FOOTER_WIDTH_DP.dp).fillMaxWidth().testTag("$idPrefix.bottom-bar"),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(Modifier.fillMaxWidth().gapBelowIfShown(FOOTER_PAGER_GAP_DP.dp), content = footer)
        pager()
    }
}

/**
 * Adds [gap] below content that has height, and nothing below empty content, so a board
 * without a "your rank" row keeps no empty slot above its pager (issue #293).
 *
 * @param gap Space below non-empty content.
 */
private fun Modifier.gapBelowIfShown(gap: Dp): Modifier = layout { measurable, constraints ->
    val placeable = measurable.measure(constraints)
    val extra = if (placeable.height > 0) gap.roundToPx() else 0
    layout(placeable.width, constraints.constrainHeight(placeable.height + extra)) { placeable.place(0, 0) }
}

/**
 * Opaque card for anchored "your rank" content, so the floating row stays legible
 * over the rows scrolling beneath it.
 *
 * @param modifier Modifier.
 * @param content Row content.
 */
@Composable
fun AnchoredRowCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Surface(
        shape = RoundedCornerShape(12.dp),
        // Opaque: no row may show through a pinned footer (operator batch 5).
        color = BrandTokens.cardBackground,
        border = BorderStroke(1.dp, BrandTokens.glassBorder),
        shadowElevation = 4.dp,
        modifier = modifier.fillMaxWidth(),
    ) {
        // Same inset as the rows' card, so the pinned row's columns line up with the list.
        Column(Modifier.padding(8.dp), content = content)
    }
}

/** Widest the anchored footer grows on large windows (keeps the pager and row centred). */
private const val MAX_FOOTER_WIDTH_DP = 720

/** Space between list items, also left between the last item and the anchored footer. */
private const val ROW_GAP_DP = 12

/** Space between the "your rank" row and the pager. */
private const val FOOTER_PAGER_GAP_DP = 8

@Composable
private fun BoardList(
    listState: LazyListState,
    idPrefix: String,
    contentPadding: PaddingValues,
    modifier: Modifier = Modifier,
    rows: LazyListScope.() -> Unit,
) {
    LazyColumn(
        state = listState,
        contentPadding = contentPadding,
        verticalArrangement = Arrangement.spacedBy(ROW_GAP_DP.dp),
        modifier = modifier.fillMaxSize().testTag("$idPrefix.list"),
        content = rows,
    )
}

/**
 * Clips the full-height list at the floating footer's top edge, where [footerEdgeFade] already
 * hides the rows: the list keeps its full viewport (scrolling, padding and the fade are
 * unchanged) but reports the shorter size, so rows beneath the footer and pager leave touch and
 * the accessibility tree. Otherwise TalkBack skips a row fully covered by the footer and focuses
 * hidden rows peeking around the pager instead of scrolling (issue #104).
 *
 * @param footerHeight Anchored footer height in px, bottom inset included (read during layout).
 */
private fun Modifier.clipAboveFooter(footerHeight: () -> Int): Modifier = this
    .clipToBounds()
    .layout { measurable, constraints ->
        val placeable = measurable.measure(constraints)
        val visible = (placeable.height - footerHeight()).coerceIn(0, placeable.height)
        layout(placeable.width, visible) { placeable.place(0, 0) }
    }

/**
 * Hides rows beneath the floating footer and fades them out over an eased band ending at its
 * top edge ([BoardFooterEdgeFade]), so the footer and pager float over the page background
 * with no row showing behind or between them. On an offscreen layer it masks the band with a
 * vertical gradient (`BlendMode.DstIn`) and clears everything below the cut. Drawing only: hit
 * testing, semantics and TalkBack order are unchanged. Without an edge it draws nothing extra
 * and skips the offscreen layer.
 *
 * @param edge Reads the current edge (draw phase only).
 * @param depth Band depth in px.
 */
private fun Modifier.footerEdgeFade(edge: () -> FooterFade?, depth: Float): Modifier = this
    .graphicsLayer { compositingStrategy = if (edge() != null) CompositingStrategy.Offscreen else CompositingStrategy.Auto }
    .drawWithContent {
        drawContent()
        val fade = edge() ?: return@drawWithContent
        val top = (fade.cut - depth).coerceAtLeast(0f)
        if (fade.cut > top) {
            // Full-strength alpha runs 1 → 0 down the band (the Songs header easing, reversed).
            val stops = SongHeaderEdgeFade.STOPS
                .map { (t, alpha) -> t to Color.Black.copy(alpha = SongHeaderEdgeFade.maskAlpha(1f - alpha, fade.strength)) }
                .toTypedArray()
            drawRect(
                Brush.verticalGradient(*stops, startY = fade.cut - depth, endY = fade.cut),
                topLeft = Offset(0f, top),
                size = Size(size.width, fade.cut - top),
                blendMode = BlendMode.DstIn,
            )
        }
        drawRect(Color.Transparent, topLeft = Offset(0f, fade.cut), size = Size(size.width, size.height - fade.cut), blendMode = BlendMode.Clear)
    }

// endregion
