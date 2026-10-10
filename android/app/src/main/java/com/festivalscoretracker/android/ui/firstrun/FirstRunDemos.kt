package com.festivalscoretracker.android.ui.firstrun

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuite
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteDefaults
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteItem
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteType
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoFit
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoPlayer
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoSongs
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoStat
import com.festivalscoretracker.android.core.firstrun.FirstRunEntrance
import com.festivalscoretracker.android.core.firstrun.FirstRunRotatingDemos
import com.festivalscoretracker.android.core.firstrun.FirstRunShopPattern
import com.festivalscoretracker.android.core.firstrun.FirstRunStillDemoData
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.LeaderboardEntry
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.nav.FestivalTabPolicy
import com.festivalscoretracker.android.core.nav.ProfileKind
import com.festivalscoretracker.android.core.paths.PathDifficulty
import com.festivalscoretracker.android.core.profile.PlayerPercentileBucket
import com.festivalscoretracker.android.core.profile.PlayerScoreSortMode
import com.festivalscoretracker.android.core.profile.ScoreHistoryEntry
import com.festivalscoretracker.android.core.profile.StatGridColumns
import com.festivalscoretracker.android.core.profile.StatTints
import com.festivalscoretracker.android.core.rankings.AccountRankingEntry
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.core.shop.ShopHighlight
import com.festivalscoretracker.android.core.shop.ShopPulse
import com.festivalscoretracker.android.core.shop.ShopSong
import com.festivalscoretracker.android.core.songs.SongHistoryPoint
import com.festivalscoretracker.android.core.songs.SongScoreFilterKind
import com.festivalscoretracker.android.core.songs.SongSortDraft
import com.festivalscoretracker.android.core.suggestions.SuggestionCategoryType
import com.festivalscoretracker.android.presentation.profile.PercentileRow
import com.festivalscoretracker.android.presentation.profile.PlayerStatTile
import com.festivalscoretracker.android.presentation.profile.ScoreHistoryRow
import com.festivalscoretracker.android.presentation.shop.ShopOfferItem
import com.festivalscoretracker.android.ui.common.LocalMotionProbe
import com.festivalscoretracker.android.ui.common.MotionProbes
import com.festivalscoretracker.android.ui.design.GlassCard
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.design.InstrumentSelector
import com.festivalscoretracker.android.ui.design.ViewFullLeaderboardButton
import com.festivalscoretracker.android.ui.design.festivalFilledButtonColors
import com.festivalscoretracker.android.ui.leaderboards.AccountRankingRow
import com.festivalscoretracker.android.ui.leaderboards.LEADERBOARD_ROW_GAP
import com.festivalscoretracker.android.ui.leaderboards.LeaderboardSectionMember
import com.festivalscoretracker.android.ui.leaderboards.LocalRankingColumns
import com.festivalscoretracker.android.ui.leaderboards.rememberAccountColumns
import com.festivalscoretracker.android.ui.leaderboards.rememberRankingRowWidth
import com.festivalscoretracker.android.ui.leaderboards.rememberScoreColumns
import com.festivalscoretracker.android.ui.profile.InstrumentHeading
import com.festivalscoretracker.android.ui.profile.PercentileTable
import com.festivalscoretracker.android.ui.profile.ScoreSortControls
import com.festivalscoretracker.android.ui.profile.StatTile
import com.festivalscoretracker.android.ui.shell.ChromeColors
import com.festivalscoretracker.android.ui.shell.icon
import com.festivalscoretracker.android.ui.shop.ShopActionButton
import com.festivalscoretracker.android.ui.shop.ShopGridCard
import com.festivalscoretracker.android.ui.shop.ShopListRow
import com.festivalscoretracker.android.ui.songdetail.HistoryChart
import com.festivalscoretracker.android.ui.songdetail.OptionGrid
import com.festivalscoretracker.android.ui.songdetail.ScoreRow
import com.festivalscoretracker.android.ui.songs.RadioRow
import com.festivalscoretracker.android.ui.songs.ShopBadge
import com.festivalscoretracker.android.ui.songs.SongRowCard
import com.festivalscoretracker.android.ui.songs.SongsTokens
import com.festivalscoretracker.android.ui.songs.SortDirectionSection
import com.festivalscoretracker.android.ui.songs.ToggleRow
import com.festivalscoretracker.android.ui.songs.chartDescription
import com.festivalscoretracker.android.ui.songs.chartLabel
import com.festivalscoretracker.android.ui.songs.pulseOutline
import com.festivalscoretracker.android.ui.songs.rememberShopBreathe
import com.festivalscoretracker.android.ui.songs.rememberShopPulse
import com.festivalscoretracker.android.ui.suggestions.InstrumentTypePicker
import com.festivalscoretracker.android.ui.suggestions.SwitchRow
import com.festivalscoretracker.android.ui.theme.BrandTokens
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import com.festivalscoretracker.android.ui.leaderboards.CardHeader as RankingsCardHeader
import com.festivalscoretracker.android.ui.leaderboards.RowSeparator as RankingsRowSeparator
import com.festivalscoretracker.android.ui.profile.HistoryRow as ProfileHistoryRow
import com.festivalscoretracker.android.ui.songdetail.CardHeader as SongCardHeader
import com.festivalscoretracker.android.ui.songdetail.HistoryRow as SongHistoryRow
import com.festivalscoretracker.android.ui.songdetail.RowSeparator as SongRowSeparator

