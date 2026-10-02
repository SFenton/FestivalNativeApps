package com.festivalscoretracker.android.presentation

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.runtime.MonotonicFrameClock
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SteppedFrameClockTest {
    // region Fixtures

    /** A display clock on virtual time: frames land on every [vsyncMs] boundary and are recorded. */
    private class VsyncClock(private val scheduler: TestCoroutineScheduler, private val vsyncMs: Long) : MonotonicFrameClock {
        val frames = sortedSetOf<Long>()

        override suspend fun <R> withFrameNanos(onFrame: (frameTimeNanos: Long) -> R): R {
            val now = scheduler.currentTime
            val next = (now / vsyncMs + 1) * vsyncMs
            delay(next - now)
            val nanos = next * NANOS_PER_MS
            frames += nanos
            return onFrame(nanos)
        }
    }

    private fun TestCoroutineScheduler.nanos(): Long = currentTime * NANOS_PER_MS

    // endregion

    @Test
    fun thirtyFpsStepsSampleAOneSecondAnimationAboutThirtyTimesOnA125HzDisplay() = runTest {
        val display = VsyncClock(testScheduler, vsyncMs = 8)
        val stepped = SteppedFrameClock(display, BackgroundPolicy.FRAME_INTERVAL_NANOS) { testScheduler.nanos() }
        val value = Animatable(0f)
        withContext(stepped) { value.animateTo(1f, tween(1_000, easing = LinearEasing)) }
        assertEquals(1f, value.value)
        assertTrue("frames=${display.frames.size}", display.frames.size in 29..33)
        val gaps = display.frames.zipWithNext { a, b -> b - a }
        assertTrue("min gap ${gaps.min()}", gaps.drop(1).all { it >= 24 * NANOS_PER_MS })
    }

    @Test
    fun unsteppedAnimationsRunOnEveryVsync() = runTest {
        val display = VsyncClock(testScheduler, vsyncMs = 8)
        val value = Animatable(0f)
        withContext(display) { value.animateTo(1f, tween(1_000, easing = LinearEasing)) }
        assertTrue("frames=${display.frames.size}", display.frames.size >= 120)
    }

    @Test
    fun separateSteppedAnimationsShareTheGridFrames() = runTest {
        val display = VsyncClock(testScheduler, vsyncMs = 8)
        val drift = Animatable(0f)
        val fade = Animatable(0f)
        val a = launch { withContext(SteppedFrameClock(display, BackgroundPolicy.FRAME_INTERVAL_NANOS) { testScheduler.nanos() }) { drift.animateTo(1f, tween(2_000, easing = LinearEasing)) } }
        delay(500)
        val b = launch { withContext(SteppedFrameClock(display, BackgroundPolicy.FRAME_INTERVAL_NANOS) { testScheduler.nanos() }) { fade.animateTo(1f, tween(1_000)) } }
        a.join()
        b.join()
        assertTrue("frames=${display.frames.size}", display.frames.size in 58..66)
    }

    @Test
    fun waitTargetsTheNextGridPointLessAQuarterInterval() {
        val interval = 40L
        assertEquals(30L, SteppedFrameClock.waitNanos(lastFrameNanos = 40, nowNanos = 40, intervalNanos = interval))
        assertEquals(30L, SteppedFrameClock.waitNanos(lastFrameNanos = 36, nowNanos = 40, intervalNanos = interval))
        assertEquals(-5L, SteppedFrameClock.waitNanos(lastFrameNanos = 40, nowNanos = 75, intervalNanos = interval))
    }

    @Test(expected = IllegalArgumentException::class)
    fun waitRejectsANonPositiveInterval() {
        SteppedFrameClock.waitNanos(0, 0, 0)
    }

    private companion object {
        const val NANOS_PER_MS = 1_000_000L
    }
}
