package com.festivalscoretracker.android.ui.background

import android.net.ConnectivityManager
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.SingletonImageLoader
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import com.festivalscoretracker.android.presentation.BackgroundController
import com.festivalscoretracker.android.presentation.BackgroundMode
import com.festivalscoretracker.android.presentation.BackgroundPolicy
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import kotlin.math.abs
import kotlinx.coroutines.delay

// region Background host

/**
 * The one shared album-art backdrop, hosted once behind the whole shell so it
 * never restarts across tabs or pushes (`.agents/controls/artwork-background/spec.md`).
 *
 * Performance: the cover index changes every 5 s (one small recomposition); the
 * zoom/pan animates inside `graphicsLayer`, so frames only re-draw a layer.
 * Decorative: hidden from accessibility and never takes taps. Data saver shows
 * no art and no dim layer; reduced motion or a backgrounded app shows one still cover.
 *
 * @param controller Shared backdrop state.
 * @param forceStill Debug override for stable screenshots.
 * @param modifier Modifier.
 */
@Composable
fun ArtworkBackground(controller: BackgroundController, forceStill: Boolean, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val covers by controller.covers.collectAsStateWithLifecycle()
    val focus by controller.focus.collectAsStateWithLifecycle()
    val lifecycleState by LocalLifecycleOwner.current.lifecycle.currentStateFlow.collectAsStateWithLifecycle()
    val reduceMotion = LocalFestivalAccessibility.current.reduceMotion
    val dataSaver = remember {
        context.getSystemService(ConnectivityManager::class.java)?.restrictBackgroundStatus ==
            ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED
    }
    val mode = BackgroundPolicy.mode(
        systemReduceMotion = reduceMotion || forceStill,
        appReduceMotion = false,
        dataSaver = dataSaver,
        visible = lifecycleState.isAtLeast(Lifecycle.State.RESUMED),
    )
    Box(modifier.fillMaxSize().background(BrandTokens.appBackground).clearAndSetSemantics { }) {
        if (mode == BackgroundMode.None) return@Box
        var index by remember(covers) { mutableIntStateOf(0) }
        var failures by remember(covers) { mutableIntStateOf(0) }
        val animating = mode == BackgroundMode.Animated && focus == null
        LaunchedEffect(covers, animating) {
            if (!animating || covers.size < 2) return@LaunchedEffect
            while (true) {
                delay(BackgroundPolicy.DWELL_MS)
                index = (index + 1) % covers.size
            }
        }
        LaunchedEffect(covers, index, animating) {
            if (animating && covers.size > 1) {
                val next = covers[(index + 1) % covers.size]
                SingletonImageLoader.get(context).enqueue(ImageRequest.Builder(context).data(next).build())
            }
        }
        val target = focus ?: covers.getOrNull(index)
        Crossfade(targetState = target, animationSpec = tween(BackgroundPolicy.CROSSFADE_MS), label = "artwork") { url ->
            if (url != null) {
                KenBurnsImage(url = url, animate = animating) {
                    if (focus == null && failures < BackgroundPolicy.FAILURE_BUDGET && covers.size > 1) {
                        failures++
                        index = (index + 1) % covers.size
                    }
                }
            }
        }
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = BackgroundPolicy.DIM_ALPHA)))
    }
}

/**
 * One cover with a slow zoom/pan driven in the draw phase.
 *
 * @param url Cover URL.
 * @param animate Whether to zoom/pan.
 * @param onError Called when the cover fails to load (skipped, never replaced by fake art).
 */
@Composable
private fun KenBurnsImage(url: String, animate: Boolean, onError: () -> Unit) {
    val preset = BackgroundPolicy.PRESETS[abs(url.hashCode()) % BackgroundPolicy.PRESETS.size]
    val progress = remember(url) { Animatable(0f) }
    val density = LocalDensity.current
    LaunchedEffect(url, animate) {
        if (animate) progress.animateTo(1f, tween(BackgroundPolicy.ZOOM_MS, easing = LinearEasing))
    }
    AsyncImage(
        model = url,
        contentDescription = null,
        contentScale = ContentScale.Crop,
        onError = { onError() },
        modifier = Modifier
            .fillMaxSize()
            .graphicsLayer {
                val t = progress.value
                val scale = 1f + (preset.scale - 1f) * t
                scaleX = scale
                scaleY = scale
                translationX = with(density) { (preset.dx * t).dp.toPx() }
                translationY = with(density) { (preset.dy * t).dp.toPx() }
            },
    )
}

// endregion