// region Demo routing

/** Every slide ID with a live native mini-demo (all 42 catalogue slides). */
internal val FIRST_RUN_DEMO_IDS: Set<String> = setOf(
    "songs-song-list", "songs-sort", "songs-navigation", "songs-filter", "songs-icons", "songs-metadata",
    "songs-shop-highlight", "songs-new-in-shop", "songs-leaving-tomorrow",
    "songinfo-chart", "songinfo-bar-select", "songinfo-view-all", "songinfo-top-scores", "songinfo-paths",
    "songinfo-shop-button", "songinfo-new-in-shop", "songinfo-leaving-tomorrow",
    "playerhistory-score-list", "playerhistory-sort",
    "statistics-select-profile", "statistics-drill-down", "statistics-overview", "statistics-instrument-breakdown",
    "statistics-percentiles", "statistics-top-songs",
    "suggestions-category-card", "suggestions-global-filter", "suggestions-instrument-filter", "suggestions-infinite-scroll",
    "leaderboards-overview", "leaderboards-experimental-metrics", "leaderboards-your-rank",
    "compete-hub", "compete-leaderboards", "compete-rivals",
    "rivals-overview", "rivals-instruments", "rivals-detail",
    "shop-overview", "shop-highlighting", "shop-new-items", "shop-leaving-tomorrow",
)

/**
 * A non-networked mini-demo for one slide (web `pages/<page>/firstRun/demo/`), built from the
 * app's real components for the feature it shows (issue #380): Songs rows are [SongRowCard],
 * sort/filter demos are the real sheets' rows, Song Detail demos are its history chart, score
 * rows and Shop button, Statistics demos are its stat tiles and percentile table, and so on.
 * Song-using demos read real catalogue songs from [LocalFirstRunDemoCatalog] (placeholder rows
 * while it loads or is unavailable); players, ranks and scores are demo numbers. Each demo's
 * parts enter with the web's staggered fadeInUp ([demoEntrance], [FirstRunEntrance]); the
 * twelve web demos that swap data on a timer rotate through [FirstRunRotatingDemo] (issue #58).
 * Pulses, breathes and the infinite scroll run only on the settled current page and never under
 * reduce motion.
 *
 * @param id Slide ID.
 * @param active Whether the slide is the settled current page.
 */
@Composable
fun FirstRunDemo(id: String, active: Boolean) {
    DemoFrame {
        if (id in FirstRunRotatingDemos.IDS) FirstRunRotatingDemo(id, active) else FirstRunStillDemo(id, active)
    }
}

/**
 * The demos that don't swap data on a timer.
 *
 * @param id Slide ID.
 * @param active Whether the slide is the settled current page.
 */
@Composable
private fun FirstRunStillDemo(id: String, active: Boolean) {
    when (id) {
        "songs-sort" -> SongsSortDemo(id)
        "playerhistory-sort" -> HistorySortDemo(id)
        "songs-navigation" -> NavigationDemo()
        "songs-filter" -> SongsFilterDemo(id)
        "suggestions-global-filter" -> SuggestionsGlobalFilterDemo(id)
        "suggestions-instrument-filter" -> SuggestionsInstrumentFilterDemo(id)
        "songs-shop-highlight", "songs-new-in-shop", "songs-leaving-tomorrow", "shop-highlighting" -> SongsShopDemo(id, active)
        "shop-new-items", "shop-leaving-tomorrow" -> ShopListDemo(id, active)
        "shop-overview" -> ShopGridDemo(id, active)
        "songinfo-shop-button", "songinfo-new-in-shop", "songinfo-leaving-tomorrow" -> ShopButtonDemo(id, active)
        "songinfo-chart" -> ChartDemo()
        "songinfo-view-all" -> ViewAllDemo(id, active)
        "songinfo-top-scores" -> TopScoresDemo(id)
        "songinfo-paths" -> PathsDemo()
        "playerhistory-score-list" -> ScoreListDemo(id)
        "leaderboards-overview", "compete-leaderboards" -> RankingsCardDemo(id, yourRank = false)
        "leaderboards-your-rank" -> RankingsCardDemo(id, yourRank = true)
        "statistics-select-profile" -> SelectProfileDemo(active)
        "statistics-drill-down" -> StatTilesDemo(id, FirstRunStillDemoData.DRILL_DOWN, active)
        "statistics-overview" -> StatTilesDemo(id, FirstRunStillDemoData.OVERVIEW, active)
        "statistics-instrument-breakdown" -> StatTilesDemo(id, FirstRunStillDemoData.BREAKDOWN, active, heading = Instrument.Lead)
        "statistics-percentiles" -> PercentilesDemo()
        "suggestions-infinite-scroll" -> InfiniteSuggestionsDemo(active)
        else -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Icon(Icons.Outlined.AutoAwesome, contentDescription = null, tint = BrandTokens.accentPurple, modifier = Modifier.size(48.dp))
        }
    }
}

