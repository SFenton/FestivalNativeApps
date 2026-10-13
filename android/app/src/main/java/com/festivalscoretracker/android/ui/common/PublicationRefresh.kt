package com.festivalscoretracker.android.ui.common

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

// region Publication refresh

/**
 * What TalkBack hears while a page re-reads for a new publication (load-transition R9;
 * Apple `PublicationRefreshBoundary` page anchor value).
 */
const val PUBLICATION_REFRESH_STATUS = "Loading new scores"

/** Test tag of [PublicationRefreshStatus]. */
const val PUBLICATION_REFRESH_STATUS_TAG = "fst.publication-refresh.status"

/** Test tag of [PublicationRefreshSpinner]. */
const val PUBLICATION_REFRESH_SPINNER_TAG = "fst.publication-refresh.spinner"

/**
 * The page's publication-refresh status (load-transition R9, #616): one polite live region that
 * says [PUBLICATION_REFRESH_STATUS] (with indeterminate progress) while the page re-reads for a
 * new publication, and is silent otherwise. It is always composed, so TalkBack announces the
 * change once per publication wherever its focus is; focus is never moved (Android cannot see
 * the TalkBack cursor, like Apple macOS). Place it in a 1 dp corner of chrome that stays on
 * screen through the refresh (the Songs search field), so no content node ever covers it:
 * Compose drops fully covered nodes, and with them the announcement.
 *
 * @param refreshing Whether the page is re-reading for a new publication.
 * @param modifier Modifier (alignment inside the chrome it sits in).
 */
@Composable
fun PublicationRefreshStatus(refreshing: Boolean, modifier: Modifier = Modifier) {
    Box(
        modifier.size(1.dp).testTag(PUBLICATION_REFRESH_STATUS_TAG).semantics {
            liveRegion = LiveRegionMode.Polite
            if (refreshing) {
                contentDescription = PUBLICATION_REFRESH_STATUS
                progressBarRangeInfo = ProgressBarRangeInfo.Indeterminate
            }
        },
    )
}

/**
 * The publication refresh's spinner (the shared [LoadSwap] spinner and its fade-out), silent to
 * TalkBack: [PublicationRefreshStatus] already speaks for it, so the reader meets one busy
 * indicator rather than two.
 *
 * @param swap The page's swap.
 * @param modifier Modifier (defaults to filling the result area).
 */
@Composable
fun PublicationRefreshSpinner(swap: LoadSwap<*>, modifier: Modifier = Modifier.fillMaxSize()) {
    Box(modifier.then(swap.spinnerModifier).testTag(PUBLICATION_REFRESH_SPINNER_TAG), contentAlignment = Alignment.Center) {
        Box(Modifier.clearAndSetSemantics { }) { FestivalLoading(null) }
    }
}

// endregion
