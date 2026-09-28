package com.festivalscoretracker.android.ui.firstrun

import com.festivalscoretracker.android.ui.design.popupTestTags
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.festivalscoretracker.android.presentation.firstrun.FirstRunCarousel
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import kotlinx.coroutines.launch

// region Carousel

/**
 * First-run carousel: an M3 dialog with a horizontal pager, page dots, a close
 * button, Skip, Back and Next/Done. Close, Skip, Done, system back and a tap
 * outside all complete it (marking every displayed slide seen). Off-screen
 * pages are not composed beyond the pager's single-page beyond bound, so demo
 * animations cost nothing while hidden.
 *
 * @param carousel Presentation.
 * @param compact Compact window width (full-width card).
 * @param onComplete Close in any way.
 */
@Composable
fun FirstRunCarouselDialog(carousel: FirstRunCarousel, compact: Boolean, onComplete: () -> Unit) {
    val pager = rememberPagerState(pageCount = { carousel.slides.size })
    val scope = rememberCoroutineScope()
    val reduceMotion = LocalFestivalAccessibility.current.reduceMotion
    val last = pager.currentPage == carousel.slides.lastIndex
    val titleFocus = androidx.compose.runtime.remember { FocusRequester() }
    fun go(page: Int) = scope.launch { if (reduceMotion) pager.scrollToPage(page) else pager.animateScrollToPage(page) }

    Dialog(onDismissRequest = onComplete, properties = DialogProperties(usePlatformDefaultWidth = !compact)) {
        Surface(
            shape = RoundedCornerShape(28.dp),
            color = BrandTokens.cardBackground,
            modifier = Modifier
                .padding(if (compact) 16.dp else 0.dp)
                .widthIn(max = 560.dp)
                .fillMaxWidth()
                .popupTestTags()
                .testTag("fst.first-run.dialog")
                .semantics { paneTitle = "Feature tour: ${carousel.page.label}" },
        ) {
            Column(Modifier.padding(vertical = 12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(start = 24.dp, end = 8.dp)) {
                    Text(
                        carousel.page.label,
                        style = MaterialTheme.typography.labelLarge,
                        color = BrandTokens.textSecondary,
                        modifier = Modifier.weight(1f),
                    )
                    IconButton(onClick = onComplete, modifier = Modifier.testTag("fst.first-run.close")) {
                        Icon(Icons.Filled.Close, contentDescription = "Close")
                    }
                }
                HorizontalPager(
                    state = pager,
                    key = { carousel.slides[it].id },
                    modifier = Modifier.fillMaxWidth().testTag("fst.first-run.pager"),
                ) { page ->
                    val slide = carousel.slides[page]
                    Column(
                        Modifier.fillMaxWidth().padding(horizontal = 24.dp).testTag("fst.first-run.slide.${slide.id}"),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Box(Modifier.fillMaxWidth().height(220.dp).clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
                            FirstRunDemo(slide.id, active = page == pager.currentPage && pager.currentPageOffsetFraction == 0f)
                        }
                        Spacer(Modifier.height(16.dp))
                        Text(
                            slide.title,
                            style = MaterialTheme.typography.headlineSmall,
                            fontWeight = FontWeight.Bold,
                            color = BrandTokens.textPrimary,
                            textAlign = TextAlign.Center,
                            modifier = Modifier
                                .semantics { heading() }
                                .then(if (page == pager.currentPage) Modifier.focusRequester(titleFocus) else Modifier),
                        )
                        Text(
                            slide.description,
                            style = MaterialTheme.typography.bodyLarge,
                            color = BrandTokens.textSecondary,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.padding(top = 8.dp).heightIn(min = 96.dp),
                        )
                    }
                }
                // Position is spoken from the dots' state ("Slide 2 of 6"); no visible text.
                Dots(
                    pager.currentPage,
                    carousel.slides.size,
                    carousel.position(pager.currentPage),
                    Modifier.align(Alignment.CenterHorizontally).padding(vertical = 12.dp),
                )
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth().padding(start = 16.dp, end = 24.dp, top = 8.dp),
                ) {
                    TextButton(onClick = onComplete, modifier = Modifier.testTag("fst.first-run.skip")) { Text("Skip") }
                    Spacer(Modifier.weight(1f))
                    if (pager.currentPage > 0) {
                        TextButton(onClick = { go(pager.currentPage - 1) }, modifier = Modifier.testTag("fst.first-run.back")) { Text("Back") }
                    }
                    Button(
                        onClick = { if (last) onComplete() else go(pager.currentPage + 1) },
                        modifier = Modifier.testTag(if (last) "fst.first-run.done" else "fst.first-run.next"),
                    ) { Text(if (last) "Done" else "Next") }
                }
            }
        }
    }
    LaunchedEffect(pager.currentPage) { runCatching { titleFocus.requestFocus() } }
}

@Composable
private fun Dots(current: Int, count: Int, position: String, modifier: Modifier) {
    if (count < 2) return
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = modifier
            .testTag("fst.first-run.position")
            .clearAndSetSemantics {
                contentDescription = "Page indicator"
                stateDescription = position
                liveRegion = LiveRegionMode.Polite
            },
    ) {
        repeat(count) { index ->
            Box(
                Modifier
                    .size(if (index == current) 10.dp else 8.dp)
                    .background(if (index == current) BrandTokens.textPrimary else BrandTokens.surfaceMuted, CircleShape),
            )
        }
    }
}

// endregion