// endregion

// region Sample data

/**
 * The catalogue songs demos may show (web `useDemoSongs`/`useItemShopDemoSongs`).
 *
 * @property songs Loaded catalogue, or null while loading/unavailable (demos draw placeholders).
 * @property shopSongIds Publication-matched Shop song IDs that Shop demos show first.
 * @property artworkUrl Artwork resolver.
 */
@Immutable
class FirstRunDemoCatalog(
    val songs: List<Song>? = null,
    val shopSongIds: List<String> = emptyList(),
    val artworkUrl: (String?) -> String? = { null },
)

/** Demo songs for the presented carousel; placeholders by default. */
val LocalFirstRunDemoCatalog = compositionLocalOf { FirstRunDemoCatalog() }

/**
 * Songs one demo shows: real catalogue picks, or `null` placeholder slots.
 *
 * @param count Rows.
 * @param shop Prefer current Item Shop songs (Shop-themed demos).
 * @return Songs or nulls.
 */
@Composable
private fun demoSongs(count: Int, shop: Boolean = false): List<Song?> {
    val catalog = LocalFirstRunDemoCatalog.current
    return remember(catalog, count, shop) {
        FirstRunDemoSongs.forDemo(catalog.songs, count, if (shop) catalog.shopSongIds else emptyList())
    }
}

/**
 * A song's decorative artwork URL: none under Data Saver.
 *
 * @param song Catalogue song.
 * @return URL, or null.
 */
@Composable
private fun demoArtUrl(song: Song): String? {
    val url = LocalFirstRunDemoCatalog.current.artworkUrl(song.albumArt)
    return if (rememberDataSaver()) null else url
}

/** "Artist · Year" (the Songs row subtitle). */
private val Song.demoSubtitle: String get() = year?.let { "$artist · $it" } ?: artist

/** A song for headers that only need the instrument artwork flavour. */
private val HEADER_SONG = Song(songId = "fst-first-run-demo", title = "", artist = "")

/** Song-row counts the Songs and Shop row demos try (web `MAX_ROWS` 5; [DemoFitFirst] keeps those that fit). */
internal val DEMO_SONG_ROWS: List<Int> = FirstRunDemoFit.rowCandidates(5)

/** Gap between demo song rows (the Songs list's). */
internal val SONG_ROW_GAP = 8.dp

/** Test tag of a demo song's title (shared with the rotating demos). */
internal fun demoSongTag(songId: String): String = "fst.first-run.demo.song.$songId"

// endregion

// region Building blocks

@Composable
internal fun DemoCard(modifier: Modifier = Modifier, border: Color = BrandTokens.glassBorder, content: @Composable () -> Unit) {
    Box(
        modifier
            .fillMaxWidth()
            .background(BrandTokens.surfaceFrosted, RoundedCornerShape(12.dp))
            .border(1.dp, border, RoundedCornerShape(12.dp))
            .padding(horizontal = 12.dp, vertical = 8.dp),
    ) { content() }
}

/**
 * A redacted text bar standing in for a placeholder row's text (Material has no redaction
 * primitive; a muted shape is its loading-skeleton pattern).
 *
 * @param fraction Share of the available width.
 * @param height Bar height.
 */
@Composable
internal fun RedactedBar(fraction: Float, height: Dp) {
    Box(
        Modifier.padding(vertical = 3.dp).fillMaxWidth(fraction).height(height)
            .background(BrandTokens.surfaceMuted, RoundedCornerShape(4.dp))
            .testTag("fst.first-run.demo.placeholder"),
    )
}

/**
 * A Songs row skeleton while the catalogue loads: the [SongRowCard] glass surface with a muted
 * art tile and two redacted bars.
 *
 * @param modifier Modifier (entrance).
 */
@Composable
internal fun PlaceholderSongCard(modifier: Modifier = Modifier) {
    GlassCard(modifier.fillMaxWidth()) {
        Row(Modifier.padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.size(48.dp).clip(RoundedCornerShape(8.dp)).background(BrandTokens.surfaceMuted))
            Column(Modifier.weight(1f)) {
                RedactedBar(0.7f, 16.dp)
                RedactedBar(0.45f, 12.dp)
            }
        }
    }
}

