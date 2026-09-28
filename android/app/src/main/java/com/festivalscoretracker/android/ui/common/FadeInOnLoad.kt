package com.festivalscoretracker.android.ui.common

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility

// region Fade in on load

/**
 * Fade content in (with the web's short upward drift, `fadeInUp`) when it finishes
 * loading, like the web's staggered row entrances.
 *
 * Content that is already loaded the first time this modifier is composed (a cached
 * card, or a row scrolled back into view) appears immediately, as the web skips its
 * animation for cached data. Remove animations / Reduce Motion
 * ([LocalFestivalAccessibility]) shows content at once. The animated values are read
 * only in the graphics layer, so the fade never recomposes the content.
 *
 * Place it on a container that stays composed while loading (the skeleton lives
 * outside it), so it sees the loading → loaded transition.
 *
 * @param isLoaded Whether the content is ready to show.
 * @param delayMillis Delay before the fade starts (stagger between siblings).
 * @return Modifier.
 */
fun Modifier.festivalFadeIn(isLoaded: Boolean, delayMillis: Int = 0): Modifier = composed {
    val reduceMotion = LocalFestivalAccessibility.current.reduceMotion
    val progress = remember { Animatable(if (isLoaded) 1f else 0f) }
    LaunchedEffect(isLoaded, reduceMotion) {
        when {
            !isLoaded -> progress.snapTo(0f)
            reduceMotion -> progress.snapTo(1f)
            else -> progress.animateTo(1f, tween(FADE_IN_MILLIS, delayMillis, FastOutSlowInEasing))
        }
    }
    val drift = FADE_IN_DRIFT_DP.dp
    graphicsLayer {
        val value = fadeInAlpha(progress.value, isLoaded, reduceMotion)
        alpha = value
        translationY = (1f - value) * drift.toPx()
    }
}

/**
 * Opacity drawn for a fade: fully shown under Reduce Motion once loaded, else the
 * animation's progress.
 *
 * @param progress Animation progress, 0 to 1.
 * @param isLoaded Whether the content is ready.
 * @param reduceMotion Remove animations / Reduce Motion.
 * @return Alpha.
 */
internal fun fadeInAlpha(progress: Float, isLoaded: Boolean, reduceMotion: Boolean): Float =
    if (reduceMotion && isLoaded) 1f else progress.coerceIn(0f, 1f)

/**
 * Whether freshly loaded content should now be shown: false for one frame after a
 * loading to loaded transition (so [festivalFadeIn] on newly composed children sees
 * the change and fades them in), true at once for content that was already loaded.
 *
 * @param isLoaded Whether the content is ready.
 * @return Value to pass to [festivalFadeIn].
 */
@Composable
fun rememberRevealed(isLoaded: Boolean): Boolean {
    var revealed by remember { mutableStateOf(isLoaded) }
    LaunchedEffect(isLoaded) { revealed = isLoaded }
    return revealed
}

/**
 * Stagger delay for the item at [index] (web `staggerDelay`), capped so long lists
 * finish promptly.
 *
 * @param index Zero-based sibling index.
 * @return Delay in milliseconds.
 */
fun fadeInStagger(index: Int): Int = index.coerceIn(0, FADE_IN_MAX_STAGGERED) * FADE_IN_STAGGER_MILLIS

/** Fade duration (web `FADE_DURATION`). */
const val FADE_IN_MILLIS = 400

/** Delay between staggered siblings (web `STAGGER_INTERVAL`). */
const val FADE_IN_STAGGER_MILLIS = 125

/** Siblings after this index start together. */
private const val FADE_IN_MAX_STAGGERED = 12

/** Upward drift at the start of the fade (web `fadeInUp`). */
private const val FADE_IN_DRIFT_DP = 8

// endregion
