package com.festivalscoretracker.android

import android.os.Bundle
import android.os.SystemClock
import android.graphics.Color
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.windowsizeclass.ExperimentalMaterial3WindowSizeClassApi
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.PermanentDrawerSheet
import androidx.compose.material3.PermanentNavigationDrawer
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.windowsizeclass.WindowWidthSizeClass
import androidx.compose.material3.windowsizeclass.calculateWindowSizeClass
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.viewModelScope
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowInfoTracker
import com.festivalscoretracker.android.data.CatalogSource
import com.festivalscoretracker.android.data.MonotonicClock
import com.festivalscoretracker.android.data.Song
import com.festivalscoretracker.android.data.SongCatalog
import com.festivalscoretracker.android.data.SongCatalogDecoder
import com.festivalscoretracker.android.data.SongCatalogRepository
import com.festivalscoretracker.android.data.TransportPolicy
import com.festivalscoretracker.android.ui.DifficultyMeter
import com.festivalscoretracker.android.ui.FestivalTheme
import java.net.URI
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

// region Lifecycle and state

/** A single native activity; the preview catalog never reaches a production service. */
@OptIn(ExperimentalMaterial3WindowSizeClassApi::class)
class MainActivity : ComponentActivity() {
    private lateinit var catalogModel: CatalogViewModel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
        )
        TransportPolicy(URI(BuildConfig.SONGS_ORIGIN), BuildConfig.FIXTURE_ONLY)
        val repository = SongCatalogRepository(
            CatalogSource {
                applicationContext.assets.open("songs.json").bufferedReader().use(SongCatalogDecoder::decode)
            },
            MonotonicClock(SystemClock::elapsedRealtime),
        )
        catalogModel = ViewModelProvider(this, object : ViewModelProvider.Factory {
            override fun <T : ViewModel> create(modelClass: Class<T>): T {
                require(modelClass == CatalogViewModel::class.java)
                return modelClass.cast(CatalogViewModel(repository))
                    ?: error("Unable to create catalog model")
            }
        })[CatalogViewModel::class.java]
        catalogModel.load()
        val separatingHinge = mutableStateOf(false)
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                WindowInfoTracker.getOrCreate(this@MainActivity)
                    .windowLayoutInfo(this@MainActivity).collect { info ->
                        separatingHinge.value = info.displayFeatures
                            .filterIsInstance<FoldingFeature>()
                            .any { it.isSeparating }
                    }
            }
        }
        setContent {
            FestivalApp(
                catalogModel = catalogModel,
                widthClass = calculateWindowSizeClass(this).widthSizeClass,
                separatingHinge = separatingHinge.value,
            )
        }
    }
}

/** Explicit loading, ready and error states for the fixture-backed Songs preview. */
sealed interface CatalogState {
    data object Loading : CatalogState
    data class Ready(val catalog: SongCatalog) : CatalogState
    data class Failed(val reason: String) : CatalogState
}

/** Keeps the pinned publication across activity recreation and exposes errors to the shell. */
class CatalogViewModel(private val repository: SongCatalogRepository) : ViewModel() {
    private val mutableState = MutableStateFlow<CatalogState>(CatalogState.Loading)
    val state: StateFlow<CatalogState> = mutableState

    /** Loads the pinned catalog off the UI thread. */
    fun load() {
        if (mutableState.value is CatalogState.Ready) return
        mutableState.value = CatalogState.Loading
        viewModelScope.launch(Dispatchers.IO) {
            try {
                mutableState.value = CatalogState.Ready(repository.get())
            } catch (error: Exception) {
                mutableState.value = CatalogState.Failed(error.message ?: "Catalog unavailable")
            }
        }
    }
}

// endregion

// region Adaptive navigation

private enum class Destination(val label: String, val testId: String) {
    Songs("Songs", "fst.nav.songs"),
    Settings("Settings", "fst.nav.settings"),
}

