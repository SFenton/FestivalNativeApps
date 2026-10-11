package com.festivalscoretracker.android.core.rivals

import com.festivalscoretracker.android.core.compete.CompeteText
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.quicklinks.QuickLinkSection

// region Quick Links

/**
 * Quick Links sections for Compete and the Rivals pages (web `CompetePage`,
 * `RivalsPage`/`LeaderboardRivalsTab`, `RivalDetailPage`). Pure: the pages pass what
 * they render and map each section ID back to its grid item. Rivalry has none: the web's
 * one link per song only repeated the list (owner, #545).
 */
object RivalQuickLinks {
    /** Web Compete group IDs. */
    const val COMPETE_LEADERBOARDS = "leaderboards"

    /** Web Compete group IDs. */
    const val COMPETE_RIVALS = "rivals"

    /** Hub section ID of Common Rivals (web `common`). */
    const val COMMON = "common"

    /** Hub section ID of the Settings combo (web `combo`). */
    const val COMBO = "combo"

    /**
     * Compete's two groups (web `quickLinkItems`: Leaderboards with a trophy, Rivals with people).
     *
     * @return Sections in page order.
     */
    fun compete(): List<QuickLinkSection> = listOf(
        QuickLinkSection(COMPETE_LEADERBOARDS, CompeteText.LEADERBOARDS, icon = "trophy"),
        QuickLinkSection(COMPETE_RIVALS, CompeteText.RIVALS, icon = "people"),
    )

    /**
     * One Rivals hub card (web: Common Rivals → people, the combo → notes, a chart → its icon;
     * the Leaderboard Rivals tab lists one chart per card).
     *
     * @param id Hub section ID.
     * @param title Card title ("Common Rivals", "Lead Rivals", …).
     * @param instrument The card's chart, or null for Common/combo.
     * @return Section.
     */
    fun hub(id: String, title: String, instrument: Instrument?): QuickLinkSection = when {
        instrument != null -> QuickLinkSection(id, title, instrument = instrument)
        id == COMMON -> QuickLinkSection(id, title, icon = "people")
        else -> QuickLinkSection(id, title, icon = "music")
    }

    /**
     * Web `rivalDetailCategoryQuickLinkId`.
     *
     * @param key Category key.
     * @return `rival-category:<key>`.
     */
    fun categoryId(key: String): String = "rival-category:$key"

    /**
     * Rival Detail: one section per shown category (web: title as label and landmark, no icon).
     *
     * @param categories Categories in page order.
     * @return Sections.
     */
    fun rivalDetail(categories: List<RivalCategory>): List<QuickLinkSection> =
        categories.map { QuickLinkSection(categoryId(it.key), it.title) }
}

// endregion
