package com.festivalscoretracker.android.core.nav

// region Sections

/**
 * Root destinations shown as tabs, rail items or drawer rows (Apple
 * `FestivalSection`, web `BottomNav`). Visibility comes from [FestivalTabPolicy].
 *
 * @property title Title Case label.
 * @property root Tab root route.
 */
enum class FestivalSection(val title: String, val root: AppRoute) {
    Songs("Songs", SongsTab),
    Suggestions("Suggestions", SuggestionsTab),
    Leaderboards("Leaderboards", LeaderboardsTab),
    Compete("Compete", CompeteTab),
    Rivals("Rivals", RivalsTab),
    Statistics("Statistics", StatisticsTab),
    Settings("Settings", SettingsTab);

    companion object {
        /**
         * Parse a lowercase debug/tab name such as `songs`.
         *
         * @param raw Name in any case.
         * @return The section or null.
         */
        fun fromName(raw: String?): FestivalSection? = entries.firstOrNull { it.name.equals(raw, ignoreCase = true) }
    }
}

/** Which kind of profile the shell is scoped to. */
enum class ProfileKind { None, Player, Band }

// endregion

// region Tab policy

/** Pure rules for which root sections exist (Apple `FestivalTabPolicy`, web `BottomNav`). */
object FestivalTabPolicy {
    /**
     * Visible sections in display order.
     *
     * No profile: Songs · Leaderboards · Settings. Player: Songs · Suggestions ·
     * Compete · Statistics · Settings on compact widths; Leaderboards and Rivals
     * replace Compete on regular widths. Band: Songs · Suggestions · Leaderboards ·
     * Statistics · Settings.
     *
     * @param profile Selected profile kind.
     * @param regularWidth True at ≥ 600 dp (rail/drawer layouts).
     * @return Ordered sections.
     */
    fun sections(profile: ProfileKind, regularWidth: Boolean): List<FestivalSection> = buildList {
        add(FestivalSection.Songs)
        if (profile != ProfileKind.None) add(FestivalSection.Suggestions)
        when {
            profile == ProfileKind.Player && regularWidth -> {
                add(FestivalSection.Leaderboards)
                add(FestivalSection.Rivals)
            }
            profile == ProfileKind.Player -> add(FestivalSection.Compete)
            else -> add(FestivalSection.Leaderboards)
        }
        if (profile != ProfileKind.None) add(FestivalSection.Statistics)
        add(FestivalSection.Settings)
    }

    /**
     * Keep the user on an equivalent section when the visible set changes;
     * Compete and Leaderboards/Rivals share a slot.
     *
     * @param current Section selected before the change.
     * @param visible Newly visible sections.
     * @return [current], its slot equivalent, or Songs.
     */
    fun resolve(current: FestivalSection, visible: List<FestivalSection>): FestivalSection {
        if (current in visible) return current
        val equivalent = when (current) {
            FestivalSection.Compete -> FestivalSection.Leaderboards.takeIf { it in visible }
            FestivalSection.Leaderboards, FestivalSection.Rivals -> FestivalSection.Compete.takeIf { it in visible }
            else -> null
        }
        return equivalent ?: FestivalSection.Songs
    }

    /**
     * Whether leaving a section discards its nested history (web: Statistics only).
     *
     * @param section Section being left.
     * @return True when its back stack should not be restored.
     */
    fun resetsPathOnLeave(section: FestivalSection): Boolean = section == FestivalSection.Statistics
}

// endregion

// region Adaptive layout policy

/** Navigation chrome per window width (bar → rail → permanent drawer). */
enum class NavigationLayout { BottomBar, Rail, PermanentDrawer }

/**
 * Window-size-class rules (Material 3 breakpoints), kept pure so they are unit-tested
 * and never depend on product names or device pixels.
 */
object AdaptiveLayoutPolicy {
    /** Material compact/medium boundary. */
    const val MEDIUM_WIDTH_DP = 600

    /** Material medium/expanded boundary. */
    const val EXPANDED_WIDTH_DP = 840

    /** Material large boundary. */
    const val LARGE_WIDTH_DP = 1200

    /**
     * Choose navigation chrome for a window.
     *
     * @param widthDp Window width in dp.
     * @param heightDp Window height in dp; a very short landscape window keeps the rail.
     * @return Bar below 600 dp (unless height-compact), rail below 1200 dp, else a permanent drawer.
     */
    fun navigationLayout(widthDp: Int, heightDp: Int): NavigationLayout = when {
        widthDp < MEDIUM_WIDTH_DP && heightDp >= 480 -> NavigationLayout.BottomBar
        widthDp < LARGE_WIDTH_DP -> NavigationLayout.Rail
        else -> NavigationLayout.PermanentDrawer
    }

    /**
     * Whether tab policy should use its regular-width variant.
     *
     * @param widthDp Window width in dp.
     * @return True at ≥ 600 dp.
     */
    fun isRegularWidth(widthDp: Int): Boolean = widthDp >= MEDIUM_WIDTH_DP

    /**
     * Whether list-detail screens show both panes.
     *
     * @param widthDp **Window** width in dp (Material's expanded class), not the
     *   content width left after a rail.
     * @param separatingHinge Whether a vertical separating fold splits the window.
     * @return True for expanded widths or a separating vertical hinge.
     */
    fun showsTwoPanes(widthDp: Int, separatingHinge: Boolean): Boolean =
        separatingHinge || widthDp >= EXPANDED_WIDTH_DP

    /**
     * Width of the list pane: the hinge's leading edge when a vertical fold
     * separates the window, otherwise 40% clamped to 320–440 dp.
     *
     * @param widthDp Content width in dp.
     * @param hingeStartDp Leading edge of a separating vertical hinge, if any.
     * @return List pane width in dp.
     */
    fun listPaneWidth(widthDp: Int, hingeStartDp: Int?): Int =
        hingeStartDp?.takeIf { it in 1 until widthDp } ?: (widthDp * 2 / 5).coerceIn(320, 440)
}

// endregion
