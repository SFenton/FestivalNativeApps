package com.festivalscoretracker.android.core.rivals

import com.festivalscoretracker.android.core.model.ProfileSearchText
import com.festivalscoretracker.android.core.nav.AllRivalsRoute
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.RivalDetailRoute
import com.festivalscoretracker.android.core.nav.RivalryRoute

// region Routes

/** Typed construction and debug parsing of rival routes. */
object RivalRoutes {
    /**
     * All Rivals for a scope.
     *
     * @param scope List scope.
     * @return Route.
     */
    fun allRivals(scope: RivalScope): AllRivalsRoute = AllRivalsRoute(scope.routeToken)

    /**
     * Rival Detail.
     *
     * @param rivalId Rival.
     * @param name Known display name.
     * @param scope Scope the rival came from, or null to resolve against Settings.
     * @param allowLiveFallback Only for Find Rival.
     * @return Route.
     */
    fun detail(rivalId: String, name: String?, scope: RivalScope?, allowLiveFallback: Boolean = false): RivalDetailRoute =
        RivalDetailRoute(rivalId, name, scope?.routeToken, allowLiveFallback)

    /**
     * Rivalry for one category, forwarding the detail's scope and live-fallback flag.
     *
     * @param detail Originating detail route.
     * @param mode Category key.
     * @param name Resolved display name.
     * @return Route.
     */
    fun rivalry(detail: RivalDetailRoute, mode: String, name: String?): RivalryRoute =
        RivalryRoute(detail.rivalId, mode, name ?: detail.name, detail.scope, detail.allowLiveFallback)

    /**
     * Parse `FST_DEBUG_ROUTE` rival forms: `allRivals:<scope>`,
     * `rivalDetail:<rivalId>[:<scope>]`, `rivalry:<rivalId>:<mode>[:<scope>]`.
     *
     * @param kind Route name.
     * @param arg Text after the first colon.
     * @return Route, or null when malformed.
     */
    fun parseDebug(kind: String, arg: String?): AppRoute? {
        if (arg.isNullOrBlank()) return null
        return when (kind) {
            "allRivals" -> RivalScopes.fromToken(arg)?.let(::allRivals)
            "rivalDetail" -> {
                val id = arg.substringBefore(':')
                val scope = arg.substringAfter(':', "").takeIf { it.isNotEmpty() }
                if (!ProfileSearchText.isValidAccountId(id)) return null
                RivalDetailRoute(id, scope = scope?.let { RivalScopes.fromToken(it)?.routeToken ?: return null })
            }
            "rivalry" -> {
                val pieces = arg.split(':', limit = 3)
                val id = pieces[0]
                val mode = pieces.getOrNull(1)?.takeIf { it.isNotEmpty() } ?: return null
                if (!ProfileSearchText.isValidAccountId(id)) return null
                RivalryRoute(id, mode, scope = pieces.getOrNull(2)?.let { RivalScopes.fromToken(it)?.routeToken ?: return null })
            }
            else -> null
        }
    }
}

// endregion