/** The Shop page's badge for a Songs pulse (in-Shop rows carry none there). */
private val ShopPulse.highlight: ShopHighlight?
    get() = when (this) {
        ShopPulse.New -> ShopHighlight.New
        ShopPulse.LeavingTomorrow -> ShopHighlight.LeavingTomorrow
        else -> null
    }

/**
 * A Shop offer for a demo song (no official link: the demo opens nothing).
 *
 * @param song Catalogue song.
 * @param highlight Badge.
 */
private fun demoOffer(song: Song, highlight: ShopHighlight?): ShopOfferItem = ShopOfferItem(
    offer = ShopSong(
        songId = song.songId,
        title = song.title,
        artist = song.artist,
        year = song.year,
        albumArt = song.albumArt,
        shopUrl = "",
        leavingTomorrow = highlight == ShopHighlight.LeavingTomorrow,
        isNew = highlight == ShopHighlight.New,
    ),
    highlight = highlight,
    detailSongId = song.songId,
    officialUrl = null,
)

// endregion

// region Songs: sort, filter and navigation

/** Songs sort sheet (web `SortDemo`): the real mode radio rows, then Sort Direction. */
@Composable
private fun SongsSortDemo(id: String) {
    val modes = remember { SongSortDraft.modes(hideShop = false) }
    var mode by remember { mutableStateOf(modes.first()) }
    var ascending by remember { mutableStateOf(true) }
    DemoFitFirst(remember(modes) { FirstRunDemoFit.sortCandidates(modes.size) }) { fit ->
    Column(Modifier.fillMaxWidth()) {
        modes.take(fit.modes).forEachIndexed { index, option ->
            Box(Modifier.demoEntrance(FirstRunEntrance.rowDelay(id, index))) {
                RadioRow(option.label, option == mode, "fst.first-run.demo.sort.${option.name.lowercase()}") { mode = option }
            }
        }
        if (fit.showDirection) {
            Column(Modifier.demoEntrance(FirstRunEntrance.SECOND_GROUP_MS)) {
                SortDirectionSection(ascending, "fst.first-run.demo.sort") { ascending = it }
            }
        }
    }
    }
}

/** Player history sort sheet (web `ScoreSortDemo`): the real Sort By and Sort Direction groups. */
@Composable
private fun HistorySortDemo(id: String) {
    // The default (Score, descending) leads so the demo shows the sheet's opening state.
    val all = remember { listOf(PlayerScoreSortMode.Score) + (PlayerScoreSortMode.entries - PlayerScoreSortMode.Score) }
    var mode by remember { mutableStateOf(PlayerScoreSortMode.Score) }
    var ascending by remember { mutableStateOf(false) }
    DemoFitFirst(remember { FirstRunDemoFit.sortCandidates(all.size) }) { fit ->
    val modes = all.take(fit.modes)
    ScoreSortControls(
        mode = mode,
        ascending = ascending,
        onMode = { mode = it },
        onAscending = { ascending = it },
        modes = modes,
        modesModifier = Modifier.demoEntrance(FirstRunEntrance.rowDelay(id, 0)),
        directionModifier = Modifier.demoEntrance(FirstRunEntrance.SECOND_GROUP_MS),
        showDirection = fit.showDirection,
    )
    }
}

/** Songs filter sheet (web `FilterDemo`): the real instrument selector, then its score checks. */
@Composable
private fun SongsFilterDemo(id: String) {
    var chart by remember { mutableStateOf(Instrument.Lead) }
    val checks = remember { mutableStateMapOf<SongScoreFilterKind, Boolean>() }
    val kinds = SongScoreFilterKind.offered(filterInvalidScores = false)
    DemoFitFirst(remember(kinds) { FirstRunDemoFit.rowCandidates(kinds.size) }) { rows ->
    Column(Modifier.fillMaxWidth()) {
        InstrumentSelector(
            instruments = ICON_INSTRUMENTS,
            selected = chart,
            onSelect = { next -> if (next != null) chart = next },
            required = true,
            tag = "fst.first-run.demo.instrument",
            modifier = Modifier.padding(vertical = 4.dp).demoEntrance(0),
        )
        kinds.take(rows).forEachIndexed { index, kind ->
            Box(Modifier.demoEntrance(FirstRunEntrance.SECOND_GROUP_MS + FirstRunEntrance.rowDelay(id, index))) {
                ToggleRow(kind.chartLabel(chart), kind.chartDescription(chart), checks[kind] ?: true, enabled = true, tag = "fst.first-run.demo.filter.${kind.name}") { checks[kind] = it }
            }
        }
    }
    }
}

