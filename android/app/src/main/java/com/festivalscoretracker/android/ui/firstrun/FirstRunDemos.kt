package com.festivalscoretracker.android.ui.firstrun

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.EmojiEvents
import androidx.compose.material.icons.outlined.LibraryMusic
import androidx.compose.material.icons.outlined.PersonAdd
import androidx.compose.material.icons.outlined.Route
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.ShoppingBag
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.firstrun.FirstRunRotatingDemos
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.ui.design.InstrumentIcon
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility

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
 * A non-networked mini-demo for one slide (web `pages/<page>/firstRun/demo/`), built
 * from shared design primitives. The twelve web demos that swap data on a timer rotate
 * through [FirstRunRotatingDemo] (issue #58); the rest are still, with pulses only for
 * the settled current page and never under reduce motion.
 *
 * @param id Slide ID.
 * @param active Whether the slide is the settled current page.
 */
@Composable
fun FirstRunDemo(id: String, active: Boolean) {
    if (id in FirstRunRotatingDemos.IDS) {
        FirstRunRotatingDemo(id, active)
        return
    }
    val pulse = active && !LocalFestivalAccessibility.current.reduceMotion
    when (id) {
        "songs-sort" -> SortList(listOf("Title", "Artist", "Year", "Duration"), "Title")
        "songs-navigation" -> NavigationReplica()
        "songs-filter", "suggestions-global-filter" -> FilterDemo(showInstruments = id == "songs-filter")
        "suggestions-instrument-filter" -> FilterDemo(showInstruments = true)
        "songs-shop-highlight", "shop-highlighting" -> SongRows(3, highlight = BrandTokens.statusGreen, pulse = pulse)
        "songs-new-in-shop", "shop-new-items" -> SongRows(3, highlight = BrandTokens.gold, pulse = pulse)
        "songs-leaving-tomorrow", "shop-leaving-tomorrow" -> SongRows(3, highlight = BrandTokens.statusRed, pulse = pulse)
        "songinfo-chart" -> BarChart(selectLast = false)
        "songinfo-view-all", "playerhistory-score-list" -> ScoreRows(pulse)
        "songinfo-top-scores", "leaderboards-overview", "compete-leaderboards" -> RankRows(highlightYou = false)
        "leaderboards-your-rank" -> RankRows(highlightYou = true)
        "songinfo-paths" -> IconTile(Icons.Outlined.Route, "View Paths")
        "songinfo-shop-button" -> Pill("Item Shop", BrandTokens.statusGreen, pulse)
        "songinfo-new-in-shop" -> Pill("Item Shop", BrandTokens.gold, pulse)
        "songinfo-leaving-tomorrow" -> Pill("Item Shop", BrandTokens.statusRed, pulse)
        "playerhistory-sort" -> SortList(listOf("Date", "Score", "Accuracy", "Season"), "Date")
        "statistics-select-profile" -> Pill("Select Player Profile", BrandTokens.accentPurple, pulse, Icons.Outlined.PersonAdd)
        "statistics-drill-down", "statistics-overview", "statistics-instrument-breakdown" -> StatGrid(chevrons = id == "statistics-drill-down")
        "statistics-percentiles" -> PercentileTable()
        "suggestions-infinite-scroll" -> CategoryCard()
        "shop-overview" -> ShopGrid()
        else -> IconTile(Icons.Outlined.AutoAwesome, null)
    }
}

// endregion

// region Sample data

private val demoSongs = listOf("Synthetic Anthem" to "Demo Band", "Placeholder Groove" to "Sample Artist", "Example Encore" to "The Fixtures")
private val demoPlayers = listOf("Player One", "Player Two", "You", "Player Four", "Player Five")

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

@Composable
private fun pulseAlpha(pulse: Boolean): Float {
    if (!pulse) return 1f
    val transition = rememberInfiniteTransition(label = "pulse")
    val value by transition.animateFloat(0.35f, 1f, infiniteRepeatable(tween(900), RepeatMode.Reverse), label = "alpha")
    return value
}

@Composable
private fun SongRows(count: Int, highlight: Color? = null, pulse: Boolean = false, badges: Boolean = false) {
    val alpha = pulseAlpha(pulse && highlight != null)
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        demoSongs.take(count).forEachIndexed { index, (title, artist) ->
            val border = if (highlight != null && index != 1) highlight.copy(alpha = alpha) else BrandTokens.glassBorder
            DemoCard(border = border) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(36.dp).background(BrandTokens.surfaceMuted, RoundedCornerShape(6.dp)))
                    Column(Modifier.weight(1f).padding(start = 10.dp)) {
                        Text(title, color = BrandTokens.textPrimary, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold, maxLines = 1)
                        Text(artist, color = BrandTokens.textSecondary, style = MaterialTheme.typography.bodySmall, maxLines = 1)
                    }
                    if (badges) {
                        Text("Top ${index * 4 + 1}%", color = BrandTokens.gold, style = MaterialTheme.typography.labelMedium)
                    } else {
                        InstrumentIcon(Instrument.entries[index], size = 22.dp, decorative = true)
                    }
                }
            }
        }
    }
}

