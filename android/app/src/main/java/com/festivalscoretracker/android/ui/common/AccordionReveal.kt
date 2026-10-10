package com.festivalscoretracker.android.ui.common

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.Ease
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.festivalscoretracker.android.core.shell.AccordionMotion
import com.festivalscoretracker.android.core.shell.AccordionStep
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility

// region Accordion reveal

/**
 * The one accordion transition (`load-transition` R10, owner-approved variant, issue #561):
 * every expandable section, panel or detail row in the app reveals through this. Opening grows
 * the height, then fades the content in; closing fades the content out, then collapses the
 * height ([AccordionMotion]). Under system or in-app reduced motion it opens and closes at
 * once (R6). A toggle mid-way reverses from where the content is.
 *
 * The header that opens it keeps its own role and Expanded/Collapsed state; this only moves
 * the content.
 *
 * @param visible The section is open.
 * @param modifier Modifier for the revealed container.
 * @param content The section's content.
 */
@Composable
fun AccordionReveal(visible: Boolean, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val reduceMotion = LocalFestivalAccessibility.current.reduceMotion
    val enter = remember(reduceMotion) { accordionEnter(reduceMotion) }
    val exit = remember(reduceMotion) { accordionExit(reduceMotion) }
    AnimatedVisibility(visible = visible, modifier = modifier, enter = enter, exit = exit) { content() }
}

/**
 * [AccordionReveal] for content built from a value that clears when the section closes (a
 * picked instrument, a selected bar): the last value stays on screen while the content fades
 * out and collapses (web `CollapseOnExit` `lastChildrenRef`).
 *
 * @param value The value to show, or null when closed.
 * @param modifier Modifier for the revealed container.
 * @param content The content for a value.
 */
@Composable
fun <T : Any> AccordionRevealOf(value: T?, modifier: Modifier = Modifier, content: @Composable (T) -> Unit) {
    val last = remember { LastValue<T>() }
    if (value != null) last.value = value
    val shown = value ?: last.value
    AccordionReveal(visible = value != null, modifier = modifier) { shown?.let { content(it) } }
}

/** Plain holder: the closing content reads it during composition, so it needn't be state. */
private class LastValue<T : Any> {
    var value: T? = null
}

/**
 * The opening transition for [AccordionMotion.opening].
 *
 * @param reduceMotion Remove animations / Reduce Motion.
 * @return Height then fade, or none under reduced motion.
 */
internal fun accordionEnter(reduceMotion: Boolean): EnterTransition {
    val steps = AccordionMotion.opening(reduceMotion)
    val fade = AccordionMotion.step(steps, AccordionStep.Kind.Fade)
    val height = AccordionMotion.step(steps, AccordionStep.Kind.Height)
    var enter = fade?.let { fadeIn(tween(it.durationMillis, it.delayMillis, Ease)) } ?: EnterTransition.None
    if (height != null) enter = expandVertically(tween(height.durationMillis, height.delayMillis, Ease), expandFrom = Alignment.Top) + enter
    return enter
}

/**
 * The closing transition for [AccordionMotion.closing].
 *
 * @param reduceMotion Remove animations / Reduce Motion.
 * @return Fade then height, or none under reduced motion.
 */
internal fun accordionExit(reduceMotion: Boolean): ExitTransition {
    val steps = AccordionMotion.closing(reduceMotion)
    val fade = AccordionMotion.step(steps, AccordionStep.Kind.Fade)
    val height = AccordionMotion.step(steps, AccordionStep.Kind.Height)
    var exit = fade?.let { fadeOut(tween(it.durationMillis, it.delayMillis, Ease)) } ?: ExitTransition.None
    if (height != null) exit += shrinkVertically(tween(height.durationMillis, height.delayMillis, Ease), shrinkTowards = Alignment.Top)
    return exit
}

// endregion
