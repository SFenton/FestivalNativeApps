package com.festivalscoretracker.android.ui.quicklinks

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.quicklinks.QuickLinkSection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** [rememberQuickLinks] keeps one controller per list while its title and sections change. */
@RunWith(AndroidJUnit4::class)
class QuickLinksControllerUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun titleChangeKeepsTheControllerAndUpdatesItsState() {
        val title = mutableStateOf("Title Quick Links")
        val sections = mutableStateOf(emptyList<QuickLinkSection>())
        val seen = mutableListOf<QuickLinksController>()
        rule.setContent {
            val controller = rememberQuickLinks(rememberLazyListState(), title.value, sections.value) { null }
            seen += controller
        }
        rule.waitForIdle()
        val first = seen.last()
        assertFalse(first.available)

        // Songs: the saved Duration sort can arrive after the catalogue (title and sections change).
        title.value = "Duration Quick Links"
        sections.value = listOf(QuickLinkSection("duration:1to2", "1-2 min"), QuickLinkSection("duration:4to5", "4-5 min"))
        rule.waitForIdle()

        // The floating toolbar keeps the controller it first composed, so it must be this one.
        assertSame(first, seen.last())
        assertEquals("Duration Quick Links", first.title)
        assertTrue(first.available)
    }

    @Test
    fun aJumpStaysLandedWhileTheSectionAboveItGrows() {
        // Player Profile (#106): the card above the target composes on the jump, then its Rank History
        // loads and it grows. As the lazy list's scroll anchor it pushed the target out of view.
        val grown = mutableStateOf(false)
        val sections = (0 until 6).map { QuickLinkSection("s$it", "Section $it") }
        lateinit var controller: QuickLinksController
        lateinit var state: LazyListState
        rule.setContent {
            state = rememberLazyListState()
            controller = rememberQuickLinks(state, "Quick Links", sections) { id -> id.removePrefix("s").toInt() }
            LazyColumn(state = state, modifier = Modifier.height(400.dp)) {
                items(6) { index -> Box(Modifier.fillMaxWidth().height(if (index == 2 && grown.value) 700.dp else 150.dp)) }
            }
        }
        rule.runOnIdle { controller.jump("s3") }
        rule.waitForIdle()
        val landing = with(rule.density) { 32.dp.roundToPx() }
        assertEquals(landing, state.layoutInfo.visibleItemsInfo.first { it.index == 3 }.offset)

        rule.runOnIdle { grown.value = true }
        rule.waitForIdle()

        val target = state.layoutInfo.visibleItemsInfo.firstOrNull { it.index == 3 }
        assertEquals(landing, target?.offset)
        assertEquals("s3", controller.activeId)
    }
}
