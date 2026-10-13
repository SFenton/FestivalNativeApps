package com.festivalscoretracker.android.core.shell

import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.nav.FestivalTabPolicy
import com.festivalscoretracker.android.core.nav.LeaderboardsRoute
import com.festivalscoretracker.android.core.nav.ProfileKind
import com.festivalscoretracker.android.core.nav.RivalsRoute
import com.festivalscoretracker.android.core.nav.ShopRoute
import com.festivalscoretracker.android.core.nav.SongsTab
import com.festivalscoretracker.android.core.nav.StatisticsRoute
import com.festivalscoretracker.android.core.nav.SuggestionsRoute

// region Entries

/** Rows of the navigation drawer's main list (web `Sidebar` `<nav>`), in display order. */
enum class DrawerEntry(val title: String, val section: FestivalSection?, val pushed: AppRoute) {
    Songs("Songs", FestivalSection.Songs, SongsTab),
    Suggestions("Suggestions", FestivalSection.Suggestions, SuggestionsRoute),
    Statistics("Statistics", FestivalSection.Statistics, StatisticsRoute),
    Rivals("Rivals", FestivalSection.Rivals, RivalsRoute),
    Leaderboards("Leaderboards", FestivalSection.Leaderboards, LeaderboardsRoute),
    Shop("Item Shop", FestivalSection.Shop, ShopRoute),
}

/** What a drawer row does. */
sealed interface DrawerTarget {
    /** Switch to a visible tab. */
    data class Section(val section: FestivalSection) : DrawerTarget

    /** Select the owning tab at its root, then push its child page. */
    data class Child(val section: FestivalSection, val route: AppRoute) : DrawerTarget

    /** Push a route on the current tab (the destination is not a tab at this width). */
    data class Push(val route: AppRoute) : DrawerTarget
}

// endregion

// region Policy

/**
 * Drawer contents, mirroring the web sidebar (`components/shell/desktop/Sidebar.tsx`):
 * Songs · Suggestions* · Statistics* · Rivals† · Leaderboards · Item Shop‡, then a footer with
 * the profile row (or Select Profile) and Settings last (* any profile, † a player,
 * ‡ unless Hide Item Shop). Bands and Licenses are not drawer rows: Bands is reached from
 * search and leaderboard links, Licenses from Settings.
 */
object DrawerPolicy {
    /**
     * Main rows for the current profile.
     *
     * @param profile Selected profile kind.
     * @param showShop False while Settings' Hide Item Shop is on.
     * @return Rows in display order.
     */
    fun entries(profile: ProfileKind, showShop: Boolean): List<DrawerEntry> = buildList {
        add(DrawerEntry.Songs)
        if (profile != ProfileKind.None) {
            add(DrawerEntry.Suggestions)
            add(DrawerEntry.Statistics)
        }
        if (profile == ProfileKind.Player) add(DrawerEntry.Rivals)
        add(DrawerEntry.Leaderboards)
        if (showShop) add(DrawerEntry.Shop)
    }

    /**
     * Where a row goes: its tab when that tab is visible at this width (e.g. Rivals on a
     * rail), its owning tab's child (Rivals/Leaderboards under Compete), or a current-tab push.
     *
     * @param entry Row.
     * @param visible Tabs visible now ([com.festivalscoretracker.android.core.nav.FestivalTabPolicy.sections]).
     * @return Target.
     */
    fun target(entry: DrawerEntry, visible: List<FestivalSection>): DrawerTarget {
        val section = entry.section
        if (section != null && section in visible) return DrawerTarget.Section(section)
        val parent = section?.let { FestivalTabPolicy.parent(it, visible) }
        return if (parent != null) DrawerTarget.Child(parent, entry.pushed) else DrawerTarget.Push(entry.pushed)
    }

    /**
     * Where a request for [section] goes (debug launch, a search result): the tab when visible,
     * else the same parent-child or pushed target as its drawer row (Statistics pushes, #601).
     *
     * @param section Requested section.
     * @param visible Tabs visible now.
     * @return Target, or null when the section is neither visible nor pushable (e.g. Compete on a rail).
     */
    fun sectionTarget(section: FestivalSection, visible: List<FestivalSection>): DrawerTarget? =
        if (section in visible) {
            DrawerTarget.Section(section)
        } else {
            DrawerEntry.entries.firstOrNull { it.section == section }?.let { target(it, visible) }
        }

    /**
     * Whether [entry] is the current location.
     *
     * @param entry Row.
     * @param selected Selected tab.
     * @return True when the row's tab is selected.
     */
    fun isSelected(entry: DrawerEntry, selected: FestivalSection): Boolean = entry.section == selected

    /**
     * Tabs shown in the rail's main group: everything but Settings, which the rail pins to
     * its bottom edge next to the profile button.
     *
     * @param sections Visible tabs.
     * @return Main-group tabs.
     */
    fun railMain(sections: List<FestivalSection>): List<FestivalSection> = sections.filter { it != FestivalSection.Settings }
}

// endregion
