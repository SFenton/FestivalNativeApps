package com.festivalscoretracker.android.core.shell

import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.nav.ProfileKind

// region Profile chip

/** What the profile chip (top-bar avatar `fst.nav.profile`, rail `fst.nav.rail.profile`) does. */
sealed interface ProfileChipAction {
    /** No profile is selected: open profile selection (the Profiles sheet). */
    data object ChooseProfile : ProfileChipAction

    /** A profile is selected: go to its page, Statistics (a visible tab, or pushed). */
    data class Open(val target: DrawerTarget) : ProfileChipAction
}

/**
 * Profile chip routing, mirroring web `getProfileClickDestination`
 * (`FortniteFestivalWeb/src/utils/profileNavigation.ts`): a selected player or band opens its
 * own page (`/statistics`), the same place as the drawer's profile row; only without a profile
 * does the chip open profile search (issue #290).
 */
object ProfileChipPolicy {
    /**
     * The chip's action for the current profile.
     *
     * @param profile Selected profile kind.
     * @param visible Tabs visible now ([com.festivalscoretracker.android.core.nav.FestivalTabPolicy.sections]).
     * @return [ProfileChipAction.ChooseProfile] without a profile, else Statistics.
     */
    fun action(profile: ProfileKind, visible: List<FestivalSection>): ProfileChipAction = when (profile) {
        ProfileKind.None -> ProfileChipAction.ChooseProfile
        ProfileKind.Player, ProfileKind.Band -> ProfileChipAction.Open(DrawerPolicy.target(DrawerEntry.Statistics, visible))
    }
}

// endregion
