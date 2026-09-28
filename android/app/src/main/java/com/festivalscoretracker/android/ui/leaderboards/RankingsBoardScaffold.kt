package com.festivalscoretracker.android.ui.leaderboards

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.rankings.LeaderboardsLayoutPolicy
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Board scaffold

/**
 * Layout shared by the paginated boards (Full Rankings, Band Rankings, Song
 * Leaderboard). Compact/medium: controls scroll with the rows, and the "your rank"
 * footer plus pager stay pinned above the bottom chrome. Expanded (≥ 840 dp) or
 * around a separating vertical hinge: rows in the list pane, controls, footer and
 * pager in a supporting pane on the other side of the fold (Material 3 supporting
 * pane pattern), so nothing straddles the hinge.
 *
 * @param padding Screen padding from [com.festivalscoretracker.android.ui.common.FestivalScreen].
 * @param listState Row list state (the caller scrolls it on page changes).
 * @param idPrefix Test-tag prefix.
 * @param loadingOverlay Whether a newer page is loading over the shown rows.
 * @param controls Pickers and population text.
 * @param footer Pinned "your rank" content (may emit nothing).
 * @param pager Pager.
 * @param rows Row items.
 */
@Composable
fun RankingsBoardScaffold(
    padding: PaddingValues,
    listState: LazyListState,
    idPrefix: String,
    loadingOverlay: Boolean,
    controls: @Composable ColumnScope.() -> Unit,
    footer: @Composable ColumnScope.() -> Unit,
    pager: @Composable () -> Unit,
    rows: LazyListScope.() -> Unit,
) {
    val (hinge, measure) = rememberHingeSplit()
    BoxWithConstraints(Modifier.fillMaxSize().padding(top = padding.calculateTopPadding()).then(measure)) {
        val supporting = LeaderboardsLayoutPolicy.showsSupportingPane(maxWidth.value.toInt(), hinge != null)
        val bottom = padding.calculateBottomPadding()
        if (supporting) {
            val paneWidth = LeaderboardsLayoutPolicy.SUPPORTING_PANE_DP.dp
            Row(Modifier.fillMaxSize()) {
                val listModifier = if (hinge != null) Modifier.width(hinge.start) else Modifier.weight(1f)
                Box(listModifier.fillMaxHeight()) {
                    BoardList(listState, idPrefix, loadingOverlay, PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = bottom + 24.dp), rows)
                }
                if (hinge != null) Spacer(Modifier.width(hinge.end - hinge.start))
                val paneModifier = if (hinge != null) Modifier.weight(1f) else Modifier.width(paneWidth)
                Column(
                    paneModifier
                        .fillMaxHeight()
                        .verticalScroll(rememberScrollState())
                        .padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = bottom + 24.dp)
                        .testTag("$idPrefix.supporting-pane"),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    controls()
                    GlassCard(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(8.dp)) {
                            footer()
                            pager()
                        }
                    }
                }
            }
        } else {
            Column(Modifier.fillMaxSize()) {
                Box(Modifier.weight(1f)) {
                    BoardList(listState, idPrefix, loadingOverlay, PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 16.dp)) {
                        item(key = "controls") { Column(verticalArrangement = Arrangement.spacedBy(8.dp), content = controls) }
                        rows()
                    }
                }
                Surface(color = BrandTokens.cardBackground.copy(alpha = 0.96f), modifier = Modifier.fillMaxWidth().testTag("$idPrefix.bottom-bar")) {
                    Column(Modifier.padding(start = 8.dp, end = 8.dp, top = 4.dp, bottom = bottom).widthIn(max = 840.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        footer()
                        pager()
                    }
                }
            }
        }
    }
}

@Composable
private fun BoardList(listState: LazyListState, idPrefix: String, loadingOverlay: Boolean, contentPadding: PaddingValues, rows: LazyListScope.() -> Unit) {
    Box(Modifier.fillMaxSize()) {
        LazyColumn(
            state = listState,
            contentPadding = contentPadding,
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.fillMaxSize().testTag("$idPrefix.list"),
            content = rows,
        )
        if (loadingOverlay) {
            LinearProgressIndicator(
                color = BrandTokens.accentBlue,
                modifier = Modifier.fillMaxWidth().align(Alignment.TopCenter).semantics { contentDescription = "Loading page" },
            )
        }
    }
}

// endregion
