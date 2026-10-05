package com.festivalscoretracker.android.ui.firstrun

import com.festivalscoretracker.android.ui.design.festivalFilledButtonColors
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
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
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
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.presentation.firstrun.FirstRunCarousel
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import kotlinx.coroutines.launch
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import com.festivalscoretracker.android.ui.common.FestivalModalDialog
import com.festivalscoretracker.android.core.firstrun.FirstRunSlide
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Density
import kotlin.math.roundToInt

// region Carousel

/**
 * First-run carousel: the shared [FestivalModalDialog] (page label header in the shared
 * Title Large modal style, with the standard Close button) holding a horizontal pager, white page dots and the footer actions,
 * ordered as Material 3 dialog actions (issue #25): **Back, then Next/Done** at the trailing
 * edge, so the confirming action is always last and never moves under the finger. Back shows
 * only after the first slide (never disabled; operator batch 6.7) and there is no Skip: the
 * close button is the one-tap early exit, so a one-slide guide shows only Done. Close, Done, system
 * back and a tap outside all complete it, marking only the slides actually displayed as
 * seen. Off-screen pages are not composed beyond the pager's single-page beyond bound,
 * so demo animations cost nothing while hidden.
 *
 * The dialog always takes the window width less 16 dp margins, capped at Material's 560 dp
 * (never the platform's narrower preferred dialog width, which left landscape phones a
 * 320 dp column). Short, wide windows lay each slide out side by side ([FirstRunSlideLayout]).
 *
 * @param carousel Presentation.
 * @param onComplete Close in any way, with how many slides (from the first) were displayed.
 */
@Composable
fun FirstRunCarouselDialog(carousel: FirstRunCarousel, onComplete: (viewedCount: Int) -> Unit) {
    val pager = rememberPagerState(pageCount = { carousel.slides.size })
    val scope = rememberCoroutineScope()
    val reduceMotion = LocalFestivalAccessibility.current.reduceMotion
    val last = pager.currentPage == carousel.slides.lastIndex
    val titleFocus = androidx.compose.runtime.remember { FocusRequester() }
    var viewed by rememberSaveable(carousel.id) { mutableIntStateOf(1) }
    val close = { onComplete(maxOf(viewed, pager.currentPage + 1)) }
    fun go(page: Int) = scope.launch { if (reduceMotion) pager.scrollToPage(page) else pager.animateScrollToPage(page) }

    FestivalModalDialog(
        title = carousel.page.label,
        closeTag = "fst.first-run.close",
        onDismissRequest = close,
        // Full-width margins capped at 560 dp on every window (see the KDoc above).
        compact = true,
        // Half-open foldables: stay on one side of the hinge (M3 foldables guidance).
        avoidHinge = true,
        paneTitle = "Feature tour: ${carousel.page.label}",
        // The shared Title Large header, like What's New and Notifications (issue #147).
        titleTag = "fst.first-run.title",
        modifier = Modifier.testTag("fst.first-run.dialog"),
    ) {
        BoxWithConstraints(Modifier.weight(1f, fill = false)) {
            // Short, wide windows (landscape phones, folded posture) lay the slide out side by side
            // and move the dots into the footer, so the title and description stay in view.
            val sideBySide = FirstRunSlideLayout.sideBySide(maxWidth.value, maxHeight.value)
            Column(Modifier.padding(bottom = 12.dp).testTag(if (sideBySide) "fst.first-run.layout.side-by-side" else "fst.first-run.layout.stacked")) {
                HorizontalPager(
                    state = pager,
                    key = { carousel.slides[it].id },
                    // Takes what the header, dots and buttons leave, so the buttons stay on screen
                    // at large font sizes; each slide then scrolls vertically.
                    modifier = Modifier.fillMaxWidth().weight(1f, fill = false).testTag("fst.first-run.pager"),
                ) { page ->
                    val slide = carousel.slides[page]
                    val active = page == pager.currentPage && pager.currentPageOffsetFraction == 0f
                    val titleModifier = Modifier
                        .semantics { heading() }
                        .then(if (page == pager.currentPage) Modifier.focusRequester(titleFocus) else Modifier)
                    Box(Modifier.fillMaxWidth().testTag("fst.first-run.slide.${slide.id}")) {
                        if (sideBySide) {
                            SideBySideSlide(slide, active, titleModifier)
                        } else {
                            StackedSlide(slide, active, titleModifier)
                        }
                    }
                }
                // Position is spoken from the dots' state ("Slide 2 of 6"); no visible text.
                if (!sideBySide) {
                    Dots(
                        pager.currentPage,
                        carousel.slides.size,
                        carousel.position(pager.currentPage),
                        Modifier.align(Alignment.CenterHorizontally).padding(vertical = 12.dp),
                    )
                }
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth().padding(start = 16.dp, end = 24.dp, top = 8.dp),
                ) {
                    if (sideBySide) {
                        Dots(pager.currentPage, carousel.slides.size, carousel.position(pager.currentPage), Modifier.padding(start = 8.dp))
                    }
                    Spacer(Modifier.weight(1f))
                    if (pager.currentPage > 0) {
                        TextButton(
                            onClick = { go(pager.currentPage - 1) },
                            colors = ButtonDefaults.textButtonColors(contentColor = BrandTokens.textPrimary),
                            modifier = Modifier.testTag("fst.first-run.back"),
                        ) { Text("Back") }
                    }
                    // M3 dialog actions: the confirming action is last, so Next/Done keeps its place when Back appears.
                    Button(
                        onClick = { if (last) close() else go(pager.currentPage + 1) },
                        colors = festivalFilledButtonColors(),
                        modifier = Modifier.testTag(if (last) "fst.first-run.done" else "fst.first-run.next"),
                    ) { Text(if (last) "Done" else "Next") }
                }
            }
        }
    }
    LaunchedEffect(pager.currentPage) {
        viewed = maxOf(viewed, pager.currentPage + 1)
        runCatching { titleFocus.requestFocus() }
    }
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
                    // White dots (operator batch 6.7): the current one solid, the rest dimmed white.
                    .background(if (index == current) BrandTokens.textPrimary else BrandTokens.textPrimary.copy(alpha = INACTIVE_DOT_ALPHA), CircleShape),
            )
        }
    }
}

