package com.festivalscoretracker.android.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DockedSearchBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.festivalscoretracker.android.ui.design.festivalFilledButtonColors
import com.festivalscoretracker.android.ui.common.festivalSheetTop
import com.festivalscoretracker.android.core.model.PlayerSearchResult
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.presentation.ProfileSearchScope
import com.festivalscoretracker.android.presentation.ProfileSearchState
import com.festivalscoretracker.android.presentation.ProfileSearchViewModel
import com.festivalscoretracker.android.ui.common.FestivalLoading
import com.festivalscoretracker.android.ui.common.ServiceStatusInline
import com.festivalscoretracker.android.ui.design.SectionHeader
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Sheet

/**
 * Profile discovery (web `SearchModal` profile targets): the selected player's
 * summary, a Players/Bands target and a Material 3 search field. A result **views**
 * the player (dismiss, then push `/player/:id` on the current tab); selecting
 * happens on the player page. Band search is never requested (its GET can write).
 *
 * @param player Selected player.
 * @param searchViewModel Search logic.
 * @param onViewPlayer Dismiss-then-push the player page.
 * @param onDeselect Deselect the selected player (after confirmation).
 * @param onDismiss Close.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileSheet(
    player: SelectedPlayer?,
    searchViewModel: ProfileSearchViewModel,
    onViewPlayer: (accountId: String, displayName: String) -> Unit,
    onDeselect: () -> Unit,
    onDismiss: () -> Unit,
) {
    var confirmDeselect by rememberSaveable { mutableStateOf(false) }
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = BrandTokens.cardBackground, modifier = Modifier.festivalSheetTop().semantics { testTagsAsResourceId = true }.testTag("fst.profile.sheet")) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 24.dp).padding(bottom = 24.dp)) {
            Text(
                "Profiles",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = BrandTokens.textPrimary,
                modifier = Modifier.semantics { heading() },
            )
            if (player != null) {
                SectionHeader("Selected Profile")
                SelectedSummary(
                    player = player,
                    onView = { onDismiss(); onViewPlayer(player.accountId, player.displayName) },
                    onDeselect = { confirmDeselect = true },
                )
            }
            SectionHeader("Find a Profile")
            SearchSection(searchViewModel) { result -> onDismiss(); onViewPlayer(result.accountId, result.displayName) }
        }
    }
    if (confirmDeselect) {
        AlertDialog(
            onDismissRequest = { confirmDeselect = false },
            title = { Text("Deselect Profile?") },
            text = { Text("Scores and profile-only content will be hidden; app Settings stay saved.") },
            confirmButton = {
                TextButton(onClick = { confirmDeselect = false; onDeselect() }, modifier = Modifier.testTag("fst.profile.deselect-confirm.ok")) { Text("Deselect") }
            },
            dismissButton = { TextButton(onClick = { confirmDeselect = false }) { Text("Cancel") } },
            containerColor = BrandTokens.cardBackground,
            modifier = Modifier.testTag("fst.profile.deselect-confirm"),
        )
    }
}

// endregion

// region Sections

@Composable
private fun SelectedSummary(player: SelectedPlayer, onView: () -> Unit, onDeselect: () -> Unit) {
    Surface(color = BrandTokens.surfaceSubtle, shape = MaterialTheme.shapes.large, modifier = Modifier.fillMaxWidth().testTag("fst.profile.selected")) {
        Column(Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Avatar(player.initials)
                Text(player.displayName, style = MaterialTheme.typography.titleMedium, color = BrandTokens.textPrimary, modifier = Modifier.padding(start = 12.dp))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.padding(top = 12.dp)) {
                Button(onClick = onView, colors = festivalFilledButtonColors(), modifier = Modifier.heightIn(min = 48.dp).testTag("fst.profile.view-selected")) { Text("View Profile") }
                OutlinedButton(onClick = onDeselect, modifier = Modifier.heightIn(min = 48.dp).testTag("fst.profile.deselect")) { Text("Deselect") }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SearchSection(viewModel: ProfileSearchViewModel, onOpen: (PlayerSearchResult) -> Unit) {
    val query by viewModel.query.collectAsStateWithLifecycle()
    val scope by viewModel.scope.collectAsStateWithLifecycle()
    val state by viewModel.state.collectAsStateWithLifecycle()
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().testTag("fst.profile.scope")) {
        ProfileSearchScope.entries.forEachIndexed { index, target ->
            SegmentedButton(
                selected = scope == target,
                onClick = { viewModel.setScope(target) },
                shape = SegmentedButtonDefaults.itemShape(index, ProfileSearchScope.entries.size),
                modifier = Modifier.testTag("fst.profile.scope.${target.name.lowercase()}"),
            ) { Text(target.label) }
        }
    }
    val bands = scope == ProfileSearchScope.Bands
    // Native M3 docked search bar (neutral container, no custom fill).
    val colors = SearchBarDefaults.colors(containerColor = BrandTokens.surfaceMuted)
    DockedSearchBar(
        inputField = {
            SearchBarDefaults.InputField(
                query = query,
                onQueryChange = viewModel::onQueryChange,
                onSearch = { (state as? ProfileSearchState.Results)?.results?.firstOrNull()?.let(onOpen) },
                expanded = false,
                onExpandedChange = {},
                enabled = !bands,
                placeholder = { Text(scope.placeholder) },
                leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                trailingIcon = if (query.isNotEmpty() && !bands) {
                    {
                        IconButton(onClick = { viewModel.onQueryChange("") }, modifier = Modifier.testTag("fst.profile.clear")) {
                            Icon(Icons.Filled.Close, contentDescription = "Clear search")
                        }
                    }
                } else {
                    null
                },
                colors = colors.inputFieldColors,
                modifier = Modifier.fillMaxWidth().testTag("fst.profile.search"),
            )
        },
        expanded = false,
        onExpandedChange = {},
        colors = colors,
        modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
    ) {}
    Box(Modifier.fillMaxWidth().heightIn(min = 180.dp).padding(top = 12.dp)) {
        when (val current = state) {
            ProfileSearchState.BandsUnavailable -> Row(Modifier.testTag("fst.profile.bands-unavailable"), verticalAlignment = Alignment.Top) {
                Icon(Icons.Outlined.Groups, contentDescription = null, tint = BrandTokens.textPrimary)
                Text(
                    "Band search isn't available: the service's band search can change stored data, so this app doesn't call it. " +
                        "Open a band from a player's Bands list or from Band Rankings.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = BrandTokens.textPrimary,
                    modifier = Modifier.padding(start = 12.dp),
                )
            }
            ProfileSearchState.Hint -> Text(
                "Enter at least 2 characters",
                color = BrandTokens.textSecondary,
                textAlign = TextAlign.Center,
                modifier = Modifier.align(Alignment.Center).testTag("fst.profile.hint"),
            )
            ProfileSearchState.Searching -> FestivalLoading("Searching", Modifier.align(Alignment.Center).testTag("fst.profile.loading"), size = 32.dp)
            is ProfileSearchState.Failed -> ServiceStatusInline(current.issue, "Player search unavailable", null, viewModel::retry)
            is ProfileSearchState.Results -> Column(Modifier.testTag("fst.profile.results")) {
                if (current.results.isEmpty()) {
                    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("No players found", color = BrandTokens.textPrimary, modifier = Modifier.padding(8.dp))
                        TextButton(onClick = viewModel::retry, modifier = Modifier.testTag("fst.profile.retry")) { Text("Retry") }
                    }
                }
                current.results.forEach { result ->
                    ListItem(
                        headlineContent = { Text(result.displayName) },
                        leadingContent = { Avatar(SelectedPlayer(result.accountId, result.displayName).initials) },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent, headlineColor = BrandTokens.textPrimary),
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onOpen(result) }
                            .testTag("fst.profile.result.${result.accountId}"),
                    )
                }
            }
        }
    }
    Spacer(Modifier.size(8.dp))
}

@Composable
private fun Avatar(initials: String) {
    // Decorative: the name beside it is what TalkBack reads.
    Box(Modifier.size(40.dp).background(BrandTokens.accentPurple, CircleShape).clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
        Text(initials, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold, color = BrandTokens.textPrimary)
    }
}

// endregion
