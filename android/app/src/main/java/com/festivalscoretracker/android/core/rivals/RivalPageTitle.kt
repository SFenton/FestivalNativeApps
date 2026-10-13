package com.festivalscoretracker.android.core.rivals

import com.festivalscoretracker.android.core.model.Instrument

// region Page titles

/**
 * A rival page's top app bar title and subtitle (issue #604).
 *
 * @property title Bar title.
 * @property subtitle Second bar line.
 * @property subtitleInstrument Chart whose decorative icon leads [subtitle], if any.
 */
data class RivalBarTitle(val title: String, val subtitle: String, val subtitleInstrument: Instrument? = null)

/**
 * Bar titles for the pages under one rival (owner, issue #604): the page names the rival and
 * its subtitle names where it sits, so the title says what is shown and the subtitle the context.
 */
object RivalPageTitles {
    /** Name shown before the read names an unnamed rival. */
    const val FALLBACK_NAME = "Rival"

    /**
     * Rival Detail: the rival's name over "Rivals", or over "{Instrument} Rivals" led by the
     * chart's icon when the rival came from a single-chart list (song or leaderboard rivals).
     * Multi-chart scopes (Common, combos, Settings) keep the plain "Rivals".
     *
     * @param name Known display name, or null.
     * @param scope Route scope, or null to resolve against Settings.
     * @return Bar title.
     */
    fun detail(name: String?, scope: RivalScope?): RivalBarTitle {
        val instrument = RivalScopes.singleInstrument(scope)
        val subtitle = instrument?.let { RivalText.rivalsTitle(it.label) } ?: RivalText.RIVALS
        return RivalBarTitle(nameOrFallback(name), subtitle, instrument)
    }

    /**
     * Rivalry (one category): the category's title (e.g. "Closest Battles") over the rival's name.
     *
     * @param mode Category key.
     * @param name Known display name, or null.
     * @return Bar title.
     */
    fun rivalry(mode: String, name: String?): RivalBarTitle =
        RivalBarTitle(RivalCategorization.title(mode), nameOrFallback(name))

    private fun nameOrFallback(name: String?): String = name?.takeIf { it.isNotBlank() } ?: FALLBACK_NAME
}

// endregion