/** Opacity of the non-current pager dots. */
private const val INACTIVE_DOT_ALPHA = 0.35f

// endregion

// region Slides

/**
 * Default slide: the demo illustration above a centred title and description, scrolling
 * vertically when large text needs more room than the pager leaves.
 *
 * @param slide Slide to show.
 * @param active Whether the slide is settled on screen (demos animate only then).
 * @param titleModifier Heading semantics and focus for the title.
 */
@Composable
private fun StackedSlide(slide: FirstRunSlide, active: Boolean, titleModifier: Modifier) {
    Column(
        Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(Modifier.fillMaxWidth().height(FirstRunSlideLayout.DEMO_HEIGHT_DP.dp)) {
            DemoIllustration(slide.id, active, Modifier.fillMaxSize())
        }
        Spacer(Modifier.height(16.dp))
        Text(
            slide.title,
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            color = BrandTokens.textPrimary,
            textAlign = TextAlign.Center,
            modifier = titleModifier,
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

/**
 * Short-window slide: the demo illustration, scaled down to the page height, at the start and
 * the title and description, vertically centred and scrolling when needed, at the end.
 *
 * @param slide Slide to show.
 * @param active Whether the slide is settled on screen (demos animate only then).
 * @param titleModifier Heading semantics and focus for the title.
 */
@Composable
private fun SideBySideSlide(slide: FirstRunSlide, active: Boolean, titleModifier: Modifier) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val pageHeight = maxHeight
        Row(
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp),
        ) {
            ScaledDemo(slide.id, active, Modifier.weight(FirstRunSlideLayout.DEMO_WIDTH_FRACTION).heightIn(max = pageHeight))
            Column(
                Modifier
                    .weight(1f - FirstRunSlideLayout.DEMO_WIDTH_FRACTION)
                    .heightIn(max = pageHeight)
                    .verticalScroll(rememberScrollState()),
            ) {
                Column(Modifier.fillMaxWidth().heightIn(min = pageHeight), verticalArrangement = Arrangement.Center) {
                    Text(
                        slide.title,
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold,
                        color = BrandTokens.textPrimary,
                        modifier = titleModifier,
                    )
                    Text(
                        slide.description,
                        style = MaterialTheme.typography.bodyLarge,
                        color = BrandTokens.textSecondary,
                        modifier = Modifier.padding(top = 8.dp),
                    )
                }
            }
        }
    }
}

