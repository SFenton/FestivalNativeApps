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
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.ui.theme.BrandTokens

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
    rows: LazyListScope.() -> Unit,
) {
    val (hinge, measure) = rememberHingeSplit()
    RankingsBoardLayout(hinge, measure, padding, listState, idPrefix, controls, footer, pager, rows)
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
    rows: LazyListScope.() -> Unit,
) {
    val bottom = padding.calculateBottomPadding()
    Box(Modifier.fillMaxSize().padding(top = padding.calculateTopPadding()).then(measure)) {
        if (hinge != null) {
            Row(Modifier.fillMaxSize()) {
                Box(Modifier.width(hinge.start).fillMaxHeight()) {
                    BoardList(listState, idPrefix, PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = bottom + 24.dp), rows)
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
            Box(Modifier.fillMaxSize()) {
                BoardList(listState, idPrefix, PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = anchoredDp + 16.dp)) {
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
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Column(Modifier.fillMaxWidth(), content = footer)
        pager()
    }
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

@Composable
private fun BoardList(listState: LazyListState, idPrefix: String, contentPadding: PaddingValues, rows: LazyListScope.() -> Unit) {
    LazyColumn(
        state = listState,
        contentPadding = contentPadding,
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxSize().testTag("$idPrefix.list"),
        content = rows,
    )
}

// endregion
