package com.festivalscoretracker.android.core.settings

import com.festivalscoretracker.android.core.serviceinfo.ServiceInfoText

// region Details

/**
 * A Settings entry with more than a switch: on wide windows it is a chevron row in the
 * Settings list whose options open in the trailing pane (owner, #371). Plain switches and
 * actions (Reset, feedback) stay in the list and are never details.
 *
 * Each section detail's [title] and [hint] are also its header on phones, so the list row,
 * the pane header and the single-column section never drift apart.
 *
 * @property id Stable id: the Quick Links section id for whole sections, else the setting's tag.
 * @property title Title Case title.
 * @property hint Supporting text under the title, or null when the control explains itself (the
 *   leeway slider's live description).
 * @property section Whether this is a whole Settings section (its row replaces the section on
 *   wide windows) rather than one App Settings option.
 */
enum class SettingsDetail(val id: String, val title: String, val hint: String?, val section: Boolean) {
    PathDefaultView("path-default-view", "CHOpt Path Default View", "Choose whether CHOpt paths open as an image or text table by default.", section = false),
    PathColumnOrder(
        "path-column-order", "CHOpt Text Path Column Order",
        "Choose the order columns appear in the CHOpt text path view. You can also drag column headers directly in the path modal.", section = false,
    ),
    SongRowOrder(
        "song-row-order", "Song Row Visual Order",
        "When filtering to a single instrument in the song list, extra metadata is displayed. Choose the order it appears in on the bottom row.", section = false,
    ),
    Leeway("leeway", "Maximum Score Leeway", null, section = false),
    ItemShop("item-shop", "Item Shop", "Control how Item Shop availability is displayed.", section = true),
    ShowInstruments("show-instruments", "Show Instruments", "Choose which instruments to display throughout the app.", section = true),
    ShowMetadata(
        "show-metadata", "Show Instrument Metadata",
        "When filtering songs down to one instrument in the song list, extra metadata for that song can appear. Choose what you'd like to see in the song row here.",
        section = true,
    ),
    Accessibility("accessibility", "Accessibility", "These add to your Android accessibility settings and can only make the app calmer or clearer.", section = true),
    Version("version", "Festival Score Tracker Version", "Festival Score Tracker information to help with debugging.", section = true),
    ServiceInfo("service-info", ServiceInfoText.TITLE, ServiceInfoText.HINT, section = true),
    FirstRun("first-run", "First Run Guides", "Re-visit the first run experience for each page.", section = true),
    Licenses("licenses", "Licenses", "Open source package license details.", section = true),
    PrivacyPolicy("privacy-policy", "Privacy Policy", "How Festival Score Tracker handles your information.", section = true);

    /** Test tag of this detail's chevron row (Licenses and Privacy Policy keep their single-column tags). */
    val rowTag: String
        get() = when (this) {
            Licenses -> "fst.settings.licenses"
            PrivacyPolicy -> "fst.settings.privacy-policy"
            else -> "fst.settings.open.$id"
        }

    companion object {
        /**
         * The detail a whole Settings section collapses to on wide windows.
         *
         * @param sectionId Quick Links section id.
         * @return The section's detail, or null for sections that stay in the list (App Settings, Diagnostics, Reset).
         */
        fun forSection(sectionId: String): SettingsDetail? = entries.firstOrNull { it.section && it.id == sectionId }

        /**
         * Parse a saved id.
         *
         * @param id Saved [SettingsDetail.id].
         * @return The detail or null.
         */
        fun fromId(id: String?): SettingsDetail? = entries.firstOrNull { it.id == id }
    }
}

// endregion

// region Policy

/** Copy of the detail pane's empty state (owner's words, #371). */
object SettingsDetailText {
    const val PLACEHOLDER_TITLE = "Settings"
    const val PLACEHOLDER_SUBTITLE = "Select a setting to see more options here"
}

/** Pure rules for the wide-window Settings list/detail (owner, #371). */
object SettingsPanes {
    /**
     * Whether [detail]'s row is in the list now: Song Row Visual Order exists only while
     * "Enable Independent Song Row Visual Order" is on, and Maximum Score Leeway only while
     * "Filter Invalid Scores" is on (as on phones, where they show under those switches).
     *
     * @param detail Detail.
     * @param settings Effective settings.
     * @return True when its row is shown.
     */
    fun available(detail: SettingsDetail, settings: AppSettings): Boolean = when (detail) {
        SettingsDetail.SongRowOrder -> settings.enableVisualOrder
        SettingsDetail.Leeway -> settings.filterInvalidScores
        else -> true
    }

    /**
     * The detail the trailing pane shows.
     *
     * @param selectedId Saved selection, or null.
     * @param settings Effective settings.
     * @return The selected detail while its row exists, else null (the "Select a setting" placeholder).
     */
    fun shown(selectedId: String?, settings: AppSettings): SettingsDetail? =
        SettingsDetail.fromId(selectedId)?.takeIf { available(it, settings) }
}

// endregion