/**
 * Lays the demo out at its designed height and scales it down uniformly to the height it is
 * given, so short windows show the whole illustration rather than a clipped slice.
 */
@Composable
private fun ScaledDemo(id: String, active: Boolean, modifier: Modifier) {
    Layout(
        content = { DemoIllustration(id, active, Modifier.fillMaxSize()) },
        modifier = modifier.clipToBounds(),
    ) { measurables, constraints ->
        val designHeight = FirstRunSlideLayout.DEMO_HEIGHT_DP.dp.roundToPx()
        val scale = FirstRunSlideLayout.demoScale(constraints.maxHeight.toFloat(), designHeight.toFloat())
        val width = constraints.maxWidth
        val placeable = measurables.single().measure(Constraints.fixed((width / scale).roundToInt(), designHeight))
        layout(width, (designHeight * scale).roundToInt()) {
            placeable.placeWithLayer(0, 0) {
                scaleX = scale
                scaleY = scale
                transformOrigin = TransformOrigin(0f, 0f)
            }
        }
    }
}

/**
 * The slide's decorative demo, hidden from accessibility services. It is drawn at font scale
 * 1.0 like a picture: the slide's title and description carry the meaning and follow the
 * user's font size, while a scaled illustration would only clip inside its fixed frame.
 */
@Composable
private fun DemoIllustration(id: String, active: Boolean, modifier: Modifier) {
    val density = LocalDensity.current
    CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale = 1f)) {
        Box(modifier.testTag("fst.first-run.demo").clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
            FirstRunDemo(id, active = active)
        }
    }
}

// endregion

// region Layout policy

/** Pure sizing rules for the carousel's slide layouts, in dp. */
internal object FirstRunSlideLayout {
    /** Designed height of a demo illustration. */
    const val DEMO_HEIGHT_DP = 220f

    /** Below this content height the stacked slide (demo, title, description, dots, footer) no longer fits. */
    const val SHORT_HEIGHT_DP = 480f

    /** Narrowest content that leaves both columns of the side-by-side slide usable. */
    const val SIDE_BY_SIDE_MIN_WIDTH_DP = 480f

    /** Share of the slide width given to the demo in the side-by-side layout. */
    const val DEMO_WIDTH_FRACTION = 0.45f

    /** Smallest demo scale, so very short windows still show a recognisable illustration. */
    const val MIN_DEMO_SCALE = 0.4f

    /**
     * Whether the dialog content area is short and wide enough for the side-by-side slide.
     *
     * @param widthDp Content width available to the dialog body.
     * @param heightDp Content height available below the dialog header.
     * @return `true` for the side-by-side layout, `false` for the stacked one.
     */
    fun sideBySide(widthDp: Float, heightDp: Float): Boolean =
        heightDp < SHORT_HEIGHT_DP && widthDp >= SIDE_BY_SIDE_MIN_WIDTH_DP

    /**
     * Uniform scale fitting the demo's designed height into the available height.
     *
     * @param available Available height (any unit; same as [design]).
     * @param design Designed demo height.
     * @return Scale in `[MIN_DEMO_SCALE, 1]`.
     */
    fun demoScale(available: Float, design: Float): Float =
        if (design <= 0f || available >= design) 1f else (available / design).coerceAtLeast(MIN_DEMO_SCALE)
}

// endregion