/** The phone navigation bar (web `NavigationDemo`): the real Material 3 navigation suite. */
@Composable
private fun NavigationDemo() {
    val sections = remember { FestivalTabPolicy.sections(ProfileKind.Player, regularWidth = false) }
    var selected by remember { mutableStateOf(sections.first()) }
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Box(Modifier.fillMaxWidth().demoEntrance(FirstRunEntrance.SECOND_GROUP_MS)) {
            ChromeColors {
                NavigationSuite(
                    navigationSuiteType = NavigationSuiteType.ShortNavigationBarCompact,
                    colors = NavigationSuiteDefaults.colors(
                        shortNavigationBarContainerColor = BrandTokens.cardBackground.copy(alpha = 0.96f),
                        shortNavigationBarContentColor = BrandTokens.textPrimary,
                    ),
                    modifier = Modifier.testTag("fst.first-run.demo.nav"),
                ) {
                    sections.forEach { section ->
                        NavigationSuiteItem(
                            selected = section == selected,
                            onClick = { selected = section },
                            icon = { Icon(section.icon(section == selected), contentDescription = null) },
                            label = { Text(section.title, maxLines = 1) },
                            navigationSuiteType = NavigationSuiteType.ShortNavigationBarCompact,
                        )
                    }
                }
            }
        }
    }
}

// endregion

// region Suggestions filters

/** Suggestions filter sheet (web `GlobalFilterDemo`): the real category switches. */
@Composable
private fun SuggestionsGlobalFilterDemo(id: String) {
    val types = SuggestionCategoryType.entries
    val checks = remember { mutableStateMapOf<SuggestionCategoryType, Boolean>() }
    DemoFitFirst(remember { FirstRunDemoFit.rowCandidates(types.size) }) { rows ->
        Column(Modifier.fillMaxWidth()) {
            types.take(rows).forEachIndexed { index, type ->
                Box(Modifier.demoEntrance(FirstRunEntrance.rowDelay(id, index))) {
                    SwitchRow(type.label, checks[type] ?: true, "fst.first-run.demo.suggestion-type.${type.key}", supporting = type.filterDescription) { checks[type] = it }
                }
            }
        }
    }
}

/** Suggestions per-instrument filters (web `InstrumentFilterDemo`): the real chip picker and switches. */
@Composable
private fun SuggestionsInstrumentFilterDemo(id: String) {
    var picked by remember { mutableStateOf(Instrument.Lead) }
    val checks = remember { mutableStateMapOf<Pair<Instrument, SuggestionCategoryType>, Boolean>() }
    val types = SuggestionCategoryType.entries
    DemoFitFirst(remember { FirstRunDemoFit.rowCandidates(types.size) }) { rows ->
        Column(Modifier.fillMaxWidth()) {
            InstrumentTypePicker(ICON_INSTRUMENTS, picked, Modifier.demoEntrance(0)) { picked = it }
            types.take(rows).forEachIndexed { index, type ->
                Box(Modifier.demoEntrance(FirstRunEntrance.SECOND_GROUP_MS + FirstRunEntrance.rowDelay(id, index))) {
                    SwitchRow(type.label, checks[picked to type] ?: true, "fst.first-run.demo.suggestion-type.${type.key}", instrument = picked) { checks[picked to type] = it }
                }
            }
        }
    }
}

// endregion

// region Item Shop

/** Songs rows with the Shop pulse and badges (web `ShopHighlightDemo` and friends). */
@Composable
private fun SongsShopDemo(id: String, active: Boolean) {
    val pulse = rememberShopPulse(active)
    val breathe = rememberShopBreathe(active)
    DemoFitFirst(DEMO_SONG_ROWS) { count ->
    val songs = demoSongs(count, shop = true)
    Column(verticalArrangement = Arrangement.spacedBy(SONG_ROW_GAP)) {
        songs.forEachIndexed { index, song ->
            val modifier = Modifier.demoEntrance(FirstRunEntrance.rowDelay(id, index))
            if (song == null) {
                PlaceholderSongCard(modifier)
            } else {
                val status = FirstRunShopPattern.pulse(id, index, count)
                SongRowCard(
                    title = song.title,
                    subtitle = song.demoSubtitle,
                    artUrl = demoArtUrl(song),
                    onClick = {},
                    modifier = modifier,
                    outline = status?.let { SongsTokens.pulse(it) },
                    pulse = pulse,
                    trailing = { status?.let { ShopBadge(it, song.songId, breathe) } },
                    titleTag = demoSongTag(song.songId),
                )
            }
        }
    }
    }
}

/** Item Shop list rows with New / Leaving Tomorrow outlines and badges (web `ShopListDemo`). */
@Composable
private fun ShopListDemo(id: String, active: Boolean) {
    val pulse = rememberShopPulse(active)
    DemoFitFirst(DEMO_SONG_ROWS) { count ->
    val songs = demoSongs(count, shop = true)
    Column(verticalArrangement = Arrangement.spacedBy(SONG_ROW_GAP)) {
        songs.forEachIndexed { index, song ->
            val modifier = Modifier.demoEntrance(FirstRunEntrance.rowDelay(id, index))
            if (song == null) {
                PlaceholderSongCard(modifier)
            } else {
                val highlight = FirstRunShopPattern.pulse(id, index, count)?.highlight
                ShopListRow(demoOffer(song, highlight), demoArtUrl(song), pulse, onOfficial = {}, onDetail = {}, modifier = modifier, titleTag = demoSongTag(song.songId))
            }
        }
    }
    }
}

