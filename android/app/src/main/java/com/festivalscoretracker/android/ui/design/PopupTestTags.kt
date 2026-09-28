package com.festivalscoretracker.android.ui.design

import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId

// region Popup test tags

/**
 * Expose Compose test tags as UIAutomator resource IDs inside a popup, sheet
 * or dialog. Popups are separate windows and do not inherit the shell root's
 * `testTagsAsResourceId`, so `device.py drive` journeys cannot find their tags
 * without this.
 *
 * @return Modifier with resource-ID test tags for this subtree.
 */
@OptIn(ExperimentalComposeUiApi::class)
fun Modifier.popupTestTags(): Modifier = semantics { testTagsAsResourceId = true }

// endregion