/** A bar on compact, rail on medium, and permanent drawer plus list/detail on expanded windows. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FestivalApp(catalogModel: CatalogViewModel, widthClass: WindowWidthSizeClass, separatingHinge: Boolean) {
    val catalogState by catalogModel.state.collectAsStateWithLifecycle()
    var destination by rememberSaveable { mutableStateOf(Destination.Songs) }
    var selectedSongId by rememberSaveable { mutableStateOf<String?>(null) }
    var extraContrast by rememberSaveable { mutableStateOf(false) }
    val expanded = widthClass == WindowWidthSizeClass.Expanded
    BackHandler(destination != Destination.Songs || selectedSongId != null) {
        if (selectedSongId != null) selectedSongId = null else destination = Destination.Songs
    }
    val navigate: (Destination) -> Unit = {
        destination = it
        selectedSongId = null
    }
    val content: @Composable () -> Unit = {
        Scaffold(
            topBar = { TopAppBar(title = { Text(destination.label) }) },
            bottomBar = {
                if (widthClass == WindowWidthSizeClass.Compact) {
                    NavigationBar {
                        Destination.entries.forEach { item ->
                            NavigationBarItem(
                                selected = destination == item,
                                onClick = { navigate(item) },
                                label = { Text(item.label) },
                                icon = {
                                    Text(if (item == Destination.Songs) "♪" else "⚙",
                                        Modifier.clearAndSetSemantics { })
                                },
                                modifier = Modifier.testTag(item.testId),
                            )
                        }
                    }
                }
            },
        ) { padding ->
            Row(Modifier.fillMaxSize().padding(padding)) {
                if (widthClass == WindowWidthSizeClass.Medium) {
                    NavigationRail {
                        Destination.entries.forEach { item ->
                            NavigationRailItem(
                                selected = destination == item,
                                onClick = { navigate(item) },
                                label = { Text(item.label) },
                                icon = {
                                    Text(if (item == Destination.Songs) "♪" else "⚙",
                                        Modifier.clearAndSetSemantics { })
                                },
                                modifier = Modifier.testTag(item.testId),
                            )
                        }
                    }
                }
                when (destination) {
                    Destination.Songs -> SongsScreen(
                        catalogState, selectedSongId, expanded, separatingHinge,
                        onSelect = { selectedSongId = it }, onRetry = catalogModel::load,
                    )
                    Destination.Settings -> SettingsScreen(
                        extraContrast, { extraContrast = it },
                    )
                }
            }
        }
    }
    FestivalTheme(extraContrast) {
        if (expanded) {
            PermanentNavigationDrawer(
                drawerContent = {
                    PermanentDrawerSheet(modifier = Modifier.width(240.dp)) {
                        Spacer(Modifier.padding(12.dp))
                        Destination.entries.forEach { item ->
                            NavigationDrawerItem(
                                label = { Text(item.label) },
                                selected = destination == item,
                                onClick = { navigate(item) },
                                modifier = Modifier.testTag(item.testId),
                            )
                        }
                    }
                },
                content = content,
            )
        } else content()
    }
}

// endregion

// region Songs and settings surfaces

/** Preview Songs with a publication label and an adaptive list/detail selection. */
@Composable
fun SongsScreen(
    state: CatalogState,
    selectedSongId: String?,
    expanded: Boolean,
    separatingHinge: Boolean,
    onSelect: (String) -> Unit,
    onRetry: () -> Unit,
) {
    when (state) {
        CatalogState.Loading -> Text("Loading bundled preview…", Modifier.padding(20.dp).testTag("fst.songs.loading"))
        is CatalogState.Failed -> Column(Modifier.padding(20.dp).testTag("fst.songs.error")) {
            Text("Preview unavailable: ${state.reason}")
            Button(onClick = onRetry, modifier = Modifier.testTag("fst.songs.retry")) {
                Text("Retry")
            }
        }
        is CatalogState.Ready -> {
            val catalog = state.catalog
            val selected = catalog.songs.find { it.id == selectedSongId }
            if (expanded) {
                Row(Modifier.fillMaxSize()) {
                    SongList(catalog, selectedSongId, Modifier.weight(1f).fillMaxHeight(), onSelect)
                    if (separatingHinge) Spacer(Modifier.width(16.dp))
                    SongDetail(selected, Modifier.weight(1f).fillMaxHeight())
                }
            } else if (selected != null) {
                SongDetail(selected, Modifier.fillMaxSize())
            } else {
                SongList(catalog, selectedSongId, Modifier.fillMaxSize(), onSelect)
            }
        }
    }
}

/** The fixture publication stays visibly distinct from live service data. */
@Composable
fun SongList(catalog: SongCatalog, selectedSongId: String?, modifier: Modifier, onSelect: (String) -> Unit) {
    LazyColumn(modifier.testTag("fst.songs.list")) {
        item {
            Text(catalog.publication, Modifier.padding(16.dp).testTag("fst.songs.publication"),
                style = MaterialTheme.typography.titleMedium)
            HorizontalDivider()
        }
        items(catalog.songs, key = Song::id) { song ->
            ListItem(
                headlineContent = { Text(song.title) },
                supportingContent = { Text(song.artist) },
                trailingContent = { DifficultyMeter(song.difficulty) },
                modifier = Modifier
                    .fillMaxWidth()
                    .selectable(selectedSongId == song.id, onClick = { onSelect(song.id) }, role = Role.Button)
                    .testTag("fst.songs.row.${song.id}"),
            )
            HorizontalDivider()
        }
    }
}

/** Placeholder detail makes selection and native back behavior testable without inventing leaderboard routes. */
@Composable
fun SongDetail(song: Song?, modifier: Modifier) {
    Column(modifier.padding(24.dp).testTag("fst.songs.detail"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (song == null) {
            Text("Select a song", style = MaterialTheme.typography.titleLarge)
        } else {
            Text(song.title, style = MaterialTheme.typography.headlineMedium)
            Text(song.artist)
            DifficultyMeter(song.difficulty)
            Text("Bundled preview · leaderboards not connected")
        }
    }
}

/** Session-local contrast can only add to OS accessibility preferences. */
@Composable
fun SettingsScreen(
    extraContrast: Boolean,
    onContrastChange: (Boolean) -> Unit,
) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).testTag("fst.settings"),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Accessibility", Modifier.padding(16.dp), style = MaterialTheme.typography.titleLarge)
        ListItem(
            headlineContent = { Text("Additional contrast") },
            supportingContent = { Text("Add contrast for this session; system accessibility stays enabled") },
            trailingContent = {
                Switch(extraContrast, onContrastChange,
                    Modifier.testTag("fst.settings.contrast")
                        .semantics { contentDescription = "Additional contrast" })
            },
        )
        Text("Motion follows system settings; this preview adds no animations.", Modifier.padding(16.dp))
        Text("Preview settings · no account or service connection",
            Modifier.padding(16.dp).testTag("fst.settings.preview"))
    }
}

// endregion
