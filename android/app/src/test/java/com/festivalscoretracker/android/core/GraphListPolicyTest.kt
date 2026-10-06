package com.festivalscoretracker.android.core

import com.festivalscoretracker.android.core.shell.GraphListPhase
import com.festivalscoretracker.android.core.shell.GraphListPolicy
import org.junit.Assert.assertEquals
import org.junit.Test

/** The graph card list sequence (issue #169, web `useListAnimation`). */
class GraphListPolicyTest {
    @Test
    fun webTimings() {
        assertEquals(200, GraphListPolicy.OUT_BASE_MS)
        assertEquals(40, GraphListPolicy.OUT_STEP_MS)
        assertEquals(300, GraphListPolicy.IN_BASE_MS)
        assertEquals(60, GraphListPolicy.IN_STEP_MS)
        assertEquals(300, GraphListPolicy.HEIGHT_MS)
        assertEquals(150, GraphListPolicy.ROW_OUT_MS)
        assertEquals(300, GraphListPolicy.ROW_IN_MS)
    }

    @Test
    fun phaseLengthsGrowWithTheStagger() {
        assertEquals(0, GraphListPolicy.outMillis(0))
        assertEquals(200, GraphListPolicy.outMillis(1))
        assertEquals(360, GraphListPolicy.outMillis(5))
        assertEquals(0, GraphListPolicy.inMillis(0))
        assertEquals(300, GraphListPolicy.inMillis(1))
        assertEquals(540, GraphListPolicy.inMillis(5))
        assertEquals(160, GraphListPolicy.rowOutDelay(4))
        assertEquals(240, GraphListPolicy.rowInDelay(4))
        // Every row has finished fading out before the out phase ends.
        (1..5).forEach { n -> assertEquals(true, GraphListPolicy.rowOutDelay(n - 1) + GraphListPolicy.ROW_OUT_MS <= GraphListPolicy.outMillis(n)) }
    }

    @Test
    fun plans() {
        assertEquals(GraphListPolicy.Plan.Keep, GraphListPolicy.plan(same = true, shownCount = 5, reduceMotion = false))
        assertEquals(GraphListPolicy.Plan.Keep, GraphListPolicy.plan(same = true, shownCount = 5, reduceMotion = true))
        assertEquals(GraphListPolicy.Plan.Instant, GraphListPolicy.plan(same = false, shownCount = 5, reduceMotion = true))
        assertEquals(GraphListPolicy.Plan.Enter, GraphListPolicy.plan(same = false, shownCount = 0, reduceMotion = false))
        assertEquals(GraphListPolicy.Plan.Swap, GraphListPolicy.plan(same = false, shownCount = 2, reduceMotion = false))
    }

    @Test
    fun hiddenRowsSkipTheFadeOut() {
        assertEquals(360, GraphListPolicy.outWait(GraphListPhase.Idle, 5))
        assertEquals(360, GraphListPolicy.outWait(GraphListPhase.Out, 5))
        assertEquals(360, GraphListPolicy.outWait(GraphListPhase.In, 5))
        assertEquals(0, GraphListPolicy.outWait(GraphListPhase.Resize, 5))
    }

    @Test
    fun rowsDriftUpOutAndRiseIn() {
        assertEquals(0f, GraphListPolicy.rowDriftDp(GraphListPhase.Out, 1f), 0f)
        assertEquals(-8f, GraphListPolicy.rowDriftDp(GraphListPhase.Out, 0f), 0f)
        assertEquals(12f, GraphListPolicy.rowDriftDp(GraphListPhase.In, 0f), 0f)
        assertEquals(6f, GraphListPolicy.rowDriftDp(GraphListPhase.In, 0.5f), 0f)
        assertEquals(0f, GraphListPolicy.rowDriftDp(GraphListPhase.Idle, 0f), 0f)
        assertEquals(0f, GraphListPolicy.rowDriftDp(GraphListPhase.Resize, 0f), 0f)
    }
}