/** The Item Shop grid (web `ShopOverviewDemo`): real Shop cards in as many square columns as fit. */
@Composable
private fun ShopGridDemo(id: String, active: Boolean) {
    val pulse = rememberShopPulse(active)
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val grid = remember(maxWidth) { FirstRunDemoFit.squareGrid(maxWidth.value) }
        val songs = demoSongs(grid.count, shop = true)
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            songs.chunked(grid.columns).forEachIndexed { row, chunk ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    chunk.forEachIndexed { column, song ->
                        val modifier = Modifier.size(grid.sideDp.dp).demoEntrance(FirstRunEntrance.rowDelay(id, row * grid.columns + column))
                        Box(modifier) {
                            if (song == null) {
                                Box(Modifier.fillMaxSize().clip(RoundedCornerShape(12.dp)).background(BrandTokens.surfaceMuted).testTag("fst.first-run.demo.placeholder"))
                            } else {
                                ShopGridCard(demoOffer(song, null), demoArtUrl(song), pulse, onOfficial = {}, onDetail = {})
                            }
                        }
                    }
                }
            }
        }
    }
}

/**
 * Song Detail's Item Shop button breathing green, gold or red (web `ShopButtonDemo`); it holds
 * the status colour when inactive, covered or under reduce motion.
 */
@Composable
private fun ShopButtonDemo(id: String, active: Boolean) {
    val pulse = when (id) {
        "songinfo-new-in-shop" -> ShopPulse.New
        "songinfo-leaving-tomorrow" -> ShopPulse.LeavingTomorrow
        else -> ShopPulse.InShop
    }
    val fraction = rememberShopBreathe(active)
    LocalMotionProbe.current?.let { probe ->
        val value = fraction()
        SideEffect { probe(MotionProbes.FIRST_RUN_DEMO_PULSE, value) }
    }
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Box(Modifier.demoEntrance(0)) { ShopActionButton(pulse.highlight, pulse, fraction) {} }
    }
}

// endregion

// region Song Detail

/** Demo history points, oldest first (web `ScoreHistoryChartDemo`). */
private fun demoHistoryPoints(): List<SongHistoryPoint> = FirstRunStillDemoData.HISTORY.reversed().map { score ->
    val date = OffsetDateTime.now().minusDays(score.daysAgo).withNano(0)
    SongHistoryPoint(
        dateKey = date.toString(),
        dateLabel = date.format(DateTimeFormatter.ofPattern("M/d/yy")),
        score = score.score,
        accuracyPercent = score.accuracy,
        isFullCombo = score.fullCombo,
    )
}

/** The real Song Detail history chart in its glass card. */
@Composable
private fun ChartDemo() {
    val points = remember { demoHistoryPoints() }
    GlassCard(Modifier.fillMaxWidth().demoEntrance(0)) {
        Box(Modifier.padding(12.dp)) {
            HistoryChart(points, Instrument.Lead, reservesPager = { false }, plotHeight = 140.dp, showAll = true, detailTag = "fst.first-run.demo.chart.detail", showDetail = false)
        }
    }
}

/**
 * Score History's best-score rows and a pulsing View All Scores ending their card (web
 * `ViewAllScoresDemo`), grouped like Song Detail's Score History card (issue #588).
 */
@Composable
private fun ViewAllDemo(id: String, active: Boolean) {
    val points = remember { demoHistoryPoints().sortedByDescending { it.score } }
    val pulse = rememberShopPulse(active)
    DemoFitFirst(remember(points) { FirstRunDemoFit.rowCandidates(points.size) }) { rows ->
    GlassCard(Modifier.fillMaxWidth().demoEntrance(0).testTag("fst.first-run.demo.history.card")) {
        Column(Modifier.padding(top = 4.dp)) {
            points.take(rows).forEachIndexed { index, point ->
                Column(Modifier.demoEntrance(FirstRunEntrance.rowDelay(id, index))) {
                    if (index > 0) SongRowSeparator()
                    SongHistoryRow(point, best = index == 0, tag = "fst.first-run.demo.history.$index", showSeason = false, grouped = true)
                }
            }
            ViewFullLeaderboardButton(
                onClick = {},
                label = "View All Scores",
                testTag = "fst.first-run.demo.view-all",
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp).demoEntrance(FirstRunEntrance.rowDelay(id, rows)).pulseOutline(BrandTokens.accentPurple, pulse),
            )
        }
    }
    }
}

/** A Song Detail instrument card: header, top score rows and View full leaderboard. */
@Composable
private fun TopScoresDemo(id: String) {
    DemoFitFirst(remember { FirstRunDemoFit.rowCandidates(FirstRunStillDemoData.TOP_SCORES.size) }) { count -> TopScoresCard(id, count) }
}

