package com.festivalscoretracker.android.ui.common

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.State
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.shell.EmptyRegion
import com.festivalscoretracker.android.core.shell.LoadGatePhase
import com.festivalscoretracker.android.core.shell.LoadGatePolicy
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility

// region Load gate

/**
 * What gated content receives: whether its entrance should play now, and a stagger modifier.
 *
 * @property revealed Pass to [festivalFadeIn]: false for the first frame after the spinner left
 *   (so each child sees the change and fades in), true otherwise.
 */
@Stable
class LoadGateScope internal constructor(val revealed: Boolean) {
    /**
     * The web's staggered `fadeInUp` entrance for the child at [index] (125 ms apart, capped).
     *
     * @param index Zero-based order of the child on the page.
     * @return Modifier.
     */
    fun Modifier.staggered(index: Int): Modifier = festivalFadeIn(revealed, fadeInStagger(index))
}

/**
 * The shared page load gate (operator batch 6.41, web `LoadGate` + `Page` phases): a page shows
 * only the app's spinner until its data is [ready], the spinner fades out (500 ms), and then
 * the content appears with its staggered entrance ([LoadGateScope.staggered]). Pages never show
 * half-built content in between.
 *
 * Data that is ready on first composition (cached, or a page navigated back to) shows at once
 * with no spinner or entrance, and content already shown stays up while it refreshes. Reduce
 * Motion skips the fade and the entrance. Everything animates in the draw phase only.
 *
 * @param ready Whether the page's data is ready (failures count as ready: show their state).
 * @param modifier Modifier for the page area (the spinner centres in it).
 * @param label Spinner's accessible description.
 * @param composeWhileLoading Compose the content invisibly (and hidden from accessibility)
 *   under the spinner, for pages whose own children start loading when composed (e.g. lazy
 *   cards that fetch as they appear); it is revealed with the same entrance once ready.
 * @param content Page content.
 */
@Composable
fun FestivalLoadGate(
    ready: Boolean,
    modifier: Modifier = Modifier,
    label: String = "Loading",
    composeWhileLoading: Boolean = false,
    content: @Composable LoadGateScope.() -> Unit,
) {
    val reduceMotion = LocalFestivalAccessibility.current.reduceMotion
    var phase by remember { mutableStateOf(LoadGatePolicy.initial(ready)) }
    var sawSpinner by remember { mutableStateOf(!ready) }
    val spinnerAlpha = remember { Animatable(1f) }
    LaunchedEffect(ready, reduceMotion) {
        phase = LoadGatePolicy.onReady(phase, ready, reduceMotion)
        if (phase == LoadGatePhase.Loading) {
            sawSpinner = true
            spinnerAlpha.snapTo(1f)
        }
    }
    LaunchedEffect(phase) {
        if (phase == LoadGatePhase.SpinnerOut) {
            spinnerAlpha.animateTo(0f, tween(LoadGatePolicy.SPINNER_FADE_MS, easing = FadeInEasing))
            phase = LoadGatePolicy.afterFade(phase)
        }
    }
    Box(modifier.testTag("fst.load-gate")) {
        val contentIn = phase == LoadGatePhase.ContentIn
        if (contentIn || composeWhileLoading) {
            var revealed by remember { mutableStateOf(contentIn && !LoadGatePolicy.animatesEntrance(sawSpinner, reduceMotion)) }
            LaunchedEffect(contentIn) { if (contentIn) revealed = true }
            // One call site in every phase, so content composed while loading keeps its state.
            Box(if (contentIn) Modifier else Modifier.graphicsLayer { alpha = 0f }.clearAndSetSemantics { }) {
                LoadGateScope(revealed).content()
            }
        }
        if (!contentIn) {
            Box(
                Modifier
                    .fillMaxSize()
                    .graphicsLayer { alpha = spinnerAlpha.value }
                    .testTag("fst.load-gate.spinner"),
                contentAlignment = Alignment.Center,
            ) { FestivalLoading(label) }
        }
    }
}

// endregion

// region Empty state

/**
 * The shared empty state (operator batch 6.33, web `EmptyState` with `fullPage`): an optional
 * icon, a bold title and an optional subtitle, centred horizontally and **vertically** in the
 * space it is given (the web centres it in the viewport below the shell chrome).
 *
 * Every empty page or result region uses this one component (issue #377): plain centred text
 * with no background card and no Reset Filters button; the subtitle says what to change
 * instead. Loading and failures keep their own components ([FestivalLoading], `ServiceStatusView`).
 *
 * In a lazy list use [festivalEmptyStateItem] so it fills the viewport height; below page
 * controls or above an inline pager, size the item with [rememberEmptyRegion] and
 * [fillEmptyRegion] so it fills the visible region they leave, never a fixed height.
 *
 * @param title Title, e.g. "No songs".
 * @param modifier Modifier (defaults to filling the available space).
 * @param subtitle Optional explanation.
 * @param icon Optional decorative icon above the title.
 * @param action Optional way out of a gate state the page cannot fill on its own (Select
 *   Player, Go Back, Retry while a player syncs). Never a Reset Filters button (#377).
 */