@Composable
private fun SortList(modes: List<String>, selected: String) {
    DemoCard {
        Column {
            modes.forEach { mode ->
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.height(36.dp)) {
                    RadioButton(selected = mode == selected, onClick = null)
                    Text(mode, color = BrandTokens.textPrimary, modifier = Modifier.padding(start = 8.dp).weight(1f))
                    if (mode == selected) Icon(Icons.Filled.ArrowUpward, contentDescription = null, tint = BrandTokens.textSecondary)
                }
            }
        }
    }
}

@Composable
private fun NavigationReplica() {
    DemoCard {
        Row(horizontalArrangement = Arrangement.SpaceEvenly, modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
            listOf(Icons.Outlined.LibraryMusic to "Songs", Icons.Outlined.EmojiEvents to "Leaderboards", Icons.Outlined.Settings to "Settings").forEachIndexed { index, (icon, label) ->
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(
                        Modifier.background(if (index == 0) BrandTokens.accentPurple.copy(alpha = 0.45f) else Color.Transparent, RoundedCornerShape(16.dp))
                            .padding(horizontal = 16.dp, vertical = 4.dp),
                    ) { Icon(icon, contentDescription = null, tint = BrandTokens.textPrimary) }
                    Text(label, color = BrandTokens.textSecondary, style = MaterialTheme.typography.labelSmall)
                }
            }
        }
    }
}

@Composable
private fun FilterDemo(showInstruments: Boolean) {
    DemoCard {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            if (showInstruments) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Instrument.entries.take(5).forEach { InstrumentIcon(it, size = 26.dp, decorative = true) }
                }
            } else {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.FilterList, contentDescription = null, tint = BrandTokens.textPrimary)
                    Text("Filter", color = BrandTokens.textPrimary, modifier = Modifier.padding(start = 8.dp))
                }
            }
            listOf("Missing scores" to true, "Missing FCs" to false).forEach { (label, on) ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(label, color = BrandTokens.textPrimary, modifier = Modifier.weight(1f))
                    Switch(checked = on, onCheckedChange = null)
                }
            }
        }
    }
}

@Composable
private fun BarChart(selectLast: Boolean) {
    val values = listOf(0.62f, 0.71f, 0.8f, 0.77f, 0.93f, 1f)
    DemoCard {
        Canvas(Modifier.fillMaxWidth().height(160.dp)) {
            val gap = 10.dp.toPx()
            val width = (size.width - gap * (values.size - 1)) / values.size
            values.forEachIndexed { index, value ->
                val height = size.height * value
                val x = index * (width + gap)
                val color = if (index == values.lastIndex) BrandTokens.gold else BrandTokens.accentBlue
                drawRoundRect(color, Offset(x, size.height - height), Size(width, height), CornerRadius(6f, 6f))
                if (selectLast && index == values.lastIndex) {
                    drawRoundRect(BrandTokens.textPrimary, Offset(x, size.height - height), Size(width, height), CornerRadius(6f, 6f), style = androidx.compose.ui.graphics.drawscope.Stroke(3.dp.toPx()))
                }
            }
        }
    }
}

