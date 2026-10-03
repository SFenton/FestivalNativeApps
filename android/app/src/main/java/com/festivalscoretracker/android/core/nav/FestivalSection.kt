package com.festivalscoretracker.android.core.nav

import kotlin.math.roundToInt

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

    /** Material compact-height boundary. */
    const val MEDIUM_HEIGHT_DP = 480

    /**
     * Choose navigation chrome for a window (Material 3 `NavigationSuiteScaffoldDefaults.navigationSuiteType`,
     * plus a permanent drawer on large windows).
     *
     * @param widthDp Window width in dp.
     * @param heightDp Window height in dp.
     * @param tabletop Whether a horizontal half-opened fold splits the window (tabletop posture).
     * @return Bar on compact widths, compact heights or tabletop (controls in the bottom half);
     *   rail below 1200 dp; else a permanent drawer.
     */
    fun navigationLayout(widthDp: Int, heightDp: Int, tabletop: Boolean = false): NavigationLayout = when {
        widthDp < MEDIUM_WIDTH_DP || heightDp < MEDIUM_HEIGHT_DP || tabletop -> NavigationLayout.BottomBar
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
     * @param fontScale User font scale. From [LARGE_TEXT_SCALE] a fold no longer forces two
     *   panes and the width must reach the expanded class in text-scaled dp (a 200% list pane
     *   beside the hinge wrapped titles a few letters per line).
     * @return True for expanded widths or a separating vertical hinge.
     */
    fun showsTwoPanes(widthDp: Int, separatingHinge: Boolean, fontScale: Float = 1f): Boolean =
        if (fontScale >= LARGE_TEXT_SCALE) widthDp / fontScale >= EXPANDED_WIDTH_DP else separatingHinge || widthDp >= EXPANDED_WIDTH_DP

    /** Font scale from which layouts reflow for large text (`ui.common.LARGE_TEXT_SCALE`). */
    const val LARGE_TEXT_SCALE = 1.3f

    /** Permanent drawer width at default text (the web sidebar's compact width). */
    const val PERMANENT_DRAWER_WIDTH_DP = 280

    /** Material 3 standard drawer width, the widest the permanent drawer grows. */
    const val PERMANENT_DRAWER_MAX_WIDTH_DP = 360

    /**
     * Width of the permanent drawer: 280 dp scaled with the user's font scale up to Material's
     * 360 dp standard drawer (at 200% text a fixed 280 dp broke "Leaderboards" mid-word, issue #101).
     *
     * @param fontScale User font scale.
     * @return Drawer width in dp.
     */
    fun permanentDrawerWidth(fontScale: Float): Int =
        (PERMANENT_DRAWER_WIDTH_DP * fontScale.coerceAtLeast(1f)).roundToInt().coerceAtMost(PERMANENT_DRAWER_MAX_WIDTH_DP)

    /**
     * Width of the list pane: the hinge's leading edge when a vertical fold
     * separates the window, otherwise 40% of the usable width clamped to 320–440 dp,
     * plus any display cutout the pane's leading edge covers (a landscape phone's camera
     * inset otherwise left the list pane's top bar room for only "Son…", issue #101).
     *
     * @param widthDp Content width in dp.
     * @param hingeStartDp Leading edge of a separating vertical hinge, if any.
     * @param leadingInsetDp Display cutout inset inside the pane's leading edge, in dp.
     * @return List pane width in dp.
     */
    fun listPaneWidth(widthDp: Int, hingeStartDp: Int?, leadingInsetDp: Int = 0): Int {
        hingeStartDp?.takeIf { it in 1 until widthDp }?.let { return it }
        val inset = leadingInsetDp.coerceIn(0, widthDp / 4)
        return (inset + ((widthDp - inset) * 2 / 5).coerceIn(320, 440)).coerceAtMost(maxOf(widthDp / 2, 320))
    }
}

// endregion
