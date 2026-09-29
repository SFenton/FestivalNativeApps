package com.festivalscoretracker.android.core.shell

import com.festivalscoretracker.android.core.nav.AllRivalsRoute
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.CompeteRoute
import com.festivalscoretracker.android.core.nav.CompeteTab
import com.festivalscoretracker.android.core.nav.PlayerHistoryRoute
import com.festivalscoretracker.android.core.nav.RivalDetailRoute
import com.festivalscoretracker.android.core.nav.RivalryRoute
import com.festivalscoretracker.android.core.nav.RivalsRoute
import com.festivalscoretracker.android.core.nav.RivalsTab
import com.festivalscoretracker.android.core.nav.StatisticsRoute
import com.festivalscoretracker.android.core.nav.StatisticsTab
import com.festivalscoretracker.android.core.nav.SuggestionsRoute
import com.festivalscoretracker.android.core.nav.SuggestionsTab
import kotlin.reflect.KClass

// region Profile-only routes

/**
 * Routes that exist only while a profile is selected (web parity, orchestrator decision
 * 2026-09-28, PWA gap 4): the web hides Rivals, Statistics, Suggestions, Compete and Player
 * History and redirects them to Songs until a player is selected, so the native app does too
 * — for deep links, back-stack restores and a deselect while one of them is showing.
 */
object ProfileRoutePolicy {
    /** Route types that need a selected profile. */
    val requiresProfile: List<KClass<out AppRoute>> = listOf(
        RivalsTab::class,
        RivalsRoute::class,
        AllRivalsRoute::class,
        RivalDetailRoute::class,
        RivalryRoute::class,
        StatisticsTab::class,
        StatisticsRoute::class,
        SuggestionsTab::class,
        SuggestionsRoute::class,
        CompeteTab::class,
        CompeteRoute::class,
        PlayerHistoryRoute::class,
    )

    /**
     * Whether a route must redirect to Songs.
     *
     * @param route Route type on screen.
     * @param hasProfile A player (or band) is selected.
     * @return True when the route needs a profile and none is selected.
     */
    fun redirectsToSongs(route: KClass<out AppRoute>, hasProfile: Boolean): Boolean = !hasProfile && route in requiresProfile
}

// endregion
