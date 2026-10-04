package com.festivalscoretracker.android.ui.background

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.util.Log
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MonotonicFrameClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsPropertyKey
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.ImageLoader
import coil3.SingletonImageLoader
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import com.festivalscoretracker.android.presentation.BackgroundController
import com.festivalscoretracker.android.presentation.BackgroundMode
import com.festivalscoretracker.android.presentation.BackgroundPolicy
import com.festivalscoretracker.android.presentation.CoverFailurePacer
import com.festivalscoretracker.android.presentation.ModalCoverage
import com.festivalscoretracker.android.presentation.SteppedFrameClock
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import kotlin.coroutines.coroutineContext
import kotlin.math.abs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
// region Background host

/** Test ID of the backdrop (`contracts/product.json` `artwork-background`). */
const val ARTWORK_BACKGROUND_TAG = "fst.shell.artwork-background"

/** Test-only semantics: the contract state ID ([com.festivalscoretracker.android.presentation.BackgroundState.id]). Not exposed to accessibility services. */
internal val ArtworkBackgroundStateKey = SemanticsPropertyKey<String>("ArtworkBackgroundState")

/** Test-only semantics: the cover URL in front, or "" for none. */
internal val ArtworkBackgroundCoverKey = SemanticsPropertyKey<String>("ArtworkBackgroundCover")

private const val LOG_TAG = "FST_ART"

/**
 * The one shared album-art backdrop, hosted once behind the whole shell so it
 * never restarts across tabs or pushes (`.agents/controls/artwork-background/spec.md`).
 *
 * Performance: the cover index changes every 5 s (one small recomposition); the
 * zoom/pan and crossfade animate inside `graphicsLayer` on a 30 fps
 * [SteppedFrameClock], so between steps nothing requests a frame. While a Festival
 * dialog or sheet is open ([ModalCoverage]) the backdrop holds its frame, like a
 * backgrounded app (issue #83). Decorative: hidden from accessibility and never takes
 * taps. Data saver shows no art and no dim; reduced motion shows one still cover. Data
 * saver and the system animator scale are followed live (issue #124).
 *
 * @param controller Shared backdrop state.
 * @param forceStill Debug override for stable screenshots, or Disable Animated Artwork.
 * @param modifier Modifier.
 * @param coverage Open-modal counter.
 * @param imageLoader Cover loader (the app's bounded in-memory Coil loader by default).
 */
@Composable
fun ArtworkBackground(
    controller: BackgroundController,
    forceStill: Boolean,
    modifier: Modifier = Modifier,
    coverage: ModalCoverage = ModalCoverage.shared,
    imageLoader: ImageLoader = SingletonImageLoader.get(LocalContext.current),
) {
    val context = LocalContext.current
    val covers by controller.covers.collectAsStateWithLifecycle()
    val focus by controller.focus.collectAsStateWithLifecycle()
    val openModals by coverage.openCount.collectAsStateWithLifecycle()
    val lifecycleState by LocalLifecycleOwner.current.lifecycle.currentStateFlow.collectAsStateWithLifecycle()
    val reduceMotion = LocalFestivalAccessibility.current.reduceMotion
    val dataSaver = rememberDataSaver(context, lifecycleState)
    val visible = lifecycleState.isAtLeast(Lifecycle.State.RESUMED)
    val mode = BackgroundPolicy.mode(
        systemReduceMotion = reduceMotion,
        appReduceMotion = forceStill,
        dataSaver = dataSaver,
        visible = visible,
        covered = openModals > 0,
    )
    val pacer = remember(covers) { CoverFailurePacer() }
    var index by remember(covers) { mutableIntStateOf(0) }
    val target = if (mode == BackgroundMode.None) null else focus ?: covers.getOrNull(index)
    val state = BackgroundPolicy.state(
        systemReduceMotion = reduceMotion,
        appReduceMotion = forceStill,
        dataSaver = dataSaver,
        visible = visible,
        covered = openModals > 0,
        hasArt = focus != null || covers.isNotEmpty(),
        focused = focus != null,
    )
    Box(
        modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .clearAndSetSemantics {
                testTag = ARTWORK_BACKGROUND_TAG
                this[ArtworkBackgroundStateKey] = state.id
                this[ArtworkBackgroundCoverKey] = target.orEmpty()
            },
    ) {
        if (mode == BackgroundMode.None) return@Box
        val animating = mode == BackgroundMode.Animated && focus == null
        val motionAllowed = !reduceMotion && !forceStill
        LaunchedEffect(covers, animating) {
            if (!animating || covers.size < 2) return@LaunchedEffect
            while (!pacer.exhausted) {
                delay(BackgroundPolicy.DWELL_MS)
                if (pacer.exhausted) break
                pacer.onDeadline()
                index = (index + 1) % covers.size
            }
        }
        LaunchedEffect(covers, index, animating) {
            if (animating && covers.size > 1) {
                val next = covers[(index + 1) % covers.size]
                imageLoader.enqueue(ImageRequest.Builder(context).data(next).build())
            }
        }
        // Brand surface never dims; only the art is multiplied (= black 0.7 over opaque art).
        val dim = remember {
            val lightness = BackgroundPolicy.ART_LIGHTNESS
            ColorFilter.tint(Color(lightness, lightness, lightness), BlendMode.Modulate)
        }
        SteppedCrossfade(target) { url ->
            KenBurnsImage(url = url, animate = animating, drift = motionAllowed && url != focus, imageLoader = imageLoader, dim = dim) { error ->
                val carousel = focus == null && url in covers
                val skip = carousel && covers.size > 1 && url == covers.getOrNull(index) && pacer.onFailure()
                Log.w(LOG_TAG, "Cover failed (${if (skip) "skipping" else "waiting"}, ${pacer.failureCount} in pool): $url", error)
                if (skip) index = (index + 1) % covers.size
            }
        }
    }
}

