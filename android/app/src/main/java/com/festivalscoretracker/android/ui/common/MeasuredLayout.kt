package com.festivalscoretracker.android.ui.common

import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableFloatState
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.isSpecified

// region Measured layout

/*
 * Layout measurements (a container's window position or width, a card's row width) that pick a
 * column plan or hinge split. They are saved with the destination: Navigation recomposes a page
 * when Back returns to it, and a plain `remember` would draw that first frame with no measurement,
 * so the grid fell back to one column and rows dropped or restacked columns for a frame before
 * snapping back (issues #82, #185). After rotation or a posture change the restored value is
 * stale for one frame at most and is corrected by the next measurement, as before.
 */

/**
 * A saved measured length in pixels (or dp, as the caller defines).
 *
 * @param initial Value before the first measurement (NaN or 0 for "unknown").
 * @return State written from `onGloballyPositioned` / `onSizeChanged`.
 */
@Composable
fun rememberMeasuredPx(initial: Float): MutableFloatState = rememberSaveable { mutableFloatStateOf(initial) }

private val BoundsSaver = Saver<Pair<Int, Int>?, IntArray>(
    save = { bounds -> bounds?.let { (start, width) -> intArrayOf(start, width) } },
    restore = { saved -> saved[0] to saved[1] },
)

/**
 * A container's saved window start and width in pixels.
 *
 * @return State holding `(start, width)`, null before the first measurement.
 */
@Composable
fun rememberMeasuredBounds(): MutableState<Pair<Int, Int>?> =
    rememberSaveable(stateSaver = BoundsSaver) { mutableStateOf(null) }

private val OffsetSaver = Saver<Offset, FloatArray>(
    save = { offset -> if (offset.isSpecified) floatArrayOf(offset.x, offset.y) else null },
    restore = { saved -> Offset(saved[0], saved[1]) },
)

/**
 * A container's saved window origin in pixels.
 *
 * @param initial Origin before the first measurement.
 * @return State written from `onGloballyPositioned`.
 */
@Composable
fun rememberMeasuredOffset(initial: Offset): MutableState<Offset> =
    rememberSaveable(stateSaver = OffsetSaver) { mutableStateOf(initial) }

// endregion
