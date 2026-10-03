package com.festivalscoretracker.android.ui.songs

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Toolbar search (phones)

/** Test tags of the Songs search in the phone floating toolbar (issue #84). */
object SongsToolbarSearchTags {
    /** Field-shaped button (expanded) or search icon (minimized) that opens the field. */
    const val OPEN = "fst.songs.search.open"

    /** Inline Clear on the expanded button. */
    const val CLEAR = "fst.songs.search.clear"

    /** Editable field (same tag as the pinned field on wider windows). */
    const val FIELD = "fst.songs.search"

    /** Close arrow beside the editable field. */
    const val CLOSE = "fst.songs.search.close"
}

/** Placeholder shared by the field-shaped button and the field (web dock). */
internal const val SONGS_SEARCH_PLACEHOLDER = "Search songs or artists"

/**
 * The Songs search entry in the phone floating toolbar's leading pill (issue #84, the Android port
 * of iOS #42's accessory search; its own pill beside the tools since issue #89): at the top of the
 * list a field-shaped button that takes the free width and shows the placeholder or the current
 * query (with an inline Clear); once the list scrolls down, a round search icon, gold while a query
 * filters the list. Either opens [SongsToolbarSearchField].
 *
 * @param query Current Songs search text.
 * @param minimized Show the icon instead of the field-shaped button.
 * @param onOpen Open the editable field.
 * @param onClear Clear the query.
 */
@Composable
internal fun RowScope.SongsToolbarSearchButton(query: String, minimized: Boolean, onOpen: () -> Unit, onClear: () -> Unit) {
    val active = query.isNotEmpty()
    val describe = Modifier.semantics {
        contentDescription = "Search songs"
        if (active) stateDescription = query
    }
    if (minimized) {
        IconButton(onClick = onOpen, modifier = Modifier.testTag(SongsToolbarSearchTags.OPEN).then(describe)) {
            Icon(Icons.Filled.Search, contentDescription = null, tint = if (active) BrandTokens.gold else BrandTokens.textPrimary)
        }
        return
    }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .weight(1f)
            .heightIn(min = 48.dp)
            .clip(CircleShape)
            .background(BrandTokens.surfaceFrosted)
            .clickable(role = Role.Button, onClick = onOpen)
            .testTag(SongsToolbarSearchTags.OPEN)
            .then(describe)
            .padding(start = 12.dp),
    ) {
        Icon(Icons.Filled.Search, contentDescription = null, tint = if (active) BrandTokens.gold else BrandTokens.textSecondary)
        Text(
            query.ifEmpty { SONGS_SEARCH_PLACEHOLDER },
            color = if (active) BrandTokens.textPrimary else BrandTokens.textMuted,
            style = MaterialTheme.typography.bodyLarge,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            // The button's description and state already speak the placeholder or query.
            modifier = Modifier.weight(1f).padding(horizontal = 8.dp).clearAndSetSemantics {},
        )
        if (active) {
            IconButton(onClick = onClear, modifier = Modifier.testTag(SongsToolbarSearchTags.CLEAR)) {
                Icon(Icons.Filled.Clear, contentDescription = "Clear search")
            }
        }
    }
}

/**
 * The editable Songs search field that fills the leading pill while open; the tools pill steps
 * aside meanwhile. It is focused on
 * open and the shell lifts the toolbar above the keyboard (`FestivalScreen(actionsAboveKeyboard)`),
 * so typing is never hidden. The close arrow, system back, the keyboard's Search key and losing
 * focus all close it and keep the query; Clear empties it.
 *
 * @param query Current Songs search text.
 * @param onChange New text.
 * @param onClose Close the field (keeps the query).
 */
@Composable
internal fun RowScope.SongsToolbarSearchField(query: String, onChange: (String) -> Unit, onClose: () -> Unit) {
    val focus = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    var focused by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        withFrameNanos { }
        runCatching { focus.requestFocus() }
        keyboard?.show()
    }
    BackHandler(onBack = onClose)
    IconButton(onClick = onClose, modifier = Modifier.testTag(SongsToolbarSearchTags.CLOSE)) {
        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Close search")
    }
    TextField(
        value = query,
        onValueChange = onChange,
        singleLine = true,
        placeholder = { Text(SONGS_SEARCH_PLACEHOLDER, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        trailingIcon = {
            if (query.isNotEmpty()) {
                IconButton(onClick = { onChange("") }) { Icon(Icons.Filled.Clear, contentDescription = "Clear search") }
            }
        },
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        keyboardActions = KeyboardActions(onSearch = { onClose() }),
        shape = RoundedCornerShape(28.dp),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = BrandTokens.surfaceFrosted,
            unfocusedContainerColor = BrandTokens.surfaceFrosted,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            focusedTextColor = BrandTokens.textPrimary,
            unfocusedTextColor = BrandTokens.textPrimary,
        ),
        modifier = Modifier
            .weight(1f)
            .focusRequester(focus)
            .onFocusChanged {
                if (it.isFocused) focused = true else if (focused) onClose()
            }
            .testTag(SongsToolbarSearchTags.FIELD),
    )
}

// endregion