/**
 * The [TopScoresDemo] card with [count] score rows.
 *
 * @param id Slide ID.
 * @param count Score rows.
 */
@Composable
private fun TopScoresCard(id: String, count: Int) {
    val entries = remember(count) {
        FirstRunStillDemoData.TOP_SCORES.take(count).map {
            LeaderboardEntry(
                accountId = "fst-first-run-${it.rank}",
                displayName = it.name,
                score = it.score,
                rank = it.rank,
                accuracy = it.accuracy * 10_000,
                isFullCombo = it.fullCombo,
                stars = it.stars,
            )
        }
    }
    Column(Modifier.fillMaxWidth()) {
        Box(Modifier.demoEntrance(0)) { SongCardHeader(HEADER_SONG, Instrument.Lead, 1_234) }
        GlassCard(Modifier.fillMaxWidth().demoEntrance(0)) {
            Column(Modifier.padding(vertical = 4.dp)) {
                val columns = rememberScoreColumns(entries)
                LeaderboardSectionMember(columns, "card") {
                    entries.forEachIndexed { index, entry ->
                        Column(Modifier.demoEntrance(FirstRunEntrance.rowDelay(id, index, lead = 1))) {
                            if (index > 0) SongRowSeparator()
                            Box(Modifier.fillMaxWidth()) { ScoreRow(entry, columns = columns.plan) }
                        }
                    }
                }
                ViewFullLeaderboardButton(
                    onClick = {},
                    testTag = "fst.first-run.demo.view-full-leaderboard",
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp).demoEntrance(FirstRunEntrance.rowDelay(id, entries.size + 1)),
                )
            }
        }
    }
}

/** The Paths sheet's instrument and difficulty pickers (web `PathsDemo`). */
@Composable
private fun PathsDemo() {
    var chart by remember { mutableStateOf(Instrument.Lead) }
    var difficulty by remember { mutableStateOf(PathDifficulty.Expert) }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        InstrumentSelector(
            instruments = ICON_INSTRUMENTS,
            selected = chart,
            onSelect = { next -> if (next != null) chart = next },
            required = true,
            tag = "fst.first-run.demo.paths.instrument",
            modifier = Modifier.demoEntrance(0),
        )
        Box(Modifier.demoEntrance(FirstRunEntrance.SECOND_GROUP_MS)) {
            OptionGrid(PathDifficulty.entries, difficulty, { it.label }, "fst.first-run.demo.paths.difficulty") { difficulty = it }
        }
    }
}

// endregion

// region Player history

/** The player history page's score rows, best highlighted (web `ScoreListDemo`). */
@Composable
private fun ScoreListDemo(id: String) {
    DemoFitFirst(remember { FirstRunDemoFit.rowCandidates(FirstRunStillDemoData.HISTORY.size) }) { rows -> ScoreList(id, rows) }
}

/**
 * The [ScoreListDemo] rows.
 *
 * @param id Slide ID.
 * @param rows Rows shown.
 */
@Composable
private fun ScoreList(id: String, rows: Int) {
    val history = remember(rows) {
        val dates = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)
        FirstRunStillDemoData.HISTORY.take(rows).mapIndexed { index, score ->
            ScoreHistoryRow(
                entry = ScoreHistoryEntry(
                    songId = "fst-first-run-demo",
                    instrument = Instrument.Lead.wireId,
                    newScore = score.score,
                    accuracy = score.accuracy * 10_000,
                    isFullCombo = score.fullCombo,
                    changedAt = OffsetDateTime.now().minusDays(score.daysAgo).withNano(0).toString(),
                ),
                isHighScore = index == 0,
                date = LocalDate.now().minusDays(score.daysAgo).format(dates),
            )
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        history.forEachIndexed { index, row ->
            Box(Modifier.demoEntrance(FirstRunEntrance.rowDelay(id, index))) { ProfileHistoryRow(row) }
        }
    }
}

// endregion

// region Leaderboards

/**
 * A Leaderboards instrument card (web `GlobalRankingsDemo`/`YourRankDemo`): the real header,
 * glass card and account ranking rows; [yourRank] centres the window on the purple player row.
 */
@Composable
private fun RankingsCardDemo(id: String, yourRank: Boolean) {
    val pool = if (yourRank) FirstRunStillDemoData.NEIGHBOURHOOD else FirstRunStillDemoData.RANKINGS
    DemoFitFirst(remember(pool) { FirstRunDemoFit.rowCandidates(pool.size) }) { count ->
        val shown = remember(count, yourRank) {
            if (yourRank) pool.slice(FirstRunDemoFit.around(pool.size, FirstRunStillDemoData.PLAYER_INDEX, count)) else pool.take(count)
        }
        DemoRankingsCard(id, shown)
    }
}

