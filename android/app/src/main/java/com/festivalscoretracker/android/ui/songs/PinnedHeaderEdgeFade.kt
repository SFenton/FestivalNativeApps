package com.festivalscoretracker.android.ui.songs

import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.traversalIndex
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.songs.EdgeFade
import com.festivalscoretracker.android.core.songs.EdgeFadeItem
import com.festivalscoretracker.android.core.scrolledge.ScrollEdgeFade
import com.festivalscoretracker.android.core.songs.SongHeaderEdgeFade
import com.festivalscoretracker.android.ui.common.drawScrollEdgeRamp
import com.festivalscoretracker.android.ui.common.rememberScrollEdgeHardEdge

// region Pinned section header edge fade

/**
 * The pinned-header edge of one sticky-header list: where rows are cut and fade out below the
 * pinned header ([edge]), and the recorded drawings of its headers ([layers]) that
 * [pinnedHeaderEdgeFade] redraws whole over the cut and ramp (issues #49, #91, #288, #308). The
 * one pinned-section-title fade on Android (scroll-edge R1): every list with sticky section
 * titles uses it.
 *
 * @property depth Full ramp in px ([ScrollEdgeFade.TOP_DP]); 0 keeps a hard edge.
 * @property layers Recorded header drawings by list key ([rememberPinnedHeaderRecorder]).
 * @param listState The list's state.
 * @param firstHeaderKey Key of the list's first header, or null when the list has no headers.
 * @param isHeader Whether a list key is a sticky header's.
 * @param spacing Gap between list items in px.
 */
@Stable
internal class PinnedHeaderEdgeState(
    private val listState: LazyListState,
    private val firstHeaderKey: Any?,
    private val isHeader: (Any) -> Boolean,
    private val spacing: Int,
    val depth: Float,
    val layers: MutableMap<Any, GraphicsLayer>,
) {
    private fun visible(): List<EdgeFadeItem> =
        listState.layoutInfo.visibleItemsInfo.map { EdgeFadeItem(it.index, it.key, it.offset, it.size, isHeader(it.key)) }

    /** The current edge, or null when no header is pinned over scrolled rows. Read in the draw phase only. */
    val edge: EdgeFade? by derivedStateOf {
        if (firstHeaderKey == null) null
        else SongHeaderEdgeFade.edge(visible(), listState.layoutInfo.viewportStartOffset, spacing, depth)
    }

    /** Key of the header pinned at the list's top edge, or null ([SongHeaderEdgeFade.pinned]). */
    val pinnedKey: Any? by derivedStateOf {
        if (firstHeaderKey == null) null
        else SongHeaderEdgeFade.pinned(visible(), listState.layoutInfo.viewportStartOffset)?.key
    }

    /**
     * Recorded layers of the headers over a cut and its band, with their top offsets in px.
     *
     * @param top The cut ([EdgeFade.top]).
     * @return Layers and offsets, in list order.
     */
    fun headersOverEdge(top: Float): List<Pair<GraphicsLayer, Float>> {
        val start = listState.layoutInfo.viewportStartOffset
        return SongHeaderEdgeFade.headersOverEdge(visible(), start, top, depth)
            .mapNotNull { item -> layers[item.key]?.let { it to (item.offset - start).toFloat() } }
    }
}

/**
 * Remembers the [PinnedHeaderEdgeState] for a sticky-header list, with the ramp chosen by
 * [rememberScrollEdgeHardEdge] (R7).
 *
 * @param listState The list's state.
 * @param firstHeaderKey Key of the list's first header, or null.
 * @param spacing Gap between list items.
 * @param isHeader Whether a list key is a sticky header's (a stable function).
 * @return Edge state.
 */
@Composable
internal fun rememberPinnedHeaderEdge(
    listState: LazyListState,
    firstHeaderKey: Any?,
    spacing: Dp,
    isHeader: (Any) -> Boolean,
): PinnedHeaderEdgeState {
    val density = LocalDensity.current
    val depth = if (rememberScrollEdgeHardEdge()) 0f else with(density) { ScrollEdgeFade.TOP_DP.dp.toPx() }
    val spacingPx = with(density) { spacing.roundToPx() }
    // Headers register here once; the map outlives a depth change (an accessibility switch).
    val layers = remember { HashMap<Any, GraphicsLayer>() }
    return remember(listState, firstHeaderKey, isHeader, spacingPx, depth, layers) {
        PinnedHeaderEdgeState(listState, firstHeaderKey, isHeader, spacingPx, depth, layers)
    }
}