@Composable
fun FestivalEmptyState(
    title: String,
    modifier: Modifier = Modifier.fillMaxSize(),
    subtitle: String? = null,
    icon: (@Composable () -> Unit)? = null,
    action: (@Composable () -> Unit)? = null,
) {
    Column(
        modifier = modifier.padding(horizontal = 24.dp, vertical = 48.dp).testTag("fst.empty-state"),
        verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        icon?.invoke()
        Text(
            title,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
            color = BrandTokens.textPrimary,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth().semantics { heading() },
        )
        if (subtitle != null) {
            Text(subtitle, style = MaterialTheme.typography.bodyLarge, color = BrandTokens.textPrimary, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        }
        action?.invoke()
    }
}

/**
 * [FestivalEmptyState] as a lazy-list item that fills the list's viewport height, so it sits
 * in the vertical centre of the page rather than just below the list's header rows. Given the
 * list's [state], it fills only the region the items around it leave ([rememberEmptyRegion]).
 *
 * @param title Title.
 * @param subtitle Optional explanation.
 * @param key Item key.
 * @param tag Extra test tag for the item (e.g. `fst.songs.empty`).
 * @param icon Optional decorative icon.
 * @param state The list's state, when other items (notices, controls) share the list.
 */
fun LazyListScope.festivalEmptyStateItem(
    title: String,
    subtitle: String? = null,
    key: Any = "empty",
    tag: String? = null,
    icon: (@Composable () -> Unit)? = null,
    state: LazyListState? = null,
) {
    item(key = key, contentType = "empty") {
        val height = if (state != null) Modifier.fillEmptyRegion(rememberEmptyRegion(state, key)) else Modifier.fillParentMaxHeight()
        EmptyStateItem(title, subtitle, tag, icon, height)
    }
}

@Composable
private fun EmptyStateItem(title: String, subtitle: String?, tag: String?, icon: (@Composable () -> Unit)?, height: Modifier) {
    Box(Modifier.fillMaxWidth().then(height).then(if (tag != null) Modifier.testTag(tag) else Modifier)) {
        FestivalEmptyState(title, Modifier.fillMaxSize(), subtitle, icon)
    }
}

/**
 * The height an empty-state item of a lazy list should take: the visible region the items
 * before it (page controls) and after it leave ([EmptyRegion]), so [FestivalEmptyState] centres
 * in the usable result region at every window height (pattern `empty-error-states` R2, #377).
 * Pair with [fillEmptyRegion] on the item's outermost modifier.
 *
 * @param state The list's state.
 * @param key The empty-state item's key.
 * @return Height in px, null until the item has been laid out once.
 */
@Composable
fun rememberEmptyRegion(state: LazyListState, key: Any): State<Int?> = remember(state, key) {
    // Derived, so the item remeasures only when the region changes, not on every layout pass.
    derivedStateOf {
        val info = state.layoutInfo
        val index = info.visibleItemsInfo.firstOrNull { it.key == key }?.index ?: return@derivedStateOf null
        EmptyRegion.height(info.visibleItemsInfo.map { EmptyRegion.Item(it.index, it.offset, it.offset + it.size) }, index, info.viewportEndOffset - info.afterContentPadding)
    }
}

/**
 * [rememberEmptyRegion] for a full-span empty-state item of a vertical lazy grid.
 *
 * @param state The grid's state.
 * @param key The empty-state item's key.
 * @return Height in px, null until the item has been laid out once.
 */
@Composable
fun rememberEmptyRegion(state: LazyGridState, key: Any): State<Int?> = remember(state, key) {
    derivedStateOf {
        val info = state.layoutInfo
        val index = info.visibleItemsInfo.firstOrNull { it.key == key }?.index ?: return@derivedStateOf null
        EmptyRegion.height(info.visibleItemsInfo.map { EmptyRegion.Item(it.index, it.offset.y, it.offset.y + it.size.height) }, index, info.viewportEndOffset - info.afterContentPadding)
    }
}

/**
 * Gives a lazy item exactly the [region] height (at least its content's height, so large text
 * scrolls rather than clips); before the first layout it keeps its natural height.
 *
 * @param region From [rememberEmptyRegion].
 */
fun Modifier.fillEmptyRegion(region: State<Int?>): Modifier = layout { measurable, constraints ->
    val target = region.value
    val placeable = if (target == null) {
        measurable.measure(constraints)
    } else {
        val height = maxOf(target, measurable.minIntrinsicHeight(constraints.maxWidth)).coerceIn(constraints.minHeight, constraints.maxHeight)
        measurable.measure(constraints.copy(minHeight = height, maxHeight = height))
    }
    layout(placeable.width, placeable.height) { placeable.place(0, 0) }
}

// endregion
