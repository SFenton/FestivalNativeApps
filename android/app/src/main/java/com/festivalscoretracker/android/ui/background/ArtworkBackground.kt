package com.festivalscoretracker.android.ui.background

import android.net.ConnectivityManager
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MonotonicFrameClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
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
import com.festivalscoretracker.android.presentation.ModalCoverage
import com.festivalscoretracker.android.presentation.SteppedFrameClock
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import kotlin.coroutines.coroutineContext
import kotlin.math.abs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

// region Background host

/**
 * The one shared album-art backdrop, hosted once behind the whole shell so it
 * never restarts across tabs or pushes (`.agents/controls/artwork-background/spec.md`).
 *
 * Performance: the cover index changes every 5 s (one small recomposition); the
 * zoom/pan and crossfade animate inside `graphicsLayer` on a 30 fps
 * [SteppedFrameClock], so between steps nothing requests a frame. While a Festival
 * dialog or sheet is open ([ModalCoverage]) the backdrop holds its frame, like a
 * backgrounded app (issue #83). Decorative: hidden from accessibility and never takes
 * taps. Data saver shows no art and no dim layer; reduced motion shows one still cover.
 *
 * @param controller Shared backdrop state.
 * @param forceStill Debug override for stable screenshots.
 * @param modifier Modifier.
 * @param coverage Open-modal counter.
 */
@Composable
fun ArtworkBackground(
    controller: BackgroundController,
    forceStill: Boolean,
    modifier: Modifier = Modifier,
    coverage: ModalCoverage = ModalCoverage.shared,
) {
    val context = LocalContext.current
    val covers by controller.covers.collectAsStateWithLifecycle()
    val focus by controller.focus.collectAsStateWithLifecycle()
    val openModals by coverage.openCount.collectAsStateWithLifecycle()
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
        covered = openModals > 0,
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
        SteppedCrossfade(target) { url ->
            KenBurnsImage(url = url, animate = animating) {
                if (focus == null && failures < BackgroundPolicy.FAILURE_BUDGET && covers.size > 1) {
                    failures++
                    index = (index + 1) % covers.size
                }
            }
        }
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = BackgroundPolicy.DIM_ALPHA)))
    }
}

/**
 * Fades [target] in over the previous cover on the 30 fps clock. Replaces Compose's
 * `Crossfade`, whose transition runs on the composition's every-vsync clock. Both
 * layers are keyed at one call site, so the outgoing cover keeps its zoom state.
 *
 * @param target Cover to show, or null for none.
 * @param content One cover.
 */
@Composable
private fun SteppedCrossfade(target: String?, content: @Composable (String) -> Unit) {
    var front by remember { mutableStateOf(target) }
    var back by remember { mutableStateOf<String?>(null) }
    val fade = remember { Animatable(1f) }
    LaunchedEffect(target) {
        if (target == front) return@LaunchedEffect
        back = front
        front = target
        fade.snapTo(0f)
        stepped { fade.animateTo(1f, tween(BackgroundPolicy.CROSSFADE_MS)) }
        back = null
    }
    for (url in listOfNotNull(back?.takeIf { it != front }, front)) {
        key(url) {
            val isFront = url == front
            Box(Modifier.fillMaxSize().graphicsLayer { alpha = if (isFront) fade.value else 1f }) { content(url) }
        }
    }
}

/**
 * One cover with a slow zoom/pan driven in the draw phase. Stopping holds the current
 * frame; resuming finishes the drift at its original speed.
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
        if (animate && progress.value < 1f) {
            stepped { progress.animateTo(1f, tween(BackgroundPolicy.remainingZoomMs(progress.value), easing = LinearEasing)) }
        }
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

/**
 * Runs [block] with animations sampled at the backdrop's 30 fps
 * ([BackgroundPolicy.FRAME_INTERVAL_NANOS]); the context's `MotionDurationScale` still applies.
 *
 * @param block Animation to run.
 * @return The block's result.
 */
private suspend fun <R> stepped(block: suspend CoroutineScope.() -> R): R {
    val parent = coroutineContext[MonotonicFrameClock] ?: return coroutineScope(block)
    return withContext(SteppedFrameClock(parent, BackgroundPolicy.FRAME_INTERVAL_NANOS), block)
}

// endregion
