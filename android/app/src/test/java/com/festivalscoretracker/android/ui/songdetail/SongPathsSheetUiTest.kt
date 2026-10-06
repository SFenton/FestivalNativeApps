package com.festivalscoretracker.android.ui.songdetail

import android.graphics.Bitmap
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertTouchHeightIsEqualTo
import androidx.compose.ui.test.assertTouchWidthIsEqualTo
import android.graphics.Canvas
import android.view.View
import com.festivalscoretracker.android.presentation.songs.PathSwapTiming
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.window.layout.FoldingFeature.Orientation
import androidx.window.layout.FoldingFeature.State
import androidx.window.testing.layout.FoldingFeature
import androidx.window.testing.layout.TestWindowLayoutInfo
import androidx.window.testing.layout.WindowLayoutInfoPublisherRule
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.paths.PathDifficulty
import com.festivalscoretracker.android.core.paths.SongPathData
import com.festivalscoretracker.android.core.settings.PathColumnKey
import com.festivalscoretracker.android.core.settings.PathDisplayMode
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.paths.SongPathDataPayload
import com.festivalscoretracker.android.data.paths.SongPathImagePayload
import com.festivalscoretracker.android.presentation.songs.SongPathsViewModel
import com.festivalscoretracker.android.testing.SongsFixtures
import com.festivalscoretracker.android.ui.theme.FestivalAccessibility
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.time.Duration
import kotlinx.coroutines.CompletableDeferred
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * CHOpt Paths sheet reachable states (issue #130, contract `chopt-paths`): image and text
 * loading/loaded, missing (404), offline with Retry, instrument and difficulty switches,
 * the Karaoke warning, zoom, the saved column order in the wide grid, 200% text and
 * reduced motion. Composes the sheet alone with lambda loaders so each state is gated.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SongPathsSheetUiTest {
    @get:Rule(order = 0)
    val windowInfo = WindowLayoutInfoPublisherRule()

    @get:Rule(order = 1)
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val calls = mutableListOf<String>()
    private var dontShowAgain = 0
    private var dismissed = 0

    // region Helpers

    private fun settle(millis: Long = 400) = repeat(4) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4)); rule.waitForIdle()
    }

    private fun count(tag: String, unmerged: Boolean = false) = rule.onAllNodesWithTag(tag, useUnmergedTree = unmerged).fetchSemanticsNodes().size

    private fun waitForTag(tag: String) = rule.waitUntil(10_000) { settle(100); count(tag) > 0 }

    private fun click(tag: String) {
        rule.onNodeWithTag(tag).performSemanticsAction(SemanticsActions.OnClick)
        settle()
    }

    private fun status() = rule.onNodeWithTag("fst.paths.status", useUnmergedTree = true).fetchSemanticsNode()
        .config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString().orEmpty()

    private fun waitForStatus(text: String) = rule.waitUntil(10_000) { settle(100); status() == text }

    private fun state(tag: String) = rule.onNodeWithTag(tag).fetchSemanticsNode().config.getOrNull(SemanticsProperties.StateDescription)

    private fun description(tag: String) = rule.onNodeWithTag(tag).fetchSemanticsNode().config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString().orEmpty()

    private fun heightDp(tag: String): Float = with(rule.density) { rule.onNodeWithTag(tag).fetchSemanticsNode().boundsInRoot.height.toDp().value }

    private fun realPng(): ByteArray {
        val bitmap = Bitmap.createBitmap(100, 200, Bitmap.Config.ARGB_8888).apply { eraseColor(android.graphics.Color.BLUE) }
        return ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    }

    private fun image(bytes: ByteArray = realPng()) = SongPathImagePayload(bytes, 100, 200, 7, 7)

    private fun text(): SongPathDataPayload {
        val path = FestivalApi.JSON.decodeFromString(SongPathData.serializer(), SongsFixtures.pathJson)
        return SongPathDataPayload(path, path.activationRows(), 7, 7)
    }

    private fun show(
        vm: SongPathsViewModel,
        columns: List<PathColumnKey> = PathColumnKey.entries,
        warning: Boolean = false,
        reduceMotion: Boolean = false,
    ) {
        rule.setContent {
            FestivalTheme {
                CompositionLocalProvider(LocalFestivalAccessibility provides FestivalAccessibility(reduceMotion = reduceMotion)) {
                    SongPathsSheet(vm, "Alpha Tune", columns, warning, { dontShowAgain++ }, { dismissed++ })
                }
            }
        }
        settle()
    }

    private fun viewModel(
        display: PathDisplayMode = PathDisplayMode.Image,
        instruments: List<Instrument> = listOf(Instrument.Lead, Instrument.Bass),
        loadImage: suspend (Instrument, PathDifficulty) -> SongPathImagePayload = { _, _ -> image() },
        loadText: suspend (Instrument, PathDifficulty) -> SongPathDataPayload = { _, _ -> text() },
    ) = SongPathsViewModel(
        instruments,
        display,
        { chart, difficulty -> calls += "image:${chart.name}:${difficulty.name}"; loadImage(chart, difficulty) },
        { chart, difficulty -> calls += "text:${chart.name}:${difficulty.name}"; loadText(chart, difficulty) },
    )

    // endregion

    // region Image

    @Test
    fun imageLoadingThenLoadedWithZoom() {
        val gate = CompletableDeferred<Unit>()
        show(viewModel(loadImage = { _, _ -> gate.await(); image() }))
        // image-loading: the spinner and the polite live region, no stale image.
        assertEquals(1, count("fst.paths.loading", unmerged = true))
        assertEquals(0, count("fst.paths.image"))
        assertEquals("Loading Lead Expert path", status())
        assertEquals("Paths for Alpha Tune", description("fst.song-detail.paths"))

        // image-loaded.
        gate.complete(Unit)
        waitForStatus("Lead Expert path image loaded")
        waitForTag("fst.paths.image")
        // The bitmap decodes on Dispatchers.Default after the container appears; wait for the image itself.
        rule.waitUntil(10_000) { settle(100); rule.onAllNodesWithContentDescription("Lead Expert CHOpt path").fetchSemanticsNodes().isNotEmpty() }
        rule.onNodeWithText("100%").assertExists()
        rule.onNodeWithContentDescription("Lead Expert CHOpt path").assertExists()

        // zoomed: 50% steps up to 300%, the buttons disable at the bounds.
        assertTrue(rule.onNodeWithTag("fst.paths.zoom-out").fetchSemanticsNode().config.contains(SemanticsProperties.Disabled))
        repeat(4) { click("fst.paths.zoom-in") }
        rule.onNodeWithText("300%").assertExists()
        assertTrue(rule.onNodeWithTag("fst.paths.zoom-in").fetchSemanticsNode().config.contains(SemanticsProperties.Disabled))
        click("fst.paths.zoom-out")
        rule.onNodeWithText("250%").assertExists()
        // M3 IconButton: 40 dp visual, 48 dp touch target.
        listOf("fst.paths.zoom-in", "fst.paths.zoom-out").forEach {
            rule.onNodeWithTag(it).assertTouchHeightIsEqualTo(48.dp).assertTouchWidthIsEqualTo(48.dp)
        }
    }

    @Test
    fun undecodableImageShowsReadableError() {
        show(viewModel(loadImage = { _, _ -> image(SongsFixtures.png()) }))
        waitForTag("fst.paths.image-error")
        rule.onNodeWithText("This path image couldn't be displayed.").assertExists()
    }

    // endregion

    // region Text

    @Test
    fun textLoadingThenLoadedRowsAreOneSpokenStop() {
        val gate = CompletableDeferred<Unit>()
        show(viewModel(display = PathDisplayMode.Text, loadText = { _, _ -> gate.await(); text() }))
        assertEquals(1, count("fst.paths.loading", unmerged = true))
        assertEquals(0, count("fst.paths.table"))
        gate.complete(Unit)
        waitForStatus("Lead Expert path loaded, 3 activations")
        waitForTag("fst.paths.row.3")
        assertTrue(description("fst.paths.row.1").startsWith("Activation 1: frets "))
        assertTrue(description("fst.paths.row.1").contains("Activate after the chord"))
        // Compact sheet: mobile cards, no desktop header.
        assertEquals(0, count("fst.paths.table.header"))
        rule.onNodeWithText("BEAT").assertDoesNotExist()
        assertEquals(listOf("text:Lead:Expert"), calls)
    }

    /**
     * Mean pixel brightness (0–1) of the node tagged [tag], drawn in software from the sheet's
     * window (Robolectric's `captureToImage` never gets a frame with the clock paused).
     */
    private fun brightness(tag: String): Float {
        val b = rule.onNodeWithTag(tag).fetchSemanticsNode().boundsInWindow
        val global = Class.forName("android.view.WindowManagerGlobal")
        val instance = global.getMethod("getInstance").invoke(null)
        @Suppress("UNCHECKED_CAST")
        val window = (global.getDeclaredField("mViews").apply { isAccessible = true }.get(instance) as List<View>).last()
        val whole = Bitmap.createBitmap(window.width, window.height, Bitmap.Config.ARGB_8888)
        rule.runOnUiThread { window.draw(Canvas(whole)) }
        val top = b.top.toInt().coerceAtLeast(0)
        val bottom = b.bottom.toInt().coerceAtMost(whole.height)
        assertTrue("$tag is on screen", top < bottom)
        var sum = 0f
        for (x in b.left.toInt() until b.right.toInt()) for (y in top until bottom) {
            val p = whole.getPixel(x, y)
            sum += (android.graphics.Color.red(p) + android.graphics.Color.green(p) + android.graphics.Color.blue(p)) / (3f * 255f)
        }
        return sum / ((b.right.toInt() - b.left.toInt()) * (bottom - top))
    }

    /** Release a gated load with the clock paused and step to the frame its content commits. */
    private fun commitGated(gate: CompletableDeferred<Unit>, loaded: String) {
        rule.mainClock.autoAdvance = false
        gate.complete(Unit)
        var frames = 0
        while (status() != loaded && frames++ < 200) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(16))
            rule.mainClock.advanceTimeByFrame()
        }
        assertEquals(loaded, status())
    }

    @Test
    fun textRowsStaggerInAfterTheSpinnerLikeWebTextStagger() {
        assertEquals(listOf(0, 60, 120, 600), listOf(0, 1, 2, 10).map(PathSwapTiming::rowStagger))
        val gate = CompletableDeferred<Unit>()
        show(viewModel(display = PathDisplayMode.Text, loadText = { _, _ -> gate.await(); text() }))
        commitGated(gate, "Lead Expert path loaded, 3 activations")
        // The table mounts with every row hidden (no container fade, no stale rows).
        rule.mainClock.advanceTimeByFrame()
        val hidden = listOf("fst.paths.row.1", "fst.paths.row.2").map(::brightness)
        // 100 ms in: row 1 is well into its fade, row 2 (60 ms later) has barely started.
        rule.mainClock.advanceTimeBy(100)
        val mid = listOf("fst.paths.row.1", "fst.paths.row.2").map(::brightness)
        rule.mainClock.advanceTimeBy(1_500)
        val full = listOf("fst.paths.row.1", "fst.paths.row.2").map(::brightness)
        val revealed = (0..1).map { (mid[it] - hidden[it]) / (full[it] - hidden[it]) }
        assertTrue("rows draw once revealed ($hidden → $full)", full.indices.all { full[it] > hidden[it] + 0.02f })
        assertTrue("row 1 leads row 2 by the 60 ms stagger ($revealed)", revealed[0] > revealed[1] + 0.1f)
        assertTrue("row 1 is mid-fade at 100 ms ($revealed)", revealed[0] in 0.15f..0.85f)
    }

    @Test
    fun reducedMotionShowsTextRowsWithoutStagger() {
        val gate = CompletableDeferred<Unit>()
        show(viewModel(display = PathDisplayMode.Text, loadText = { _, _ -> gate.await(); text() }), reduceMotion = true)
        commitGated(gate, "Lead Expert path loaded, 3 activations")
        rule.mainClock.advanceTimeByFrame()
        val first = listOf("fst.paths.row.1", "fst.paths.row.2").map(::brightness)
        rule.mainClock.advanceTimeBy(1_500)
        val later = listOf("fst.paths.row.1", "fst.paths.row.2").map(::brightness)
        (0..1).forEach { assertEquals("row ${it + 1} fully shown on its first frame", later[it], first[it], 0.01f) }
    }

    /**
     * The image fades in, and out on a switch, on web `opacity 300ms ease` (Compose [androidx.compose.animation.core.Ease],
     * load-transition R3, #177 decision): halfway through the fade CSS `ease` is ~80% done (75–85% within
     * a frame either way) where linear would be 50%, so a regression to `LinearEasing` fails.
     */
    @Test
    fun imageSwitchFadesOnTheWebEaseCurve() {
        val expert = CompletableDeferred<Unit>()
        val hard = CompletableDeferred<Unit>()
        val vm = viewModel(loadImage = { _, difficulty -> (if (difficulty == PathDifficulty.Expert) expert else hard).await(); image() })
        show(vm)
        commitGated(expert, "Lead Expert path image loaded")
        // The decoded chart commits fully transparent (no spinner, no stale image), then eases in.
        rule.mainClock.advanceTimeByFrame()
        val hidden = brightness("fst.paths.image")
        rule.mainClock.advanceTimeBy(PathSwapTiming.FADE_MILLIS / 2)
        val mid = brightness("fst.paths.image")
        rule.mainClock.advanceTimeBy(1_000)
        val shown = brightness("fst.paths.image")
        assertTrue("the chart draws once faded in ($hidden → $shown)", shown > hidden + 0.02f)
        val fadedIn = (mid - hidden) / (shown - hidden)
        assertTrue("fade-in at 150 ms follows CSS ease, not linear ($fadedIn)", fadedIn in 0.68f..0.95f)

        // Difficulty switch: the old chart fades out on the same curve before the spinner.
        vm.selectDifficulty(PathDifficulty.Hard)
        shadowOf(Looper.getMainLooper()).idle()
        rule.mainClock.advanceTimeByFrame()
        assertEquals("Loading Lead Hard path", status())
        rule.mainClock.advanceTimeBy(PathSwapTiming.FADE_MILLIS / 2)
        val left = (brightness("fst.paths.image") - hidden) / (shown - hidden)
        assertTrue("fade-out at 150 ms follows CSS ease, not linear ($left)", left in 0.05f..0.32f)
    }

    @Test
    @Config(qualifiers = "w1280dp-h800dp-xhdpi")
    fun wideGridFollowsSavedColumnOrder() {
        val order = listOf(PathColumnKey.Score, PathColumnKey.Od, PathColumnKey.Time, PathColumnKey.Beat, PathColumnKey.Note)
        show(viewModel(display = PathDisplayMode.Text), columns = order)
        waitForTag("fst.paths.table.header")
        val lefts = listOf("SCORE", "OVERDRIVE %", "TIME", "BEAT", "ACTIVATION").map { label ->
            rule.onNodeWithText(label).fetchSemanticsNode().boundsInRoot.left
        }
        assertEquals("columns follow the saved order", lefts.sorted(), lefts)
        assertTrue(rule.onNodeWithTag("fst.paths.table.header").fetchSemanticsNode().config.contains(SemanticsProperties.Heading))
    }

    @Test
    @Config(qualifiers = "w1280dp-h800dp-xhdpi")
    fun wideSheetAtLargeTextKeepsCardsInsteadOfClippedGrid() {
        RuntimeEnvironment.setFontScale(2f)
        show(viewModel(display = PathDisplayMode.Text))
        waitForTag("fst.paths.row.1")
        assertEquals("200% text drops the five-column grid", 0, count("fst.paths.table.header"))
        // Stacked mobile card: Activation, Beat, Time, Score and Overdrive each on their own lines.
        assertTrue("row 1 stacks its values (${heightDp("fst.paths.row.1")} dp)", heightDp("fst.paths.row.1") >= 380f)
    }

    @Test
    fun pathGridNeedsSixHundredDpAtFullSizeText() {
        assertTrue(usesPathGrid(640f, 1f))
        assertTrue(usesPathGrid(600f, 0.85f))
        assertEquals(false, usesPathGrid(599f, 1f))
        assertEquals(false, usesPathGrid(640f, 1.15f))
        assertEquals(false, usesPathGrid(640f, 2f))
        assertTrue(usesPathGrid(1280f, 2f))
    }

    // endregion

    // region Failures

    @Test
    fun missingPathReadsNotGenerated() {
        show(viewModel(loadImage = { _, _ -> throw FestivalApiException.HttpStatus(404) }))
        waitForTag("fst.paths.not-generated")
        rule.onNodeWithText("No Expert path has been generated for Lead yet.").assertExists()
        assertEquals("No Expert path has been generated for Lead yet.", status())
        assertEquals(0, count("fst.paths.error"))
    }

    @Test
    fun offlineShowsRetryThatReloads() {
        var online = false
        show(viewModel(loadImage = { _, _ -> if (!online) throw IOException("offline"); image() }))
        waitForTag("fst.paths.error")
        assertEquals("Path unavailable", status())
        online = true
        rule.onAllNodesWithText("Retry", substring = true).fetchSemanticsNodes().also { assertTrue("Retry offered", it.isNotEmpty()) }
        rule.onNodeWithText("Retry", substring = true).performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.paths.image")
        assertEquals(0, count("fst.paths.error"))
        assertEquals(listOf("image:Lead:Expert", "image:Lead:Expert"), calls)
    }

    // endregion

    // region Switches

    @Test
    fun instrumentAndDifficultySwitchReload() {
        show(viewModel())
        waitForTag("fst.paths.image")
        // Bottom controls: buttons with Expanded/Collapsed state and 48 dp+ targets.
        listOf("fst.paths.instrument.open", "fst.paths.difficulty.open", "fst.paths.display.open").forEach { tag ->
            val config = rule.onNodeWithTag(tag).fetchSemanticsNode().config
            assertEquals(Role.Button, config.getOrNull(SemanticsProperties.Role))
            assertEquals("Collapsed", config.getOrNull(SemanticsProperties.StateDescription))
            assertTrue("$tag target", heightDp(tag) >= 48f)
        }
        assertEquals("Instrument: Lead", description("fst.paths.instrument.open"))

        // instrument-switch.
        click("fst.paths.instrument.open")
        assertEquals("Expanded", state("fst.paths.instrument.open"))
        waitForTag("fst.paths.instrument.Solo_Bass")
        click("fst.paths.instrument.Solo_Bass")
        waitForStatus("Bass Expert path image loaded")
        assertEquals("Instrument: Bass", description("fst.paths.instrument.open"))

        // difficulty-switch: a radio grid with the choice selected.
        click("fst.paths.difficulty.open")
        waitForTag("fst.paths.difficulty.hard")
        val expert = rule.onNodeWithTag("fst.paths.difficulty.expert").fetchSemanticsNode().config
        assertEquals(Role.RadioButton, expert.getOrNull(SemanticsProperties.Role))
        assertEquals(true, expert.getOrNull(SemanticsProperties.Selected))
        assertTrue(heightDp("fst.paths.difficulty.hard") >= 48f)
        click("fst.paths.difficulty.hard")
        waitForStatus("Bass Hard path image loaded")
        assertEquals("Difficulty: Hard", description("fst.paths.difficulty.open"))
        // Choosing the current value again closes the panel without a reload.
        click("fst.paths.difficulty.hard")
        settle()
        assertEquals("Collapsed", state("fst.paths.difficulty.open"))
        assertEquals(listOf("image:Lead:Expert", "image:Bass:Expert", "image:Bass:Hard"), calls)

        // Image → Text.
        click("fst.paths.display.open")
        waitForTag("fst.paths.display.text")
        click("fst.paths.display.text")
        waitForStatus("Bass Hard path loaded, 3 activations")
        assertEquals("View: Text", description("fst.paths.display.open"))
        click("fst.paths.close")
        assertEquals(1, dismissed)
    }

    @Test
    fun reducedMotionSwapsWithoutFadesOrMinimumSpinner() {
        show(viewModel(), reduceMotion = true)
        settle(50)
        assertEquals("Lead Expert path image loaded", status())
        click("fst.paths.difficulty.open")
        rule.onNodeWithTag("fst.paths.difficulty.medium").performSemanticsAction(SemanticsActions.OnClick)
        // One frame later the new chart is up: no 300 ms fade or 400 ms spinner hold.
        settle(50)
        assertEquals("Lead Medium path image loaded", status())
        assertEquals(0, count("fst.paths.loading", unmerged = true))
    }

    // endregion

    // region Warning and large text

    @Test
    fun karaokeWarningOkKeepsAskingAndNeverPersists() {
        show(viewModel(), warning = true)
        waitForTag("fst.paths.karaoke-warning")
        rule.onNodeWithText("Karaoke is not available for path visualization yet.").assertExists()
        click("fst.paths.warning.ok")
        assertEquals(0, count("fst.paths.karaoke-warning"))
        assertEquals(0, dontShowAgain)
    }

    @Test
    fun karaokeWarningDontShowAgainPersists() {
        show(viewModel(), warning = true)
        waitForTag("fst.paths.warning.never")
        click("fst.paths.warning.never")
        assertEquals(0, count("fst.paths.karaoke-warning"))
        assertEquals(1, dontShowAgain)
    }

    @Test
    fun largeTextKeepsControlsAndRowsReachable() {
        RuntimeEnvironment.setFontScale(2f)
        show(viewModel(display = PathDisplayMode.Text))
        waitForTag("fst.paths.row.1")
        assertTrue("phone card stacks Beat/Time/Score at 200% (${heightDp("fst.paths.row.1")} dp)", heightDp("fst.paths.row.1") >= 380f)
        listOf("fst.paths.instrument.open", "fst.paths.difficulty.open", "fst.paths.display.open").forEach { tag ->
            assertTrue("$tag target at 200%", heightDp(tag) >= 48f)
        }
        // The controls stay inside the sheet below the scrolling table.
        val sheet = rule.onNodeWithTag("fst.song-detail.paths").fetchSemanticsNode().boundsInRoot
        val controls = rule.onNodeWithTag("fst.paths.selectors").fetchSemanticsNode().boundsInRoot
        assertTrue("controls inside the sheet", controls.bottom <= sheet.bottom + with(rule.density) { 1.dp.toPx() } && controls.top >= sheet.top)
        click("fst.paths.difficulty.open")
        waitForTag("fst.paths.difficulty.easy")
        assertTrue(heightDp("fst.paths.difficulty.easy") >= 48f)
    }

    @Test
    fun fullSizeTextKeepsBeatTimeScoreOnOneLine() {
        show(viewModel(display = PathDisplayMode.Text))
        waitForTag("fst.paths.row.1")
        assertTrue("row 1 is the compact card (${heightDp("fst.paths.row.1")} dp)", heightDp("fst.paths.row.1") < 260f)
        assertEquals("411 dp phone keeps one control row", 0, count("fst.paths.selectors.stacked"))
        assertEquals(1, difficultyLines())
    }

    /** Lines the difficulty button's label wraps to. */
    private fun difficultyLines(): Int {
        val node = rule.onNode(hasText("Expert") and hasAnyAncestor(hasTestTag("fst.paths.difficulty.open")), useUnmergedTree = true).fetchSemanticsNode()
        val layouts = mutableListOf<TextLayoutResult>()
        node.config[SemanticsActions.GetTextLayoutResult].action?.invoke(layouts)
        return layouts.single().lineCount
    }

    @Test
    @Config(qualifiers = "w320dp-h640dp-xhdpi")
    fun narrowPaneStacksDifficultyAboveIconButtons() {
        show(viewModel(display = PathDisplayMode.Text))
        waitForTag("fst.paths.row.1")
        waitForTag("fst.paths.selectors.stacked")
        assertEquals("Expert stays on one line", 1, difficultyLines())
        val difficulty = bounds("fst.paths.difficulty.open")
        val instrument = bounds("fst.paths.instrument.open")
        val display = bounds("fst.paths.display.open")
        assertTrue("difficulty above the icon buttons", difficulty.bottom <= instrument.top && difficulty.bottom <= display.top)
        assertTrue("instrument before view", instrument.right <= display.left)
        listOf("fst.paths.instrument.open", "fst.paths.difficulty.open", "fst.paths.display.open").forEach { assertTrue("$it target", heightDp(it) >= 48f) }
    }

    @Test
    fun controlRowNeedsRoomForTheWidestLabel() {
        // Instrument 86 dp + view 82 dp + gaps 24 dp + difficulty (58 dp + label).
        assertTrue(controlRowFits(379.dp, 50.dp))
        assertTrue(controlRowFits(300.dp, 50.dp))
        assertEquals(false, controlRowFits(299.dp, 50.dp))
        assertEquals(false, controlRowFits(288.dp, 50.dp))
    }

    // endregion

    // region Fold

    /** Publish one vertical fold (centred, zero width) to Jetpack WindowManager. */
    private fun fold(state: State) {
        windowInfo.overrideWindowLayoutInfo(TestWindowLayoutInfo(listOf(FoldingFeature(rule.activity, state = state, orientation = Orientation.VERTICAL))))
        settle()
    }

    private fun bounds(tag: String) = rule.onNodeWithTag(tag).fetchSemanticsNode().boundsInWindow

    @Test
    @Config(qualifiers = "w852dp-h883dp-xhdpi")
    fun halfOpenBookPostureKeepsPathAndControlsOffTheHinge() {
        show(viewModel(display = PathDisplayMode.Text))
        waitForTag("fst.paths.row.1")
        val hinge = rule.activity.window.decorView.width / 2f
        assertTrue("the centred 640 dp sheet spans the window centre while flat", bounds("fst.song-detail.paths").let { it.left < hinge && it.right > hinge })
        fold(State.HALF_OPENED)
        // FestivalModalSheet (SheetHinge) moves the whole sheet to the leading half (a tie keeps the leading side).
        rule.waitUntil(10_000) { settle(100); bounds("fst.song-detail.paths").right <= hinge }
        assertTrue("row ends before the hinge (${bounds("fst.paths.row.1")} vs $hinge)", bounds("fst.paths.row.1").right <= hinge)
        assertEquals("a half pane uses the stacked cards", 0, count("fst.paths.table.header"))
        assertTrue("controls end before the hinge", bounds("fst.paths.selectors").right <= hinge)
        assertEquals("the ~426 dp half keeps one control row", 0, count("fst.paths.selectors.stacked"))
        assertEquals("Expert stays on one line", 1, difficultyLines())
        click("fst.paths.difficulty.open")
        waitForTag("fst.paths.difficulty.easy")
        listOf("easy", "medium", "hard", "expert").forEach { assertTrue("$it before the hinge", bounds("fst.paths.difficulty.$it").right <= hinge) }
        click("fst.paths.difficulty.open")
        click("fst.paths.display.open")
        click("fst.paths.display.image")
        waitForTag("fst.paths.image")
        assertTrue("image before the hinge", bounds("fst.paths.image").right <= hinge)
        assertTrue("zoom before the hinge", bounds("fst.paths.zoom-in").right <= hinge)
    }

    @Test
    @Config(qualifiers = "w852dp-h883dp-xhdpi")
    fun flatFoldKeepsTheCentredSheet() {
        show(viewModel(display = PathDisplayMode.Text))
        waitForTag("fst.paths.row.1")
        fold(State.FLAT)
        val centre = rule.activity.window.decorView.width / 2f
        assertTrue("a flat fold is not separating: the sheet stays centred", bounds("fst.song-detail.paths").let { it.left < centre && it.right > centre })
        assertEquals("640 dp sheet keeps the desktop grid", 1, count("fst.paths.table.header"))
    }

    @Test
    @Config(qualifiers = "w852dp-h883dp-xhdpi", fontScale = 2f)
    fun halfOpenAtLargeTextKeepsTheSheetOffTheHinge() {
        show(viewModel(display = PathDisplayMode.Text))
        waitForTag("fst.paths.row.1")
        fold(State.HALF_OPENED)
        val hinge = rule.activity.window.decorView.width / 2f
        rule.waitUntil(10_000) { settle(100); bounds("fst.song-detail.paths").right <= hinge }
        assertTrue("row ends before the hinge", bounds("fst.paths.row.1").right <= hinge)
        assertTrue("controls end before the hinge", bounds("fst.paths.selectors").right <= hinge)
    }

    // endregion
}
