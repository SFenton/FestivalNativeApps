package com.festivalscoretracker.android.ui.quicklinks

import androidx.activity.ComponentActivity
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.junit4.createAndroidComposeRule
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
}
