package com.festivalscoretracker.android.ui.songdetail

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.paths.PathCapability
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.shop.ShopPayload
import com.festivalscoretracker.android.core.shop.ShopPresentationPolicy
import com.festivalscoretracker.android.core.shop.ShopResponse
import com.festivalscoretracker.android.core.shop.SongRelatedPublicationPolicy
import com.festivalscoretracker.android.data.paths.pathData
import com.festivalscoretracker.android.data.paths.pathImage
import com.festivalscoretracker.android.data.songs.leaderboardPage
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.SongDetailViewModel
import com.festivalscoretracker.android.presentation.ShellViewModel
import com.festivalscoretracker.android.presentation.profile.SelectedProfileState
import com.festivalscoretracker.android.presentation.songs.InvalidScoreContext
import com.festivalscoretracker.android.presentation.songs.SongDetailSummary
import com.festivalscoretracker.android.presentation.songs.SongPathsViewModel
import com.festivalscoretracker.android.presentation.songs.songScoreSource
import com.festivalscoretracker.android.presentation.valueOrNull
import kotlinx.coroutines.launch

// region Route

/**
 * Song Detail wiring: the detail view model plus same-publication Shop offer,
 * selected-player summaries, invalid-score leeway and the Paths sheet.
 *
 * @param container Process dependencies.
 * @param shellViewModel Shell (settings persistence).
 * @param settings Current settings.
 * @param songId Route song ID (or debug title).
 * @param embedded Inside a two-pane layout.
 */
@Composable
fun SongDetailRouteScreen(container: AppContainer, shellViewModel: ShellViewModel, settings: AppSettings, songId: String, embedded: Boolean) {
    val api = container.api
    val currentSettings by rememberUpdatedState(settings)
    val viewModel: SongDetailViewModel = viewModel(key = "detail:$songId") {
        SongDetailViewModel(
            songKey = songId,
            loadCatalog = { api.catalog(it) },
            loadLeaderboard = { id, chart, page, top, leeway -> api.leaderboardPage(id, chart, page, top, leeway) },
            backoff = container.backoff,
            leeway = { currentSettings.leeway.takeIf { currentSettings.filterInvalidScores } },
        )
    }
    LaunchedEffect(settings.hideShop) { if (!settings.hideShop) container.shop.ensureStarted() }
    val shop by container.shop.state.collectAsStateWithLifecycle()
    val profile by container.selectedProfile.state.collectAsStateWithLifecycle()
    val publication by api.publicationChanges.collectAsStateWithLifecycle()
    val catalogPublication by viewModel.catalogPublication.collectAsStateWithLifecycle()
    val songState by viewModel.song.collectAsStateWithLifecycle()
    val song = songState.valueOrNull
    val extras = remember(song, settings, shop, profile, publication, catalogPublication) {
        song?.let { songDetailExtras(it, settings, shop, profile, catalogPublication, publication ?: catalogPublication) } ?: SongDetailExtras(settings.visibleInstruments)
    }
    var pathsFor by rememberSaveable { mutableStateOf<String?>(null) }
    SongDetailScreen(viewModel, extras, api::artworkUrl, container.background, embedded) { pathsFor = it.songId }
    val scope = rememberCoroutineScope()
    if (song != null && pathsFor == song.songId && extras.pathInstruments.isNotEmpty()) {
        val pathsViewModel: SongPathsViewModel = viewModel(key = "paths:${song.songId}:${extras.pathInstruments}") {
            SongPathsViewModel(
                instruments = extras.pathInstruments,
                defaultDisplay = settings.pathDefaultView,
                loadImage = { chart, difficulty -> api.pathImage(song.songId, chart, difficulty, song.pathArtifactGenerationId) },
                loadText = { chart, difficulty -> api.pathData(song.songId, chart, difficulty, song.pathArtifactGenerationId) },
            )
        }
        SongPathsSheet(
            viewModel = pathsViewModel,
            songTitle = song.title,
            columns = settings.pathColumnOrder,
            showKaraokeWarning = PathCapability.showsKaraokeWarning(settings.visibleInstruments, settings.pathUnavailableWarningDismissed),
            onDontShowAgain = { scope.launch { container.settings.update { it.copy(pathUnavailableWarningDismissed = true) } } },
            onDismiss = { pathsFor = null },
        )
    }
}

/**
 * Derive Song Detail extras.
 *
 * @param song Resolved song.
 * @param settings Settings.
 * @param shop Shop state.
 * @param profile Selected-profile state.
 * @param catalogPublication Catalogue generation.
 * @param current Latest generation.
 * @return Extras.
 */
internal fun songDetailExtras(
    song: Song,
    settings: AppSettings,
    shop: LoadState<ShopPayload>,
    profile: SelectedProfileState,
    catalogPublication: Int?,
    current: Int?,
): SongDetailExtras {
    val player = settings.selectedPlayer
    val invalid = if (settings.filterInvalidScores) InvalidScoreContext(settings.leeway, mapOf(song.songId to song)) else null
    val source = if (player == null) null else profile.songScoreSource(catalogPublication, current, invalid)
    val summaries = if (source == null || player == null) {
        emptyMap()
    } else {
        Instrument.entries.filter { it in settings.visibleInstruments && song.supports(it) }
            .mapNotNull { chart -> SongDetailSummary.summary(source, player.displayName, song, chart)?.let { chart to it } }
            .toMap()
    }
    val payload = shop.valueOrNull
    val offer = payload?.takeIf { SongRelatedPublicationPolicy.matches(catalogPublication, it.observedPublicationId, current) }?.offersById?.get(song.songId)
    return SongDetailExtras(
        visibleInstruments = settings.visibleInstruments,
        selectedAccountId = player?.accountId,
        summaries = summaries,
        shopHighlight = if (settings.hideShop) null else ShopPresentationPolicy.highlight(offer, settings.hideShop, settings.disableShopHighlighting),
        shopPulse = ShopPresentationPolicy.pulse(offer, settings.hideShop, settings.disableShopHighlighting),
        shopUrl = if (settings.hideShop) null else offer?.shopUrl?.takeIf(ShopResponse::isOfficialShopUrl),
        shopError = !settings.hideShop && shop is LoadState.Failed,
        pathInstruments = PathCapability.menuInstruments(settings.visibleInstruments, song::supports),
    )
}

// endregion
