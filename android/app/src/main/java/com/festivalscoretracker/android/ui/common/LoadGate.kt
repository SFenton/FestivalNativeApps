package com.festivalscoretracker.android.ui.common

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyItemScope
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
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
 * @param content Page content.
 */
@Composable
fun FestivalLoadGate(ready: Boolean, modifier: Modifier = Modifier, label: String = "Loading", content: @Composable LoadGateScope.() -> Unit) {
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
        if (phase == LoadGatePhase.ContentIn) {
            val animate = LoadGatePolicy.animatesEntrance(sawSpinner, reduceMotion)
            var revealed by remember { mutableStateOf(!animate) }
            LaunchedEffect(Unit) { revealed = true }
            LoadGateScope(revealed).content()
        } else {
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
 * In a lazy list use [festivalEmptyStateItem] so it fills the viewport height.
 *
 * @param title Title, e.g. "No songs".
 * @param modifier Modifier (defaults to filling the available space).
 * @param subtitle Optional explanation.
 * @param icon Optional decorative icon above the title.
 */
@Composable
fun FestivalEmptyState(title: String, modifier: Modifier = Modifier.fillMaxSize(), subtitle: String? = null, icon: (@Composable () -> Unit)? = null) {
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
    }
}

/**
 * [FestivalEmptyState] as a lazy-list item that fills the list's viewport height, so it sits
 * in the vertical centre of the page rather than just below the list's header rows.
 *
 * @param title Title.
 * @param subtitle Optional explanation.
 * @param key Item key.
 * @param tag Extra test tag for the item (e.g. `fst.songs.empty`).
 * @param icon Optional decorative icon.
 */
fun LazyListScope.festivalEmptyStateItem(
    title: String,
    subtitle: String? = null,
    key: Any = "empty",
    tag: String? = null,
    icon: (@Composable () -> Unit)? = null,
) {
    item(key = key, contentType = "empty") { EmptyStateItem(title, subtitle, tag, icon) }
}

@Composable
private fun LazyItemScope.EmptyStateItem(title: String, subtitle: String?, tag: String?, icon: (@Composable () -> Unit)?) {
    Box(Modifier.fillParentMaxHeight().fillMaxWidth().then(if (tag != null) Modifier.testTag(tag) else Modifier)) {
        FestivalEmptyState(title, Modifier.fillMaxSize(), subtitle, icon)
    }
}

// endregion
