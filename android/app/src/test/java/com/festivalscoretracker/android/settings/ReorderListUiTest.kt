package com.festivalscoretracker.android.settings

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.ui.settings.ReorderList
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** CHOpt column order: drag handles (web) plus the numbered up/down alternative. */
@RunWith(AndroidJUnit4::class)
class ReorderListUiTest {
    @get:Rule
    val rule = createComposeRule()

    private var order by mutableStateOf(listOf("Activation", "Beat", "Time", "Overdrive %"))

    private fun move(index: Int, offset: Int) {
        val list = order.toMutableList()
        val item = list.removeAt(index)
        list.add(index + offset, item)
        order = list
    }

    @Test
    fun dragHandleMovesARowDownTwoSlots() {
        rule.setContent { FestivalTheme { ReorderList(order, "order", ::move) } }
        val rowHeight = rule.onNodeWithTag("order.0").fetchSemanticsNode().size.height.toFloat()
        rule.onNodeWithTag("order.0.handle").performTouchInput {
            down(center)
            // Past the touch slop, then two row heights in small steps.
            repeat(20) { moveBy(androidx.compose.ui.geometry.Offset(0f, rowHeight * 2.2f / 20)) }
            up()
        }
        rule.waitForIdle()
        assertEquals(listOf("Beat", "Time", "Activation", "Overdrive %"), order)
    }

    @Test
    fun buttonsStillReorder() {
        rule.setContent { FestivalTheme { ReorderList(order, "order", ::move) } }
        rule.onNodeWithTag("order.1.up").performClick()
        rule.onNodeWithTag("order.3.up").performClick()
        rule.waitForIdle()
        assertEquals(listOf("Beat", "Activation", "Overdrive %", "Time"), order)
    }
}