/**
 * A Leaderboards instrument card with [shown] players: the real card header (unless
 * [header] is off), glass card and account ranking rows, the player's row highlighted like the
 * real card's own row or pinned footer row.
 *
 * @param id Slide ID (entrance cadence).
 * @param shown Players, in order.
 * @param header Whether the Lead card header shows (the Compete hub demo has none, like the web).
 */
@Composable
internal fun DemoRankingsCard(id: String, shown: List<FirstRunDemoPlayer>, header: Boolean = true) {
    val entries = remember(shown) {
        shown.map { AccountRankingEntry(accountId = "fst-first-run-${it.rank}", displayName = it.name, totalScore = it.score, totalScoreRank = it.rank) }
    }
    Column(Modifier.fillMaxWidth()) {
        if (header) Box(Modifier.demoEntrance(0)) { RankingsCardHeader(Instrument.Lead.label) { InstrumentIcon(Instrument.Lead, size = 40.dp, decorative = true) } }
        GlassCard(Modifier.fillMaxWidth().demoEntrance(0)) {
            var rowWidth by rememberRankingRowWidth()
            val density = LocalDensity.current
            Column(Modifier.padding(8.dp).onSizeChanged { rowWidth = with(density) { it.width.toDp().value } }, verticalArrangement = Arrangement.spacedBy(LEADERBOARD_ROW_GAP)) {
                CompositionLocalProvider(LocalRankingColumns provides rememberAccountColumns(entries, RankingMetric.TotalScore, rowWidth = rowWidth)) {
                    entries.forEachIndexed { index, entry ->
                        Box(Modifier.demoEntrance(FirstRunEntrance.rowDelay(id, index, lead = 1))) {
                            if (index > 0) RankingsRowSeparator(Modifier.align(Alignment.TopCenter))
                            AccountRankingRow(entry, RankingMetric.TotalScore, isSelected = shown[index].isPlayer, route = null, onOpen = {}, tag = "fst.first-run.demo.rank.${shown[index].rank}")
                        }
                    }
                }
            }
        }
    }
}

// endregion

// region Statistics

/** The player page's Select Player Profile button with the web's pulse ring. */
@Composable
private fun SelectProfileDemo(active: Boolean) {
    val pulse = rememberShopPulse(active)
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Button(
            onClick = {},
            colors = festivalFilledButtonColors(),
            modifier = Modifier.heightIn(min = 48.dp).demoEntrance(0).pulseOutline(BrandTokens.accentPurple, pulse, corner = 24.dp),
        ) { Text("Select Player Profile") }
    }
}

/**
 * Statistics stat tiles in the page's grid columns (web `OverviewDemo`, `DrillDownDemo`,
 * `InstrumentBreakdownDemo`); clickable tiles carry the chevron and the drill-down pulse.
 */
@Composable
private fun StatTilesDemo(id: String, stats: List<FirstRunDemoStat>, active: Boolean, heading: Instrument? = null) {
    val pulse = rememberShopPulse(active)
    val spacing = StatGridColumns.SPACING_DP
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val columns = StatGridColumns.count(maxWidth.value)
        val maxRows = (stats.size + columns - 1) / columns
        val lead = if (heading != null) 1 else 0
        DemoFitFirst(remember(maxRows) { FirstRunDemoFit.rowCandidates(maxRows) }) { rows ->
        Column(verticalArrangement = Arrangement.spacedBy(spacing.dp)) {
            heading?.let { Box(Modifier.demoEntrance(0)) { InstrumentHeading(it, "fst.first-run.demo.heading") } }
            stats.take(columns * rows).chunked(columns).forEachIndexed { row, chunk ->
                Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(spacing.dp)) {
                    chunk.forEachIndexed { column, stat ->
                        val tappable = stat.clickable || heading != null
                        StatTile(
                            PlayerStatTile(id = stat.label, label = stat.label, value = stat.value, tint = if (stat.gold) StatTints.GOLD else null),
                            onClick = if (tappable) ({}) else null,
                            modifier = Modifier.weight(1f).fillMaxHeight()
                                .demoEntrance(FirstRunEntrance.rowDelay(id, row * columns + column, lead))
                                .then(if (stat.clickable) Modifier.pulseOutline(BrandTokens.accentPurple, pulse) else Modifier),
                        )
                    }
                    repeat(columns - chunk.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
        }
    }
}

/** The player page's percentile table (web `PercentileDemo`). */
@Composable
private fun PercentilesDemo() {
    DemoFitFirst(remember { FirstRunDemoFit.rowCandidates(FirstRunStillDemoData.PERCENTILES.size) }) { rows ->
        val table = remember(rows) { FirstRunStillDemoData.PERCENTILES.take(rows).map { (top, count) -> PercentileRow(PlayerPercentileBucket(top, count)) } }
        PercentileTable(table, canRun = { false }, onAction = {}, modifier = Modifier.demoEntrance(0))
    }
}

// endregion
