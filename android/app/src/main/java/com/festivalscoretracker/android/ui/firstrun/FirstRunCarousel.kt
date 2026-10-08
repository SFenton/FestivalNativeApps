package com.festivalscoretracker.android.ui.firstrun

import com.festivalscoretracker.android.ui.design.festivalFilledButtonColors
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.pager.PagerState
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
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.foundation.focusGroup
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
import com.festivalscoretracker.android.core.firstrun.FirstRunEntrance
import com.festivalscoretracker.android.ui.common.LocalFadeInWindow
import androidx.compose.runtime.mutableStateOf
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
import androidx.compose.ui.unit.Dp
import androidx.compose.runtime.remember
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.rememberTextMeasurer
import kotlin.math.roundToInt

// region Carousel

/**
 * First-run carousel: the shared [FestivalModalDialog] (page label header in the shared
 * Title Large modal style, with the standard Close button) holding a horizontal pager, white page dots and the footer actions,
 * ordered as Material 3 dialog actions (issue #25): **Back, then Next/Done** at the trailing
 * edge, so the confirming action is always last and never moves under the finger. Stacked slides
 * reserve the tallest slide's text height, so the dialog and its footer also keep one height
 * through the tour (issue #148). Back shows
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
        // Half-open foldables: the shared dialog stays on one side of the hinge (M3 foldables guidance).
        paneTitle = "Feature tour: ${carousel.page.label}",
        // The shared Title Large header, like What's New and Notifications (issue #147).
        titleTag = "fst.first-run.title",
        modifier = Modifier.testTag("fst.first-run.dialog"),
    ) {
        FirstRunCarouselBody(
            carousel,
            pager,
            titleFocus,
            onBack = { go(pager.currentPage - 1) },
            onNext = { if (last) close() else go(pager.currentPage + 1) },
        )
    }
    LaunchedEffect(pager.currentPage) {
        viewed = maxOf(viewed, pager.currentPage + 1)
        runCatching { titleFocus.requestFocus() }
    }
}

/**
 * The tour's body below the dialog header: pager, dots and the Back/Next/Done footer. Internal
 * so layout tests can measure it in a full-height window.
 *
 * @param carousel Presentation.
 * @param pager Page state, hoisted so a dismissal can report the slides displayed.
 * @param titleFocus Focus for the current slide's title.
 * @param onBack Back to the previous slide.
 * @param onNext Next slide, or Done on the last one.
 */
@Composable
internal fun ColumnScope.FirstRunCarouselBody(
    carousel: FirstRunCarousel,
    pager: PagerState,
    titleFocus: FocusRequester,
    onBack: () -> Unit,
    onNext: () -> Unit,
) {
    BoxWithConstraints(Modifier.weight(1f, fill = false)) {
        // Short, wide windows (landscape phones, folded posture) lay the slide out side by side
        // and move the dots into the footer, so the title and description stay in view.
        val sideBySide = FirstRunSlideLayout.sideBySide(maxWidth.value, maxHeight.value)
        val last = pager.currentPage == carousel.slides.lastIndex
        val textBlockHeight = stackedTextBlockHeight(carousel.slides, maxWidth - (STACKED_PADDING_DP * 2).dp)
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
                // Web parity (#380): every visit replays the slide's entrance once it settles.
                // Starts false so the first slide's entrance runs too.
                val settled = pager.settledPage == page
                var revealed by remember { mutableStateOf(false) }
                LaunchedEffect(settled) { revealed = settled }
                val reduceMotion = LocalFestivalAccessibility.current.reduceMotion
                CompositionLocalProvider(LocalFirstRunReveal provides (revealed || reduceMotion), LocalFadeInWindow provides null) {
                    Box(Modifier.fillMaxWidth().testTag("fst.first-run.slide.${slide.id}")) {
                        if (sideBySide) {
                            SideBySideSlide(slide, active, titleModifier)
                        } else {
                            StackedSlide(slide, active, titleModifier, textBlockHeight)
                        }
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
                        onClick = onBack,
                        colors = ButtonDefaults.textButtonColors(contentColor = BrandTokens.textPrimary),
                        modifier = Modifier.testTag("fst.first-run.back"),
                    ) { Text("Back") }
                }
                // M3 dialog actions: the confirming action is last, so Next/Done keeps its place when Back appears.
                Button(
                    onClick = onNext,
                    colors = festivalFilledButtonColors(),
                    modifier = Modifier.testTag(if (last) "fst.first-run.done" else "fst.first-run.next"),
                ) { Text(if (last) "Done" else "Next") }
            }
        }
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
 * @param textBlockHeight Height reserved for the title and description: the tallest slide's, so
 *   every slide (and so the dialog and its footer) keeps one height through the tour.
 */
