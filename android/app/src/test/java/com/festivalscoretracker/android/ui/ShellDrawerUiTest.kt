package com.festivalscoretracker.android.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.ui.shell.DrawerContent
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** Drawer entries follow Settings (Hide Item Shop removes the Shop entry, like web/Apple/Windows). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class ShellDrawerUiTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun hideShopRemovesTheDrawerEntry() {
        rule.setContent { DrawerContent(emptyList(), FestivalSection.Songs, null, {}, {}, showShop = true) }
        rule.onNodeWithTag("fst.nav.drawer.shop").assertIsDisplayed()
        rule.onNodeWithTag("fst.nav.drawer.bands").assertIsDisplayed()
    }

    @Test
    fun hiddenShopHasNoEntry() {
        rule.setContent { DrawerContent(emptyList(), FestivalSection.Songs, null, {}, {}, showShop = false) }
        assertEquals(0, rule.onAllNodesWithTag("fst.nav.drawer.shop").fetchSemanticsNodes().size)
        rule.onNodeWithTag("fst.nav.drawer.bands").assertIsDisplayed()
    }
}
