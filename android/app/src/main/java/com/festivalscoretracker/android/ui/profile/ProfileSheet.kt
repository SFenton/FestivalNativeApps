package com.festivalscoretracker.android.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.DockedSearchBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.search.GlobalSearchResults
import com.festivalscoretracker.android.core.search.SearchDestination
import com.festivalscoretracker.android.core.search.SearchScope
import com.festivalscoretracker.android.presentation.search.GlobalSearchUiState
import com.festivalscoretracker.android.presentation.search.GlobalSearchViewModel
import com.festivalscoretracker.android.ui.common.FestivalAlertDialog
import com.festivalscoretracker.android.ui.common.FestivalEmptyState
import com.festivalscoretracker.android.ui.common.FestivalLoading
import com.festivalscoretracker.android.ui.common.FestivalModalSheet
import com.festivalscoretracker.android.ui.design.SectionHeader
import com.festivalscoretracker.android.ui.design.festivalFilledButtonColors
import com.festivalscoretracker.android.ui.search.SearchAnnouncement
import com.festivalscoretracker.android.ui.search.SearchResultTags
import com.festivalscoretracker.android.ui.search.rememberSearchResultsRevealed
import com.festivalscoretracker.android.ui.search.searchResultItems
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Test IDs

/** `fst.profile.*` search tags (issue #600: the sheet shows global search's rows). */
object ProfileSheetTags {
    /** All · Players · Bands segmented row. */
    const val SCOPES = "fst.profile.scope"

    /** Search field. */
    const val SEARCH = "fst.profile.search"

    /** Clear-text button. */
    const val CLEAR = "fst.profile.clear"

    /** Short-query hint. */
    const val HINT = "fst.profile.hint"

    /** Centred spinner. */
    const val LOADING = "fst.profile.loading"

    /** Centred title-and-subtitle empty state. */
    const val EMPTY = "fst.profile.empty"

    /** Polite result-count status. */
    const val STATUS = "fst.profile.status"

    /** Players failure line. */
    const val PLAYERS_ERROR = "fst.profile.players-error"

    /** Bands failure line. */
    const val BANDS_ERROR = "fst.profile.bands-error"

    /**
     * Scope segment tag.
     *
     * @param scope Segment scope.
     * @return Tag.
     */
    fun scope(scope: SearchScope) = "fst.profile.scope.${scope.token}"

    /**
     * Player result row tag.
     *
     * @param accountId Player.
     * @return Tag.
     */
    fun player(accountId: String) = "fst.profile.result.$accountId"

    /**
     * Band result card tag.
     *
     * @param key Band row key.
     * @return Tag.
     */
    fun band(key: String) = "fst.profile.band.$key"

    /**
     * All-scope section title tag.
     *
     * @param scope Section.
     * @return Tag.
     */
    fun section(scope: SearchScope) = "fst.profile.section.${scope.token}"

    /** Result row tags for [searchResultItems]. */
    internal val results = SearchResultTags(
        player = { player(it.accountId) },
        band = { band(it.key) },
        section = ::section,
        playersError = PLAYERS_ERROR,
        bandsError = BANDS_ERROR,
    )
}

// endregion

// region Sheet

