package com.festivalscoretracker.android.presentation

import androidx.compose.runtime.MonotonicFrameClock
import kotlin.math.roundToLong
import kotlinx.coroutines.delay

// region Stepped frame clock

/**
 * A [MonotonicFrameClock] that hands frames to its animations at most once per
 * [intervalNanos], on a grid shared by every instance with the same interval.
 *
 * Wrapping an animation in `withContext(SteppedFrameClock(parent, …))` makes Compose's
 * `Animatable`/`animate*` sample it at that rate instead of on every display vsync
 * (up to 120 Hz): between steps nothing requests a frame, so the UI thread and
 * RenderThread stay idle (issue #83, the Android side of iOS #28's 30 fps backdrop).
 * `MotionDurationScale` stays in the context, so animator scale and reduce motion
 * still apply. Because the waits target the same absolute grid, several stepped
 * animations (the outgoing and incoming zoom, the crossfade) share each frame.
 *
 * @property parent The composition's real frame clock.
 * @property intervalNanos Minimum time between frames.
 * @property nanoTime Monotonic time source in the parent's time base (`System.nanoTime` on Android).
 */
class SteppedFrameClock(
    private val parent: MonotonicFrameClock,
    private val intervalNanos: Long,
    private val nanoTime: () -> Long = System::nanoTime,
) : MonotonicFrameClock {
    private var lastFrameNanos: Long? = null

    override suspend fun <R> withFrameNanos(onFrame: (frameTimeNanos: Long) -> R): R {
        lastFrameNanos?.let { last ->
            val wait = waitNanos(last, nanoTime(), intervalNanos)
            if (wait > 0) delay((wait + NANOS_PER_MILLI - 1) / NANOS_PER_MILLI)
        }
        return parent.withFrameNanos { frameTime ->
            lastFrameNanos = frameTime
            onFrame(frameTime)
        }
    }

    companion object {
        private const val NANOS_PER_MILLI = 1_000_000L

        /**
         * How long to wait before requesting the next frame: until the grid point after the
         * one [lastFrameNanos] landed on, less a quarter interval so the request catches
         * the vsync at (or just before) that point.
         *
         * @param lastFrameNanos Time of the last delivered frame.
         * @param nowNanos Current time.
         * @param intervalNanos Grid interval (> 0).
         * @return Nanoseconds to wait; 0 or less means request a frame now.
         */
        fun waitNanos(lastFrameNanos: Long, nowNanos: Long, intervalNanos: Long): Long {
            require(intervalNanos > 0) { "intervalNanos must be positive" }
            val slot = (lastFrameNanos.toDouble() / intervalNanos).roundToLong()
            val next = (slot + 1) * intervalNanos - intervalNanos / 4
            return next - nowNanos
        }
    }
}

// endregion
