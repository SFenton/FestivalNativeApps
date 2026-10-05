package com.festivalscoretracker.android.core.shell

import com.festivalscoretracker.android.core.nav.FestivalSection

// region Prototype

/**
 * Issue #309 design prototype: where compact (phone) windows put global search, the Songs list
 * filter and page tools. Debug launches only (`FST_DEBUG_CHROME_PROTO`); every other launch is [A],
 * the shipped #52/#84 placement. Medium and wider windows are unchanged by every option.
 *
 * **Prototype, not for merge:** the owner picks one option, then the chosen placement replaces
 * this switch and the others are deleted.
 *
 * @property searchTab Global search is a trailing Search item in the bottom navigation bar.
 * @property searchInTopBar Global search is a magnifier action in the top app bar.
 * @property songsFilterInToolbar The Songs filter field lives in the floating toolbar and
 *   minimizes on scroll (#84); otherwise it is pinned inline above the list.
 * @property floatingToolbar Page tools sit in the floating toolbar; otherwise in top app bar actions.
 * @property bellInToolbar The notifications bell trails the page tools in the floating toolbar
 *   (Apple's tab-bar accessory analog); otherwise it stays in the top app bar.
 */
enum class ChromePrototype(
    val searchTab: Boolean,
    val searchInTopBar: Boolean,
    val songsFilterInToolbar: Boolean,
    val floatingToolbar: Boolean,
    val bellInToolbar: Boolean,
) {
    /** Shipped baseline: toolbar search + Sort/Filter/Quick Links; search icon, bell, avatar on top. */
    A(searchTab = false, searchInTopBar = true, songsFilterInToolbar = true, floatingToolbar = true, bellInToolbar = false),

    /** Closest to Apple: Search tab, inline filter, toolbar tools + bell, avatar on top. */
    B(searchTab = true, searchInTopBar = false, songsFilterInToolbar = false, floatingToolbar = true, bellInToolbar = true),

    /** Top-bar search: search icon, bell, avatar on top; inline filter; toolbar tools. */
    C(searchTab = false, searchInTopBar = true, songsFilterInToolbar = false, floatingToolbar = true, bellInToolbar = false),

    /** Top app bar only: Search tab, inline filter, tools + bell + avatar in the top app bar. */
    D(searchTab = true, searchInTopBar = false, songsFilterInToolbar = false, floatingToolbar = false, bellInToolbar = false);

    /**
     * Sections shown in the compact bottom bar. A Search item makes six items for a profile, over
     * Material's 3–5 destination limit, so Statistics (still in the drawer and on the avatar)
     * leaves the bar first, as Apple's `FestivalTabPolicy.fittingSearchTab` does.
     *
     * @param sections Visible sections ([com.festivalscoretracker.android.core.nav.FestivalTabPolicy.sections]).
     * @return Sections for the bar, before the Search item.
     */
    fun barSections(sections: List<FestivalSection>): List<FestivalSection> =
        if (searchTab && sections.size >= MAX_BAR_ITEMS) sections - FestivalSection.Statistics else sections

    companion object {
        /** Material 3 navigation bar limit. */
        const val MAX_BAR_ITEMS = 5

        /**
         * Parse the debug extra.
         *
         * @param raw `A`–`D` in any case, or null.
         * @return The option, or [A] for anything else.
         */
        fun parse(raw: String?): ChromePrototype = entries.firstOrNull { it.name.equals(raw?.trim(), ignoreCase = true) } ?: A
    }
}

// endregion
