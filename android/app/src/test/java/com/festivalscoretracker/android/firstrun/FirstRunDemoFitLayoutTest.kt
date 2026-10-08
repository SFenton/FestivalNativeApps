package com.festivalscoretracker.android.firstrun

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.ui.firstrun.DemoFitFirst
import com.festivalscoretracker.android.ui.firstrun.DemoFrame
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** The First Run demo frame's measured fit (issue #380, web `useSlideHeight`). */
@RunWith(AndroidJUnit4::class)
class FirstRunDemoFitLayoutTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun showsTheMostWholeRowsThatFitAndDropsTheProbes() {
        rule.setContent {
            Box(Modifier.width(300.dp)) {
                DemoFitFirst(listOf(5, 4, 3, 2, 1)) { rows ->
                    Column(Modifier.testTag("rows")) { repeat(rows) { Box(Modifier.height(60.dp).width(10.dp).testTag("row")) } }
                }
            }
        }
        rule.waitForIdle()
        assertEquals(3, rule.onAllNodesWithTag("row", useUnmergedTree = true).fetchSemanticsNodes().size)
        assertEquals(180f, rule.onNodeWithTag("rows", useUnmergedTree = true).fetchSemanticsNode().size.height / rule.density.density, 0.5f)
    }

    @Test
    fun showsTheLastCandidateWhenNoneFits() {
        rule.setContent {
            Box(Modifier.width(300.dp)) {
                DemoFitFirst(listOf(3, 2)) { rows -> Column { repeat(rows) { Box(Modifier.height(200.dp).width(10.dp).testTag("row")) } } }
            }
        }
        rule.waitForIdle()
        assertEquals(2, rule.onAllNodesWithTag("row", useUnmergedTree = true).fetchSemanticsNodes().size)
    }

    @Test
    fun frameScalesAnOverflowingDemoToTheFrame() {
        rule.setContent {
            Box(Modifier.width(300.dp).testTag("host")) { DemoFrame { Box(Modifier.height(440.dp).width(300.dp)) } }
        }
        rule.waitForIdle()
        assertEquals(220f, rule.onNodeWithTag("host").fetchSemanticsNode().size.height / rule.density.density, 0.5f)
    }

    @Test
    fun frameLeavesAFittingDemoAlone() {
        rule.setContent {
            Box(Modifier.width(300.dp).testTag("host")) { DemoFrame { Box(Modifier.height(120.dp).width(300.dp)) } }
        }
        rule.waitForIdle()
        assertEquals(120f, rule.onNodeWithTag("host").fetchSemanticsNode().size.height / rule.density.density, 0.5f)
    }
}