@Composable
private fun StackedSlide(slide: FirstRunSlide, active: Boolean, titleModifier: Modifier, textBlockHeight: Dp) {
    Column(
        Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = STACKED_PADDING_DP.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(Modifier.fillMaxWidth().height(FirstRunSlideLayout.DEMO_HEIGHT_DP.dp)) {
            DemoIllustration(slide.id, active, Modifier.fillMaxSize())
        }
        Spacer(Modifier.height(16.dp))
        Column(Modifier.fillMaxWidth().heightIn(min = textBlockHeight), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                slide.title,
                style = stackedTitleStyle(),
                color = BrandTokens.textPrimary,
                textAlign = TextAlign.Center,
                modifier = titleModifier.demoEntrance(FirstRunEntrance.titleDelay(slide.id)),
            )
            Text(
                slide.description,
                style = MaterialTheme.typography.bodyLarge,
                color = BrandTokens.textSecondary,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = STACKED_DESCRIPTION_GAP_DP.dp).heightIn(min = STACKED_DESCRIPTION_MIN_DP.dp)
                    .demoEntrance(FirstRunEntrance.descriptionDelay(slide.id)),
            )
        }
    }
}

/** Stacked slide title style: Headline Small, bold. */
@Composable
private fun stackedTitleStyle(): TextStyle = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.Bold)

/**
 * Height of the tallest stacked title + description among [slides] at [textWidth] and the
 * current font scale, so the dialog never resizes between slides and Back/Next/Done stay put
 * (issue #148: before, the footer jumped up to 66 dp when a slide's text was longer).
 *
 * @param slides Slides of the carousel.
 * @param textWidth Width the slide text is laid out in.
 * @return Height to reserve below the demo on every slide.
 */
@Composable
private fun stackedTextBlockHeight(slides: List<FirstRunSlide>, textWidth: Dp): Dp {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val titleStyle = stackedTitleStyle()
    val bodyStyle = MaterialTheme.typography.bodyLarge
    return remember(slides, textWidth, density, titleStyle, bodyStyle) {
        with(density) {
            val constraints = Constraints(maxWidth = textWidth.roundToPx().coerceAtLeast(0))
            slides.maxOfOrNull { slide ->
                val title = measurer.measure(slide.title, titleStyle, constraints = constraints).size.height.toDp()
                val body = measurer.measure(slide.description, bodyStyle, constraints = constraints).size.height.toDp()
                title + STACKED_DESCRIPTION_GAP_DP.dp + maxOf(body, STACKED_DESCRIPTION_MIN_DP.dp)
            } ?: 0.dp
        }
    }
}

/** Horizontal padding of the stacked slide. */
private const val STACKED_PADDING_DP = 24

/** Gap between the stacked title and description. */
private const val STACKED_DESCRIPTION_GAP_DP = 8

/** Smallest description height on a stacked slide. */
private const val STACKED_DESCRIPTION_MIN_DP = 96

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
                        modifier = titleModifier.demoEntrance(FirstRunEntrance.titleDelay(slide.id)),
                    )
                    Text(
                        slide.description,
                        style = MaterialTheme.typography.bodyLarge,
                        color = BrandTokens.textSecondary,
                        modifier = Modifier.padding(top = 8.dp).demoEntrance(FirstRunEntrance.descriptionDelay(slide.id)),
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
 * Keyboard focus never enters it either (issue #420): the demos reuse real clickable rows and
 * controls, which would otherwise be Tab stops that TalkBack and the user cannot see.
 */
@Composable
private fun DemoIllustration(id: String, active: Boolean, modifier: Modifier) {
    val density = LocalDensity.current
    CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale = 1f)) {
        Box(
            modifier.testTag("fst.first-run.demo")
                .clearAndSetSemantics { }
                .focusProperties { onEnter = { cancelFocusChange() } }
                .focusGroup(),
            contentAlignment = Alignment.Center,
        ) {
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