@Composable
private fun ScoreRows(pulse: Boolean) {
    val alpha = pulseAlpha(pulse)
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        listOf("1,000,000" to "100%", "987,654" to "99.1%", "912,345" to "97.4%").forEachIndexed { index, (score, accuracy) ->
            DemoCard(border = if (index == 0) BrandTokens.accentPurple.copy(alpha = alpha) else BrandTokens.glassBorder) {
                Row {
                    Text(score, color = BrandTokens.textPrimary, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                    Text(accuracy, color = if (index == 0) BrandTokens.gold else BrandTokens.textSecondary)
                }
            }
        }
    }
}

@Composable
private fun RankRows(highlightYou: Boolean) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        demoPlayers.forEachIndexed { index, name ->
            val you = highlightYou && name == "You"
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth()
                    .background(if (you) BrandTokens.accentPurple.copy(alpha = 0.5f) else BrandTokens.surfaceFrosted, RoundedCornerShape(8.dp))
                    .padding(horizontal = 12.dp, vertical = 6.dp),
            ) {
                Text("#${index + 1}", color = BrandTokens.textSecondary, modifier = Modifier.padding(end = 12.dp))
                Text(if (!highlightYou && name == "You") "Player Three" else name, color = BrandTokens.textPrimary, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text("${(1_000_000 - index * 12_345).let { "%,d".format(it) }}", color = BrandTokens.textSecondary)
            }
        }
    }
}

@Composable
private fun StatGrid(chevrons: Boolean) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        listOf(listOf("Songs Played" to "412", "Full Combos" to "128"), listOf("Gold Stars" to "96", "Best Rank" to "#42")).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                row.forEach { (label, value) ->
                    DemoCard(Modifier.weight(1f)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(value, color = BrandTokens.textPrimary, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                                Text(label, color = BrandTokens.textSecondary, style = MaterialTheme.typography.labelMedium)
                            }
                            if (chevrons) Icon(Icons.Filled.ChevronRight, contentDescription = null, tint = BrandTokens.textSecondary)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PercentileTable() {
    DemoCard {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            listOf("Top 1%" to "12", "Top 5%" to "48", "Top 10%" to "97", "Top 25%" to "180").forEach { (bracket, count) ->
                Row {
                    Text(bracket, color = BrandTokens.textPrimary, modifier = Modifier.weight(1f))
                    Text(count, color = BrandTokens.textSecondary)
                }
            }
        }
    }
}

@Composable
private fun CategoryCard() {
    DemoCard(border = BrandTokens.accentPurple) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.AutoAwesome, contentDescription = null, tint = BrandTokens.gold)
                Text("Almost Full Combo", color = BrandTokens.textPrimary, fontWeight = FontWeight.Bold, modifier = Modifier.padding(start = 8.dp))
            }
            SongRows(2)
        }
    }
}

@Composable
private fun ShopGrid() {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        repeat(2) { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                repeat(3) { col ->
                    Box(
                        Modifier.weight(1f).height(72.dp).background(BrandTokens.surfaceMuted, RoundedCornerShape(10.dp))
                            .border(1.dp, if ((row + col) % 3 == 0) BrandTokens.statusGreen else BrandTokens.glassBorder, RoundedCornerShape(10.dp)),
                        contentAlignment = Alignment.Center,
                    ) { Icon(Icons.Outlined.ShoppingBag, contentDescription = null, tint = BrandTokens.textSecondary) }
                }
            }
        }
    }
}

@Composable
private fun Pill(label: String, color: Color, pulse: Boolean, icon: ImageVector = Icons.Outlined.ShoppingBag) {
    val alpha = pulseAlpha(pulse)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .background(color.copy(alpha = 0.25f), RoundedCornerShape(50))
            .border(2.dp, color.copy(alpha = alpha), RoundedCornerShape(50))
            .padding(horizontal = 20.dp, vertical = 10.dp),
    ) {
        Icon(icon, contentDescription = null, tint = BrandTokens.textPrimary)
        Text(label, color = BrandTokens.textPrimary, fontWeight = FontWeight.Bold, modifier = Modifier.padding(start = 8.dp))
    }
}

@Composable
private fun IconTile(icon: ImageVector, label: String?) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.size(96.dp).background(BrandTokens.accentPurple.copy(alpha = 0.35f), CircleShape), contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = BrandTokens.textPrimary, modifier = Modifier.size(48.dp))
        }
        if (label != null) {
            Text(label, color = BrandTokens.textPrimary, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 12.dp))
        }
    }
}

// endregion