/**
 * Whether Data Saver restricts this app's background data, followed live: the
 * `ACTION_RESTRICT_BACKGROUND_CHANGED` broadcast (sent to registered receivers only) plus a
 * re-read whenever the lifecycle state changes.
 *
 * @param context Any context.
 * @param lifecycleState Current lifecycle state (re-read key).
 * @return True while Data Saver is on for this app.
 */
@Composable
private fun rememberDataSaver(context: Context, lifecycleState: Lifecycle.State): Boolean {
    var restricted by remember { mutableStateOf(dataSaverOn(context)) }
    LaunchedEffect(lifecycleState) { restricted = dataSaverOn(context) }
    DisposableEffect(context) {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(receiverContext: Context, intent: Intent) {
                restricted = dataSaverOn(context)
            }
        }
        ContextCompat.registerReceiver(
            context,
            receiver,
            IntentFilter(ConnectivityManager.ACTION_RESTRICT_BACKGROUND_CHANGED),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        onDispose { context.unregisterReceiver(receiver) }
    }
    return restricted
}

/**
 * Reads Data Saver for this app.
 *
 * @param context Any context.
 * @return True when background data is restricted for this app.
 */
private fun dataSaverOn(context: Context): Boolean =
    context.getSystemService(ConnectivityManager::class.java)?.restrictBackgroundStatus ==
        ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED

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
 * @param animate Whether to zoom/pan now.
 * @param drift Whether this cover drifts at all; false (reduced motion, song cover) draws it untransformed.
 * @param imageLoader Cover loader.
 * @param dim Art-only dimming filter.
 * @param onError Called with the cause when the cover fails to load (skipped, never replaced by fake art).
 */
@Composable
private fun KenBurnsImage(
    url: String,
    animate: Boolean,
    drift: Boolean,
    imageLoader: ImageLoader,
    dim: ColorFilter,
    onError: (Throwable) -> Unit,
) {
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
        imageLoader = imageLoader,
        contentScale = ContentScale.Crop,
        colorFilter = dim,
        onError = { onError(it.result.throwable) },
        modifier = Modifier
            .fillMaxSize()
            .graphicsLayer {
                if (!drift) return@graphicsLayer
                val t = progress.value
                val scale = preset.scaleAt(t)
                scaleX = scale
                scaleY = scale
                translationX = with(density) { preset.offsetXAt(t).dp.toPx() }
                translationY = with(density) { preset.offsetYAt(t).dp.toPx() }
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
