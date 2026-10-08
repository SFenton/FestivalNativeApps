package com.festivalscoretracker.android.settings

import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.settings.SettingsDetail
import com.festivalscoretracker.android.core.settings.SettingsDetailText
import com.festivalscoretracker.android.core.settings.SettingsPanes
import com.festivalscoretracker.android.ui.settings.settingsSections
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** List/detail Settings rules (issue #371). */
class SettingsPanesTest {
    @Test
    fun everyMultiOptionSectionIsADetailAndTheRestStayInTheList() {
        val sections = settingsSections(debug = true).map { it.id }
        val details = sections.mapNotNull { SettingsDetail.forSection(it) }
        assertEquals(
            listOf(
                SettingsDetail.ItemShop, SettingsDetail.ShowInstruments, SettingsDetail.ShowMetadata, SettingsDetail.Accessibility,
                SettingsDetail.Version, SettingsDetail.ServiceInfo, SettingsDetail.FirstRun, SettingsDetail.Licenses, SettingsDetail.PrivacyPolicy,
            ),
            details,
        )
        assertEquals(listOf("app-settings", "diagnostics", "reset"), sections.filter { SettingsDetail.forSection(it) == null })
        // Every section detail is a real section; App Settings options never replace a section.
        assertEquals(SettingsDetail.entries.filter { it.section }.map { it.id }.toSet(), details.map { it.id }.toSet())
        assertNull(SettingsDetail.forSection("path-default-view"))
    }

    @Test
    fun idsRoundTripAndRowTagsAreUnique() {
        SettingsDetail.entries.forEach { assertEquals(it, SettingsDetail.fromId(it.id)) }
        assertNull(SettingsDetail.fromId(null))
        assertNull(SettingsDetail.fromId("unknown"))
        assertEquals(SettingsDetail.entries.size, SettingsDetail.entries.map { it.rowTag }.toSet().size)
        // Licenses and Privacy Policy keep the tags their single-column rows always had.
        assertEquals("fst.settings.licenses", SettingsDetail.Licenses.rowTag)
        assertEquals("fst.settings.privacy-policy", SettingsDetail.PrivacyPolicy.rowTag)
        assertEquals("fst.settings.open.show-instruments", SettingsDetail.ShowInstruments.rowTag)
    }

    @Test
    fun dependentOptionsExistOnlyWhileTheirSwitchIsOn() {
        val defaults = AppSettings()
        assertNull(SettingsPanes.shown(SettingsDetail.SongRowOrder.id, defaults.copy(enableVisualOrder = false)))
        assertEquals(SettingsDetail.SongRowOrder, SettingsPanes.shown(SettingsDetail.SongRowOrder.id, defaults.copy(enableVisualOrder = true)))
        assertNull(SettingsPanes.shown(SettingsDetail.Leeway.id, defaults.copy(filterInvalidScores = false)))
        assertEquals(SettingsDetail.Leeway, SettingsPanes.shown(SettingsDetail.Leeway.id, defaults.copy(filterInvalidScores = true)))
        SettingsDetail.entries.filter { it != SettingsDetail.SongRowOrder && it != SettingsDetail.Leeway }.forEach {
            assertTrue(SettingsPanes.available(it, defaults))
            assertEquals(it, SettingsPanes.shown(it.id, defaults))
        }
    }

    @Test
    fun nothingSelectedShowsThePlaceholder() {
        assertNull(SettingsPanes.shown(null, AppSettings()))
        assertEquals("Settings", SettingsDetailText.PLACEHOLDER_TITLE)
        assertEquals("Select a setting to see more options here", SettingsDetailText.PLACEHOLDER_SUBTITLE)
    }
}
