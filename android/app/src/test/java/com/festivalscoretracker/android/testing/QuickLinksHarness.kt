package com.festivalscoretracker.android.testing

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.quicklinks.QuickLinkSection
import com.festivalscoretracker.android.ui.quicklinks.QuickLinksAction
import com.festivalscoretracker.android.ui.quicklinks.QuickLinksController
import com.festivalscoretracker.android.ui.quicklinks.rememberQuickLinks
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.FestivalTheme

// region Harness

/**
 * A synthetic page for the Quick Links control's state tests (issue #137): a 64 dp header row
 * holding [QuickLinksAction] above a `LazyColumn` of numbered sections, each a heading followed
 * by [ROWS_PER_SECTION] rows. Shared by the Robolectric suite and the connected device test.
 */
object QuickLinksHarness {
    /** Test tag of the page list. */
    const val LIST_TAG = "fst.quick-links.harness.list"

    /** Rows below each section heading. */
    const val ROWS_PER_SECTION = 6

    /** Height of one row. */
    const val ROW_HEIGHT_DP = 72

    /** Quick Links title. */
    const val TITLE = "Quick Links"

    private val icons = listOf("settings", "music", "trophy", "people", "chart", "info")

    /**
     * Sections `section-0` … in page order, titled "Section 1" …; the third has a longer spoken label.
     *
     * @param count Number of sections.
     * @return Sections.
     */
    fun sections(count: Int): List<QuickLinkSection> = (0 until count).map { i ->
        QuickLinkSection(
            id = "section-$i",
            title = "Section ${i + 1}",
            icon = icons[i % icons.size],
            spokenTitle = if (i == 2) "Section ${i + 1} (spoken)" else null,
        )
    }

    /**
     * List index of a section's heading.
     *
     * @param id Section ID.
     * @return Index, or null for an unknown ID.
     */
    fun headerIndex(id: String): Int? = id.removePrefix("section-").toIntOrNull()?.let { it * (ROWS_PER_SECTION + 1) }

    /**
     * Test tag of a section heading.
     *
     * @param id Section ID.
     * @return Tag.
     */
    fun headerTag(id: String): String = "fst.quick-links.harness.section.$id"
}

/**
 * The harness page.
 *
 * @param sectionCount Sections on the page.
 * @param windowWidthDp Window width handed to [QuickLinksAction] (below 600 dp: sheet; otherwise: menu).
 * @param listState The page list's state.
 * @param onController Receives the page's controller on every composition.
 */
@Composable
fun QuickLinksHarnessPage(
    sectionCount: Int,
    windowWidthDp: Int,
    listState: LazyListState = rememberLazyListState(),
    onController: (QuickLinksController) -> Unit = {},
) {
    FestivalTheme {
        val sections = remember(sectionCount) { QuickLinksHarness.sections(sectionCount) }
        val controller = rememberQuickLinks(listState, QuickLinksHarness.TITLE, sections, indexOf = QuickLinksHarness::headerIndex)
        onController(controller)
        Column(Modifier.fillMaxSize().background(BrandTokens.appBackground).safeDrawingPadding()) {
            Row(Modifier.fillMaxWidth().height(64.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Harness", Modifier.weight(1f).padding(start = 12.dp), color = BrandTokens.textPrimary, style = MaterialTheme.typography.titleLarge)
                QuickLinksAction(controller, windowWidthDp)
            }
            LazyColumn(state = listState, modifier = Modifier.weight(1f).fillMaxWidth().testTag(QuickLinksHarness.LIST_TAG)) {
                sections.forEach { section ->
                    item(key = section.id) {
                        Text(
                            section.title,
                            Modifier.testTag(QuickLinksHarness.headerTag(section.id)).fillMaxWidth().heightIn(min = 56.dp).semantics { heading() }.padding(16.dp),
                            color = BrandTokens.textPrimary,
                            style = MaterialTheme.typography.titleMedium,
                        )
                    }
                    items(QuickLinksHarness.ROWS_PER_SECTION, key = { "${section.id}-$it" }) { row ->
                        Text(
                            "${section.title} row ${row + 1}",
                            Modifier.fillMaxWidth().height(QuickLinksHarness.ROW_HEIGHT_DP.dp).padding(horizontal = 16.dp, vertical = 12.dp),
                            color = BrandTokens.textSecondary,
                        )
                    }
                }
            }
        }
    }
}

// endregion