/**
 * Records a sticky header's drawing into a [GraphicsLayer] registered under [key] in [layers], so
 * [pinnedHeaderEdgeFade] can redraw it above the cut that hides rows scrolling under it. Apply it
 * to the header's outermost drawn node; the header draws normally too.
 *
 * @param key The header's list key.
 * @param layers The edge's [PinnedHeaderEdgeState.layers].
 * @return Recording modifier.
 */
@Composable
internal fun rememberPinnedHeaderRecorder(key: Any, layers: MutableMap<Any, GraphicsLayer>): Modifier {
    val layer = rememberGraphicsLayer()
    DisposableEffect(key, layer, layers) {
        layers[key] = layer
        onDispose { if (layers[key] === layer) layers.remove(key) }
    }
    return Modifier.drawWithContent {
        layer.record { this@drawWithContent.drawContent() }
        drawLayer(layer)
    }
}

/**
 * Has TalkBack read a sticky header before the rows beneath it while it is pinned (scroll-edge
 * R5). Compose orders a list's items by their on-screen bounds; a row partly hidden under the
 * pinned header ([pinnedHeaderEdgeFade] is drawing only) starts at the same top edge and further
 * left, so without this TalkBack read that row before the title naming its section (issue #462).
 * A pinned header gets a [traversalIndex] below its siblings in the list's traversal group; an
 * in-flow header keeps 0, so it is still read between the sections it divides.
 *
 * @param key The header's list key.
 * @param state The list's edge state.
 * @return Semantics modifier for the header's outermost node.
 */
@Composable
internal fun rememberPinnedHeaderReadOrder(key: Any, state: PinnedHeaderEdgeState): Modifier {
    val pinned by remember(key, state) { derivedStateOf { state.pinnedKey == key } }
    return if (pinned) Modifier.semantics { traversalIndex = PINNED_HEADER_TRAVERSAL_INDEX } else Modifier
}

/** Traversal index of the pinned header among its list's items (which keep 0). */
internal const val PINNED_HEADER_TRAVERSAL_INDEX = -1f

/**
 * Hides rows under the pinned section header and fades them in over the linear ramp just below
 * it ([SongHeaderEdgeFade]), so the header needs no backing (issue #91). On an offscreen layer it
 * clears everything above the header's resting bottom edge, masks the ramp
 * ([drawScrollEdgeRamp]), then redraws the recorded layers of the headers over the cut and ramp
 * whole ([SongHeaderEdgeFade.headersOverEdge]), so their text stays fully opaque, the next header
 * pushes the pinned one out without fading (issue #288) and no row ever shows behind a header.
 * With a hard edge ([PinnedHeaderEdgeState.depth] 0) rows end at the header's bottom edge.
 * Drawing only: hit testing and semantics are unchanged; [rememberPinnedHeaderReadOrder] keeps
 * the pinned header first in TalkBack order. Without an edge it draws
 * nothing and skips the offscreen layer.
 *
 * @param state The list's edge state.
 * @param headerStart Headers' start inset in px (the list's start content padding).
 * @return Drawing modifier.
 */
internal fun Modifier.pinnedHeaderEdgeFade(state: PinnedHeaderEdgeState, headerStart: Float): Modifier = this
    .graphicsLayer { compositingStrategy = if (state.edge != null) CompositingStrategy.Offscreen else CompositingStrategy.Auto }
    .drawWithContent {
        drawContent()
        val fade = state.edge ?: return@drawWithContent
        drawRect(Color.Transparent, size = Size(size.width, fade.top), blendMode = BlendMode.Clear)
        drawScrollEdgeRamp(clearY = fade.top, opaqueY = fade.top + fade.depth)
        // Headers are drawn whole and opaque over the cut and ramp, so the next header slides up and
        // pushes the pinned one out instead of fading in the band (issue #288). Each header's own
        // (partly faded) drawing is cleared first; list items never overlap a header there.
        val placed = state.headersOverEdge(fade.top).map { (layer, y) ->
            val x = if (layoutDirection == LayoutDirection.Ltr) headerStart else size.width - headerStart - layer.size.width
            Triple(layer, x, y)
        }
        for ((layer, x, y) in placed) {
            drawRect(Color.Transparent, Offset(x, y), Size(layer.size.width.toFloat(), layer.size.height.toFloat()), blendMode = BlendMode.Clear)
        }
        for ((layer, x, y) in placed) translate(x, y) { drawLayer(layer) }
    }

// endregion
