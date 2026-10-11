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

    /**
     * Select [parent]'s tab at its root, then push [route] as its child: the destination is not
     * a tab at this width, but its parent is (Rivals and Leaderboards under Compete, #610).
     */
    data class Child(val parent: FestivalSection, val route: AppRoute) : DrawerTarget

    /** Push a route on the current tab (neither the destination nor a parent is a tab here). */
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
     * rail); else its pushed page as a child of its visible parent tab (Rivals and Leaderboards
     * under Compete on a phone, #610, so the bar shows the tab the page belongs to); else the
     * pushed page on the current tab (Statistics, which the Profile button also pushes, #601).
     *
     * @param entry Row.
     * @param visible Tabs visible now ([FestivalTabPolicy.sections]).
     * @return Target.
     */
    fun target(entry: DrawerEntry, visible: List<FestivalSection>): DrawerTarget {
        val section = entry.section
        if (section != null && section in visible) return DrawerTarget.Section(section)
        val parent = section?.let(FestivalTabPolicy::parent)?.takeIf { it in visible }
        return if (parent != null) DrawerTarget.Child(parent, entry.pushed) else DrawerTarget.Push(entry.pushed)
    }

    /**
     * Where a request for [section] goes (debug launch, a search result): the same as its
     * drawer row ([target]), so Statistics pushes (never a tab since #601) and Rivals or
     * Leaderboards open under Compete on a phone (#610).
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
     * Whether [entry] is the current location. Like the web sidebar's `NavLink`, a row follows
     * the page on screen: a pushed drawer page ([page]) wins over the tab under it, so Rivals
     * opened under Compete highlights Rivals, not nothing, and Statistics pushed on Songs
     * highlights Statistics, not Songs (#610).
     *
     * @param entry Row.
     * @param selected Selected tab.
     * @param page Drawer page pushed on the selected tab ([pageOf]), or null on a tab's own pages.
     * @return True when the row is the page shown, or its tab when no drawer page is pushed.
     */
    fun isSelected(entry: DrawerEntry, selected: FestivalSection, page: DrawerEntry? = null): Boolean =
        if (page != null) entry == page else entry.section == selected

    /**
     * The drawer page a tab's back stack is showing: the topmost route above the tab root that is
     * a drawer row's pushed page (Rivals under Compete, Statistics on Songs), so its child pages
     * (Rival Detail, a song opened from Statistics) keep the row highlighted.
     *
     * @param aboveRoot Matchers for the stack entries above the selected tab's root, bottom to
     *   top; each answers whether that entry shows a given route.
     * @return The row, or null when no drawer page is pushed.
     */
    fun pageOf(aboveRoot: List<(AppRoute) -> Boolean>): DrawerEntry? =
        aboveRoot.asReversed().firstNotNullOfOrNull { shows -> DrawerEntry.entries.firstOrNull { shows(it.pushed) } }

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