/**
 * Profile discovery (web `SearchModal` with targets `players|bands`, issue #600): the selected
 * player's summary, an All · Players · Bands segmented scope (starting on All) and a Material 3
 * search field over global search's own engine and rows (pattern search-scopes). Players and
 * bands are searched together; the scope only filters what shows. A player result **views** the
 * player (selecting happens on the player page); a band result opens its Band page, since Android
 * can't select a band as the profile yet.
 *
 * @param player Selected player.
 * @param searchViewModel Global search engine narrowed to [SearchScope.profileTargets].
 * @param onOpen Dismiss-then-open a result (player page, Statistics or Band page).
 * @param onViewPlayer Dismiss-then-push the selected player's page.
 * @param onDeselect Deselect the selected player (after confirmation).
 * @param onDismiss Close.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileSheet(
    player: SelectedPlayer?,
    searchViewModel: GlobalSearchViewModel,
    onOpen: (SearchDestination) -> Unit,
    onViewPlayer: (accountId: String, displayName: String) -> Unit,
    onDeselect: () -> Unit,
    onDismiss: () -> Unit,
) {
    var confirmDeselect by rememberSaveable { mutableStateOf(false) }
    val ui by searchViewModel.state.collectAsStateWithLifecycle()
    FestivalModalSheet(
        title = "Profiles",
        closeTag = "fst.profile.close",
        onDismissRequest = onDismiss,
        modifier = Modifier.testTag("fst.profile.sheet"),
    ) {
        val revealed = rememberSearchResultsRevealed(ui)
        // Result rows carry their own 16 dp inset; headers and controls add it here so every
        // leading edge lines up at 24 dp.
        LazyColumn(Modifier.fillMaxWidth().padding(horizontal = 8.dp).testTag("fst.profile.results"), state = rememberLazyListState()) {
            if (player != null) {
                item(key = "selected") {
                    Column(Modifier.padding(horizontal = 16.dp)) {
                        SectionHeader("Selected Profile")
                        SelectedSummary(
                            player = player,
                            onView = { onDismiss(); onViewPlayer(player.accountId, player.displayName) },
                            onDeselect = { confirmDeselect = true },
                        )
                    }
                }
            }
            item(key = "search") {
                Column(Modifier.padding(horizontal = 16.dp)) {
                    SectionHeader("Find a Profile")
                    ScopeRow(ui.scope, searchViewModel::selectScope)
                    SearchField(ui.query, searchViewModel)
                    SearchAnnouncement(ui, ProfileSheetTags.STATUS)
                }
            }
            searchBody(ui, revealed) { destination -> onDismiss(); onOpen(destination) }
            item(key = "bottom") { Spacer(Modifier.size(24.dp)) }
        }
    }
    if (confirmDeselect) {
        FestivalAlertDialog(
            title = "Deselect Profile?",
            text = "Scores and profile-only content will be hidden; app Settings stay saved.",
            tag = "fst.profile.deselect-confirm",
            confirmLabel = "Deselect",
            confirmTag = "fst.profile.deselect-confirm.ok",
            onConfirm = { confirmDeselect = false; onDeselect() },
            dismissLabel = "Cancel",
            dismissTag = "fst.profile.deselect-confirm.cancel",
            onDismissRequest = { confirmDeselect = false },
        )
    }
}

// endregion

// region Sections

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SelectedSummary(player: SelectedPlayer, onView: () -> Unit, onDeselect: () -> Unit) {
    Surface(color = BrandTokens.surfaceSubtle, shape = MaterialTheme.shapes.large, modifier = Modifier.fillMaxWidth().testTag("fst.profile.selected")) {
        Column(Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Avatar(player.initials)
                Text(player.displayName, style = MaterialTheme.typography.titleMedium, color = BrandTokens.textPrimary, modifier = Modifier.padding(start = 12.dp))
            }
            // Wraps at large font sizes instead of squeezing "Deselect" to a letter per line.
            FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 12.dp)) {
                Button(onClick = onView, colors = festivalFilledButtonColors(), modifier = Modifier.heightIn(min = 48.dp).testTag("fst.profile.view-selected")) { Text("View Profile") }
                OutlinedButton(onClick = onDeselect, modifier = Modifier.heightIn(min = 48.dp).testTag("fst.profile.deselect")) { Text("Deselect") }
            }
        }
    }
}

/**
 * All · Players · Bands as a Material 3 single-choice segmented button row (issue #600: start
 * broad, narrow to one kind). Choosing a segment only filters the results already searched.
 *
 * @param selected Current scope.
 * @param onSelect Choose a scope.
 */
@Composable
private fun ScopeRow(selected: SearchScope, onSelect: (SearchScope) -> Unit) {
    val scopes = SearchScope.profileScopes
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().testTag(ProfileSheetTags.SCOPES)) {
        scopes.forEachIndexed { index, scope ->
            SegmentedButton(
                selected = selected == scope,
                onClick = { onSelect(scope) },
                shape = SegmentedButtonDefaults.itemShape(index, scopes.size),
                modifier = Modifier.testTag(ProfileSheetTags.scope(scope)),
            ) { Text(scope.title, maxLines = 1, overflow = TextOverflow.Ellipsis) }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SearchField(query: String, viewModel: GlobalSearchViewModel) {
    // Native M3 docked search bar (neutral container, no custom fill).
    val colors = SearchBarDefaults.colors(containerColor = BrandTokens.surfaceMuted)
    DockedSearchBar(
        inputField = {
            SearchBarDefaults.InputField(
                query = query,
                onQueryChange = viewModel::onQueryChange,
                // Like global search (issue #299, no Retry button): Search runs the text now and
                // runs a failed or empty search again.
                onSearch = { viewModel.submit() },
                expanded = false,
                onExpandedChange = {},
                placeholder = { Text(GlobalSearchResults.PROFILE_PLACEHOLDER, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                trailingIcon = if (query.isNotEmpty()) {
                    {
                        IconButton(onClick = viewModel::clearQuery, modifier = Modifier.testTag(ProfileSheetTags.CLEAR)) {
                            Icon(Icons.Filled.Close, contentDescription = "Clear search")
                        }
                    }
                } else {
                    null
                },
                colors = colors.inputFieldColors,
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag(ProfileSheetTags.SEARCH)
                    .semantics { contentDescription = GlobalSearchResults.PROFILE_FIELD_NAME },
            )
        },
        expanded = false,
        onExpandedChange = {},
        colors = colors,
        modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
    ) {}
}

/**
 * The search body below the field: the short-query hint, the one centred spinner, the centred
 * empty state, or global search's result rows (pattern search-scopes).
 *
 * @param ui Search state.
 * @param revealed Whether the current result set may show.
 * @param onOpen Opens a result.
 */
private fun LazyListScope.searchBody(ui: GlobalSearchUiState, revealed: Boolean, onOpen: (SearchDestination) -> Unit) {
    val hint = ui.hint
    val empty = ui.emptyState
    when {
        // Web: the hint is plain primary text centred in the results area, with no container.
        hint != null -> centred("hint") {
            Text(hint, color = BrandTokens.textPrimary, textAlign = TextAlign.Center, modifier = Modifier.testTag(ProfileSheetTags.HINT))
        }
        empty != null -> centred("empty") {
            Box(Modifier.fillMaxWidth().testTag(ProfileSheetTags.EMPTY)) {
                FestivalEmptyState(title = empty.title, subtitle = empty.subtitle, modifier = Modifier.fillMaxWidth())
            }
        }
        ui.isBusy -> centred("loading") {
            FestivalLoading("Searching", Modifier.testTag(ProfileSheetTags.LOADING), size = 32.dp)
        }
        else -> searchResultItems(ui, revealed, artworkUrl = { null }, onOpen = onOpen, tags = ProfileSheetTags.results)
    }
}

private fun LazyListScope.centred(key: String, content: @Composable () -> Unit) {
    item(key = key) {
        Box(Modifier.fillMaxWidth().heightIn(min = 180.dp).padding(horizontal = 16.dp, vertical = 12.dp), contentAlignment = Alignment.Center) {
            content()
        }
    }
}

@Composable
private fun Avatar(initials: String) {
    // Decorative: the name beside it is what TalkBack reads.
    Box(Modifier.size(40.dp).background(BrandTokens.accentPurple, CircleShape).clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
        Text(initials, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary)
    }
}

// endregion
