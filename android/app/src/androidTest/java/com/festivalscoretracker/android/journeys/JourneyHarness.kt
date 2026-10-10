package com.festivalscoretracker.android.journeys

import android.content.res.Configuration
import android.content.res.Resources
import android.os.Build
import android.os.SystemClock
import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.platform.ViewRootForTest
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getAllSemanticsNodes
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.test.ComposeAccessibilityValidator
import androidx.compose.ui.test.ComposeTimeoutException
import androidx.compose.ui.test.DeviceConfigurationOverride
import androidx.compose.ui.test.FontScale
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.emptyPreferences
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.test.ext.junit.rules.ActivityScenarioRule
import androidx.test.platform.app.InstrumentationRegistry
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowInfoTracker
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.ui.shell.FestivalApp
import com.google.android.apps.common.testing.accessibility.framework.AccessibilityCheckResult.AccessibilityCheckResultType
import com.google.android.apps.common.testing.accessibility.framework.integrations.espresso.AccessibilityValidator
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import java.util.Locale
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue

// region Preferences

/** Process-local preferences so device journeys never touch the app's saved settings. */
class MemoryPreferences(initial: Preferences = emptyPreferences()) : DataStore<Preferences> {
    private val state = MutableStateFlow(initial)
    override val data: Flow<Preferences> = state
    override suspend fun updateData(transform: suspend (t: Preferences) -> Preferences): Preferences =
        transform(state.value).also { state.value = it }
}

// endregion

// region Harness

/** Rule type every journey uses. */
typealias JourneyRule = AndroidComposeTestRule<ActivityScenarioRule<ComponentActivity>, ComponentActivity>

/**
 * Shared helpers for instrumented journeys on one FST AVD (run through `device.py test`):
 * launching the whole shell against synthetic fixtures, waiting and tapping by test tag,
 * separating-hinge checks, Accessibility Test Framework checks and a TalkBack reading-order
 * dump (logcat tag [READING_ORDER_TAG]; `device.py drive --steps "logcat:<file>@FST_A11Y"`).
 *
 * @property rule The journey's compose rule.
 */
class JourneyHarness(private val rule: JourneyRule) {
    /**
     * Launch the full app shell.
     *
     * @param debug Debug launch (route, profile, …).
     * @param transport Fixture transport.
     * @param preferences Settings store.
     * @param fontScale Font scale to render the app at, read in composition so a test can switch
     *   it in place (backed by snapshot state); `null` keeps the device's own. Modals opened
     *   after a switch (sheets and dialogs are separate windows) render at it too. The
     *   activity's original scale comes back when the activity is destroyed at the end of the
     *   test, so a journey that ends at 200% does not leak it into the next test's activity.
     */
    fun launch(
        debug: DebugLaunch,
        transport: FakeTransport,
        preferences: DataStore<Preferences> = MemoryPreferences(),
        fontScale: (() -> Float)? = null,
    ) {
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = preferences)
        rule.setContent {
            key(generation) {
                if (fontScale == null) {
                    FestivalApp(container, debug)
                } else {
                    val scale = fontScale()
                    SideEffect { applyWindowFontScale(scale) }
                    DeviceConfigurationOverride(DeviceConfigurationOverride.FontScale(scale)) { FestivalApp(container, debug) }
                }
            }
        }
    }

    /** Bumped by [recreateApp] to dispose and re-create the app's composition. */
    private var generation by mutableIntStateOf(0)

    /**
     * Re-create the app as an activity recreation does (a font-size change: font scale is not in
     * the manifest's `configChanges`): the shell's composition and every scope `FestivalApp`
     * started (such as the selected player's read) end, and a new composition starts with the
     * same process `AppContainer` and activity-scoped ViewModels. Saved instance state is not
     * restored, so the shell starts again at its [DebugLaunch].
     */
    fun recreateApp() {
        rule.runOnUiThread { generation++ }
        rule.waitForIdle()
    }

    /** [readingOrder] walks the tree Compose publishes to TalkBack ([publishTalkBackTree]). */
    private var talkBackTree = false

    /**
     * Make every Compose view in the window publish to the test's UiAutomation what it publishes
     * to TalkBack. Compose computes `traversalIndex`/`isTraversalGroup` order as
     * `traversalBefore`/`traversalAfter` links, and sends the content-change events that refresh
     * UiAutomation's node cache, only while a real accessibility service is on; without this,
     * [readingOrder] sees no links (it falls back to tree order) and can read rows that scrolled
     * away. Call after [launch]; from then on [readingOrder] is TalkBack's linear order and
     * reads a fresh tree. UiAutomation connects first: a forced view sends events, and the
     * platform throws "Accessibility off" for any sent before the app's AccessibilityManager is on.
     * A `Dialog` or `ModalBottomSheet` composes in its own window (API 29+: every window of the
     * process is covered), and one opened later is published by the next [readingOrder].
     */
    fun publishTalkBackTree() {
        InstrumentationRegistry.getInstrumentation().uiAutomation
        val manager = rule.activity.getSystemService(android.view.accessibility.AccessibilityManager::class.java)
        rule.waitUntil(10_000) { manager.isEnabled }
        rule.waitForIdle()
        assertTrue("no Compose view to publish", forceComposeRoots() > 0)
        talkBackTree = true
        rule.waitForIdle()
    }

    /**
     * Force TalkBack publishing on every Compose root in the activity's window and, on API 29+,
     * in every other window of the process (modal dialogs and sheets).
     *
     * @return Number of Compose roots found.
     */
    private fun forceComposeRoots(): Int {
        var count = 0
        rule.runOnUiThread {
            fun roots(view: android.view.View): List<ViewRootForTest> = when {
                view is ViewRootForTest -> listOf(view)
                view is android.view.ViewGroup -> (0 until view.childCount).flatMap { roots(view.getChildAt(it)) }
                else -> emptyList()
            }
            val windows = if (android.os.Build.VERSION.SDK_INT >= 29) {
                (android.view.inspector.WindowInspector.getGlobalWindowViews() + rule.activity.window.decorView).distinct()
            } else {
                listOf(rule.activity.window.decorView)
            }
            val found = windows.flatMap { roots(it) }
            found.forEach { it.forceAccessibilityForTesting(true) }
            count = found.size
        }
        return count
    }

    /** Traversal links the last [readingOrder] followed (0: it fell back to tree order). */
    var lastReadingLinks = 0
        private set

    /**
     * Give modal windows [scale]. `DeviceConfigurationOverride` stops at a window boundary: a
     * `ModalBottomSheet` or `Dialog` composes in its own window, whose density comes from the
     * activity's resources, so without this a "200%" sheet still renders at the device scale.
     *
     * The activity's `Resources` share their implementation with every later activity of the
     * same configuration in this instrumentation process, so the device's own scale is put back
     * when the activity is destroyed. Without that, one 200 % journey left every following test
     * class at 200 % text in a full `connectedDebugAndroidTest` run (issue #528).
     *
     * @param scale Font scale.
     */
    private fun applyWindowFontScale(scale: Float) {
        val activity = rule.activity
        val resources = activity.resources
        if (resources.configuration.fontScale == scale) return
        if (activity !in restoresFontScale) {
            restoresFontScale += activity
            val original = resources.configuration.fontScale
            activity.lifecycle.addObserver(
                LifecycleEventObserver { _, event ->
                    if (event == Lifecycle.Event.ON_DESTROY) {
                        setFontScale(resources, original)
                        restoresFontScale -= activity
                    }
                },
            )
        }
        setFontScale(resources, scale)
    }

    /** Activities whose shared resources get the device's font scale back on destroy. */
    private val restoresFontScale = mutableSetOf<ComponentActivity>()

    /**
     * Set [scale] on [resources] (shared with the activity's dialogs and sheets).
     *
     * @param resources Activity resources.
     * @param scale Font scale.
     */
    @Suppress("DEPRECATION")
    private fun setFontScale(resources: Resources, scale: Float) {
        if (resources.configuration.fontScale == scale) return
        resources.updateConfiguration(Configuration(resources.configuration).apply { fontScale = scale }, resources.displayMetrics)
    }

    /** Distinct ATF findings so far (`TYPE | Check | element | message`). */
    val accessibilityFindings = linkedSetOf<String>()

    /**
     * Run the Accessibility Test Framework on the whole window before every interaction
     * (touch target ≥ 48 dp, labels, contrast, duplicate clickable bounds, …). Findings are
     * collected and logged under [ATF_TAG]; call [assertAccessible] at the end of the journey
     * so one run lists every error at once.
     */
    fun enableAccessibilityChecks() {
        val validator = AccessibilityValidator().setRunChecksFromRootView(true).setThrowExceptionForErrors(false)
        val composeValidator = object : ComposeAccessibilityValidator {
                override fun check(view: android.view.View) {
                    validator.checkAndReturnResults(view).forEach { result ->
                        val type = result.type
                        if (type != AccessibilityCheckResultType.ERROR && type != AccessibilityCheckResultType.WARNING) return@forEach
                        val element = result.element?.let { e ->
                            (e.resourceName ?: e.contentDescription ?: e.text)?.toString()
                                ?: "${e.className?.toString()?.substringAfterLast('.')} ${e.boundsInScreen}"
                        } ?: "?"
                        val check = result.sourceCheckClass.simpleName
                        val line = "$type | $check | $element | ${result.getMessage(Locale.US)}"
                        if (check == "TouchTargetSizeCheck" && element.startsWith("fst.") && composedFullSize(view, element)) fullSizeTargets += element
                        if (accessibilityFindings.add(line)) Log.w(ATF_TAG, line)
                    }
                }
            }
        checkNow = { rule.runOnUiThread { composeValidator.check(rule.activity.window.decorView) } }
        rule.setComposeAccessibilityValidator(composeValidator)
    }

    /**
     * ATF measures a row cut off by its scrolling container at its visible height; a
     * touch-target finding whose tagged node is really at least 48 dp tall is that artifact.
     * Likewise a text field scrolled to a sliver hides its label child, so a missing-label
     * finding on a tagged node that composes a label (a text descendant) is a clipping artifact.
     *
     * @param finding Collected finding line.
     * @return True for a clipping artifact.
     */
    private fun clippedTouchTarget(finding: String): Boolean {
        val parts = finding.split(" | ")
        val tag = parts.getOrNull(2)?.takeIf { it.startsWith("fst.") } ?: return false
        if (parts.getOrNull(1) == "SpeakableTextPresentCheck") {
            if (tag in labelledTags) return true
            val labelled = hasAnyAncestor(hasTestTag(tag)) and SemanticsMatcher.keyIsDefined(SemanticsProperties.Text)
            return (exists(tag) && rule.onAllNodes(labelled, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty())
                .also { if (it) labelledTags += tag }
        }
        if (parts.getOrNull(1) != "TouchTargetSizeCheck") return false
        if (tag in fullSizeTargets) return true
        val min = with(rule.density) { 48.dp.toPx() } - 1
        val nodes = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes()
        if (nodes.isNotEmpty() && nodes.all { it.size.height >= min && it.size.width >= min }) return true
        // A Material icon button draws 40 dp and extends its touch bounds to 48 dp; partly
        // scrolled off (the hide-on-scroll floating toolbar) ATF measures the cut-off part. Its
        // accessibility node, once fully shown, reports the real touch bounds (issue #171).
        if (nodes.isEmpty()) return false
        fun fullSize() = visibleAccessibilityNodes(tag).let { shown ->
            shown.isNotEmpty() && shown.all { n ->
                val box = android.graphics.Rect().also(n::getBoundsInScreen)
                box.height() >= min && box.width() >= min
            }
        }
        return runCatching { rule.waitUntil(5_000) { fullSize() } }.isSuccess
    }

    /** ATF can expose an unlabelled Compose child after the scroll viewport clips it to a sliver. */
    private fun clippedUnlabelledView(element: String): Boolean {
        val match = Regex("""View Rect\((-?\d+), (-?\d+) - (-?\d+), (-?\d+)\)""").matchEntire(element) ?: return false
        val bounds = android.graphics.Rect(
            match.groupValues[1].toInt(),
            match.groupValues[2].toInt(),
            match.groupValues[3].toInt(),
            match.groupValues[4].toInt(),
        )
        if (bounds.height() > with(rule.density) { 8.dp.roundToPx() }) return false
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        if (android.os.Build.VERSION.SDK_INT >= 34) automation.clearCache()
        fun find(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
            node ?: return null
            val nodeBounds = android.graphics.Rect().also(node::getBoundsInScreen)
            if (node.isVisibleToUser && nodeBounds == bounds) return node
            for (i in 0 until node.childCount) find(node.getChild(i))?.let { return it }
            return null
        }
        return find(automation.rootInActiveWindow) != null
    }

    /**
     * Visible nodes in the window's accessibility tree whose resource id is [tag].
     *
     * @param tag Test tag (exposed as the resource id).
     * @return Matching nodes.
     */
    private fun visibleAccessibilityNodes(tag: String): List<AccessibilityNodeInfo> {
        val out = mutableListOf<AccessibilityNodeInfo>()
        fun walk(n: AccessibilityNodeInfo?) {
            n ?: return
            if (n.viewIdResourceName == tag && n.isVisibleToUser) out += n
            for (i in 0 until n.childCount) walk(n.getChild(i))
        }
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        // The cache can keep bounds from before the toolbar slid back in.
        if (android.os.Build.VERSION.SDK_INT >= 34) automation.clearCache()
        walk(automation.rootInActiveWindow)
        return out
    }

    /**
     * Fail unless every visible accessibility node tagged [tag] is at least 48 dp each way.
     * TalkBack's explore-by-touch uses these bounds, which Compose trims where a later sibling's
     * touch bounds overlap; [assertAccessible] skips such a finding while the Compose node is
     * still 48 dp, so a journey asserts the published bounds directly (issue #422).
     *
     * @param tag Test tag (exposed as the resource id).
     */
    fun assertFullTouchTarget(tag: String) {
        val min = with(rule.density) { 48.dp.toPx() } - 1
        var last = emptyList<android.graphics.Rect>()
        val full = runCatching {
            rule.waitUntil(5_000) {
                last = visibleAccessibilityNodes(tag).map { android.graphics.Rect().also(it::getBoundsInScreen) }
                last.isNotEmpty() && last.all { it.height() >= min && it.width() >= min }
            }
        }.isSuccess
        assertTrue("$tag accessibility bounds $last are under 48 dp (${min + 1} px)", full)
    }

    /** Checks the current window when accessibility checks are on. */
    private var checkNow: () -> Unit = {}

    /** Tags whose missing-label finding proved to be a clipped label (resolved while composed). */
    private val labelledTags = mutableSetOf<String>()

    /**
     * Findings [readingOrder] proved to be clipping artifacts while their nodes were composed: a
     * row partly under a pinned header or the viewport edge can scroll out of composition before
     * [assertAccessible] runs (issue #462).
     */
    private val clippedFindings = mutableSetOf<String>()

    /**
     * Tags whose touch-target finding the composed node disproved when ATF recorded it. A
     * dialog that is moving (IME, growing content) can report a 47 dp sliver of a 48 dp button;
     * once the dialog closes, [assertAccessible] could no longer measure the node (issue #432).
     */
    private val fullSizeTargets = mutableSetOf<String>()

    /**
     * Whether every composed node tagged [tag] in [view]'s window lays out at least 48 × 48 dp.
     * Runs on the UI thread inside the ATF callback, so it reads the semantics owners directly.
     *
     * @param view View ATF checked.
     * @param tag Test tag.
     * @return True when the composed targets are full size.
     */
    private fun composedFullSize(view: android.view.View, tag: String): Boolean {
        val min = 48f * view.resources.displayMetrics.density - 1
        fun roots(v: android.view.View): List<ViewRootForTest> = when {
            v is ViewRootForTest -> listOf(v)
            v is android.view.ViewGroup -> (0 until v.childCount).flatMap { roots(v.getChildAt(it)) }
            else -> emptyList()
        }
        val nodes = roots(view.rootView).flatMap { it.semanticsOwner.getAllSemanticsNodes(mergingEnabled = false) }
            .filter { it.config.getOrNull(SemanticsProperties.TestTag) == tag }
        return nodes.isNotEmpty() && nodes.all { it.size.width >= min && it.size.height >= min }
    }

    /** Fail with every ATF error collected during the journey (warnings only log). */
    fun assertAccessible() {
        val errors = accessibilityFindings.filter { finding ->
            finding.startsWith("ERROR") &&
                finding !in clippedFindings &&
                !clippedTouchTarget(finding) &&
                !scrimSliver(finding) &&
                !(finding.split(" | ").getOrNull(1) == "SpeakableTextPresentCheck" &&
                    clippedUnlabelledView(finding.split(" | ").getOrNull(2).orEmpty()))
        }
        assertTrue("Accessibility errors:\n" + errors.joinToString("\n"), errors.isEmpty())
    }

    /**
     * Material's `ModalBottomSheet` scrim is a clickable "Close sheet" node; Compose reports its
     * uncovered part, which above a fully expanded compact sheet on API 34 is only the
     * [com.festivalscoretracker.android.ui.common.SHEET_TOP_GAP_DP] strip (1080×21 px on a
     * Pixel 6), so ATF measures an 8 dp target. Every Festival sheet has the equivalent 48 dp
     * header Close and Back (modal-shell R3/R4, `ModalCloseJourneyTest`), the WCAG 2.5.8
     * "equivalent" exception, so only that touch-target finding is ignored (issue #418).
     *
     * @param finding Collected finding line.
     * @return True for the scrim strip's touch-target finding.
     */
    private fun scrimSliver(finding: String): Boolean = finding.split(" | ").let {
        it.getOrNull(1) == "TouchTargetSizeCheck" && it.getOrNull(2) == "Close sheet"
    }

    /**
     * Whether a node with [tag] exists (unmerged tree).
     *
     * @param tag Test tag.
     * @return True when present.
     */
    fun exists(tag: String): Boolean = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    /**
     * Wait for a node.
     *
     * @param tag Test tag.
     * @param timeoutMs Timeout.
     */
    fun waitForTag(tag: String, timeoutMs: Long = 15_000) {
        try {
            rule.waitUntil(timeoutMs) { exists(tag) }
        } catch (timeout: ComposeTimeoutException) {
            throw AssertionError("Timed out waiting for $tag", timeout)
        }
    }

    /**
     * Wait for a node to leave.
     *
     * @param tag Test tag.
     */
    fun waitGone(tag: String) = rule.waitUntil(15_000) { !exists(tag) }

    /**
     * Wait until the window's accessibility tree (what TalkBack and [readingOrder] read) shows
     * [present] and no longer shows [absent]. UiAutomation's node cache trails Compose's
     * semantics by a few throttled content-change events, so a [readingOrder] straight after a
     * page switch can still list the previous page.
     *
     * Each poll waits for Compose to idle, then clears UiAutomation's node cache (API 34+) so it
     * reads the window's live tree: only the root is fetched fresh, and children come from a cache
     * that only accessibility events invalidate. On a slow, freshly booted emulator a missed or late
     * event left that cache stale for the whole wait, so every half-open fold journey timed out at
     * its first call (#568). Polls are spaced so the tree walk does not starve the UI thread, and a
     * timeout fails with what the tree and Compose showed.
     *
     * @param present Test tag (exposed as the node's resource id) that must be in the tree.
     * @param absent Test tag that must have left the tree, or `null`.
     * @param timeoutMs Timeout.
     */
    fun awaitAccessibilityTree(present: String, absent: String? = null, timeoutMs: Long = 15_000) {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        fun ids(node: AccessibilityNodeInfo?, into: MutableSet<String> = mutableSetOf()): Set<String> {
            node ?: return into
            node.viewIdResourceName?.let(into::add)
            for (i in 0 until node.childCount) ids(node.getChild(i), into)
            return into
        }
        val deadline = SystemClock.uptimeMillis() + timeoutMs
        while (true) {
            rule.waitForIdle()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) automation.clearCache()
            val root = automation.rootInActiveWindow
            val seen = ids(root)
            if (present in seen && (absent == null || absent !in seen)) return
            if (SystemClock.uptimeMillis() > deadline) {
                throw AssertionError(
                    "Accessibility tree of ${root?.packageName ?: "no active window"} never showed $present" +
                        "${absent?.let { " without $it" }.orEmpty()} in $timeoutMs ms " +
                        "(composed: ${exists(present)}${absent?.let { ", $it composed: ${exists(it)}" }.orEmpty()}; " +
                        "${seen.size} ids): ${readingOrder("await-tree-timeout", fresh = true)}",
                )
            }
            SystemClock.sleep(TREE_POLL_MILLIS)
        }
    }

    /**
     * Wait for, then activate, the first node with [tag] (semantics click: no touch slop).
     *
     * @param tag Test tag.
     */
    fun tap(tag: String) {
        waitForTag(tag)
        rule.onAllNodesWithTag(tag, useUnmergedTree = true)[0].performSemanticsAction(SemanticsActions.OnClick)
        rule.waitForIdle()
    }

    /**
     * Scroll a lazy list until a node is composed.
     *
     * @param list List test tag.
     * @param tag Target test tag.
     */
    fun scrollTo(list: String, tag: String) {
        waitForTag(list)
        rule.onNodeWithTag(list).performScrollToNode(hasTestTag(tag))
        rule.waitForIdle()
    }

    /**
     * Settings: bring the setting [tag] on screen. On list/detail windows (issue #371) it lives
     * in the detail pane, so the chevron row [detailRow] opens it first; on phones (and at large
     * text) the list scrolls to it.
     *
     * @param detailRow The chevron row's test tag (`SettingsDetail.rowTag`).
     * @param tag Target test tag.
     */
    fun openSetting(detailRow: String, tag: String) {
        waitForTag("fst.settings.list")
        if (exists("fst.settings.detail-pane")) {
            scrollTo("fst.settings.list", detailRow)
            tap(detailRow)
            waitForTag(tag)
            rule.onAllNodesWithTag(tag, useUnmergedTree = true)[0].performScrollTo()
            rule.waitForIdle()
        } else {
            scrollTo("fst.settings.list", tag)
        }
    }

    /** Separating vertical hinges in window pixels (empty on phones and flat folds). */
    fun hinges(): List<Rect> = runBlocking {
        val info = withTimeoutOrNull(5_000) { WindowInfoTracker.getOrCreate(rule.activity).windowLayoutInfo(rule.activity).first() }
        info?.displayFeatures.orEmpty().filterIsInstance<FoldingFeature>()
            .filter { it.isSeparating && it.orientation == FoldingFeature.Orientation.VERTICAL }
            .map { Rect(it.bounds.left.toFloat(), it.bounds.top.toFloat(), it.bounds.right.toFloat(), it.bounds.bottom.toFloat()) }
    }

    /**
     * Fail when the run asked for a hinge (instrumentation argument `fstRequireHinge=true`,
     * set by the `android-fold` CI job) and the window has no separating vertical one, so a
     * [HalfOpenFoldJourney] can't pass by skipping its straddle checks. Without the argument
     * (phones, `device.py test` on any AVD) it does nothing.
     */
    fun requireHingeWhenAsked() {
        if (InstrumentationRegistry.getArguments().getString(REQUIRE_HINGE_ARG) != "true") return
        assertTrue("$REQUIRE_HINGE_ARG=true but the window reports no separating vertical hinge", hinges().isNotEmpty())
    }

    /**
     * Assert that no node with any of [tags] crosses a separating hinge.
     *
     * @param tags Test tags.
     */
    fun assertNothingStraddles(vararg tags: String) {
        val folds = hinges()
        tags.forEach { tag ->
            rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().forEach { node ->
                val box = node.boundsInWindow
                folds.forEach { fold -> assertTrue("$tag straddles the fold at ${fold.left}", box.right <= fold.left || box.left >= fold.right) }
            }
        }
    }

    /**
     * The order TalkBack's linear navigation visits the current window's items. Compose
     * publishes its traversal order as `traversalBefore` links between nodes (child order is
     * semantic, not traversal), so the walk collects visible nodes depth-first, then follows
     * each chain of `traversalBefore` links from its head. Kept: nodes TalkBack focuses
     * (screen-reader focusable, clickable, or labelled outside such a node); a focusable
     * node without a content description reads its text, its unfocusable descendants' labels
     * (where Compose puts a merged node's description) and its state, as TalkBack composes it. Logged under
     * [READING_ORDER_TAG] as `<screen> | <index> | <role> | <label> | <w>x<h>`.
     *
     * @param screen Name for the log.
     * @param fresh Drop UiAutomation's node cache first (API 34+), after a change made in place
     *   such as a font-scale switch, which the cache can trail.
     * @return Labels in reading order.
     */
    fun readingOrder(screen: String, fresh: Boolean = false): List<String> = readingStops(screen, fresh).map { it.label }

    /**
     * One stop of [readingStops].
     *
     * @property id The node's test tag (its resource id), or null.
     * @property label What TalkBack speaks (`<unlabelled>` when nothing).
     * @property isHeading Whether TalkBack announces it as a heading.
     * @property isClickable Whether it is a button.
     * @property bounds Its visible bounds on screen in px.
     */
    data class ReadingStop(val id: String?, val label: String, val isHeading: Boolean, val isClickable: Boolean, val bounds: android.graphics.Rect)

    /**
     * [readingOrder] with each stop's test tag, heading/button role and visible bounds, for
     * journeys that assert which tagged nodes TalkBack visits and in what order.
     *
     * @param screen Name for the log.
     * @param fresh As in [readingOrder].
     * @return Stops in reading order.
     */
    fun readingStops(screen: String, fresh: Boolean = false): List<ReadingStop> {
        rule.waitForIdle()
        // A modal opened since publishTalkBackTree has its own, unpublished Compose root.
        if (talkBackTree) {
            forceComposeRoots()
            rule.waitForIdle()
        }
        checkNow()
        // Resolve clipping artifacts while the flagged nodes are still composed.
        accessibilityFindings.forEach { if (it !in clippedFindings && clippedTouchTarget(it)) clippedFindings += it }
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        // After an in-place change (font scale, issue #397) the node cache can keep the old bounds and labels.
        if ((fresh || talkBackTree) && android.os.Build.VERSION.SDK_INT >= 34) automation.clearCache()
        val root = automation.rootInActiveWindow ?: return emptyList()
        val nodes = mutableListOf<AccessibilityNodeInfo>()
        val insideFocusable = mutableListOf<Boolean>()
        fun ownLabel(node: AccessibilityNodeInfo) = listOfNotNull(node.contentDescription, node.text, node.stateDescription)
            .map { it.toString().trim() }.filter { it.isNotEmpty() }.distinct().joinToString(", ")
        fun isFocusable(node: AccessibilityNodeInfo) = node.isScreenReaderFocusable || node.isClickable || node.isLongClickable
        fun collect(node: AccessibilityNodeInfo, inside: Boolean) {
            if (!node.isVisibleToUser) return
            nodes += node
            insideFocusable += inside
            for (i in 0 until node.childCount) node.getChild(i)?.let { collect(it, inside || isFocusable(node)) }
        }
        collect(root, false)
        // Chains from both hints: A.traversalBefore = B means A → B; A.traversalAfter = B means B → A.
        val next = mutableMapOf<Int, Int>()
        nodes.indices.forEach { i ->
            nodes[i].traversalBefore?.let { nodes.indexOf(it) }?.takeIf { it >= 0 }?.let { next.putIfAbsent(i, it) }
            nodes[i].traversalAfter?.let { nodes.indexOf(it) }?.takeIf { it >= 0 }?.let { next.putIfAbsent(it, i) }
        }
        Log.i(READING_ORDER_TAG, "$screen | links ${next.size} of ${nodes.size} nodes")
        lastReadingLinks = next.size
        val targets = next.values.toSet()
        val order = mutableListOf<Int>()
        val seen = BooleanArray(nodes.size)
        nodes.indices.filter { it !in targets }.forEach { head ->
            var current: Int? = head
            while (current != null && !seen[current]) {
                seen[current] = true
                order += current
                current = next[current]
            }
        }
        nodes.indices.filter { !seen[it] }.forEach { order += it }
        fun descendantsLabel(node: AccessibilityNodeInfo): String = buildList {
            for (i in 0 until node.childCount) {
                val child = node.getChild(i) ?: continue
                if (!child.isVisibleToUser || isFocusable(child)) continue
                ownLabel(child).takeIf { it.isNotEmpty() }?.let(::add) ?: descendantsLabel(child).takeIf { it.isNotEmpty() }?.let(::add)
            }
        }.joinToString(", ")
        val stops = mutableListOf<ReadingStop>()
        order.forEach { i ->
            val node = nodes[i]
            val own = ownLabel(node)
            val focusable = isFocusable(node) || (node.isFocusable && own.isNotEmpty())
            if (!focusable && (own.isEmpty() || insideFocusable[i])) return@forEach
            // TalkBack speaks a content description alone; otherwise text, unfocusable children, then state.
            val label = if (!node.contentDescription.isNullOrBlank()) own else listOfNotNull(node.text, descendantsLabel(node), node.stateDescription)
                .map { it.toString().trim() }.filter { it.isNotEmpty() }.distinct().joinToString(", ")
            val role = buildList {
                if (node.isHeading) add("heading")
                if (node.isClickable) add("button")
                if (node.isCheckable) add(if (node.isChecked) "checked" else "unchecked")
                node.className?.toString()?.substringAfterLast('.')?.takeIf { it != "View" && it != "ViewGroup" }?.let(::add)
            }.joinToString(" ")
            val bounds = android.graphics.Rect().also(node::getBoundsInScreen)
            stops += ReadingStop(node.viewIdResourceName, label.ifEmpty { "<unlabelled>" }, node.isHeading, node.isClickable, bounds)
            Log.i(READING_ORDER_TAG, "$screen | ${stops.size} | $role | ${stops.last().label} | ${bounds.width()}x${bounds.height()}")
        }
        return stops
    }

    // region Sheet checks (issues #428, #432)

    /**
     * The node TalkBack reads for [tag] (test tags are exposed as resource ids).
     *
     * @param tag Test tag.
     * @return The visible platform node, or null.
     */
    fun accessibilityNode(tag: String): AccessibilityNodeInfo? {
        fun find(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
            node ?: return null
            if (node.viewIdResourceName == tag && node.isVisibleToUser) return node
            for (i in 0 until node.childCount) find(node.getChild(i))?.let { return it }
            return null
        }
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        // Compose sends UiAutomation no invalidation for a semantics click, so cached nodes keep the old state.
        if (android.os.Build.VERSION.SDK_INT >= 34) automation.clearCache()
        return find(automation.rootInActiveWindow)
    }

    /**
     * Assert a 48 × 48 dp touch target as TalkBack and ATF measure it: the platform node's
     * bounds, which include the 48 dp touch bounds an M3 icon or text button extends around
     * its smaller drawing.
     *
     * @param screen Log name.
     * @param tag Test tag.
     */
    fun assertTouchTarget(screen: String, tag: String) {
        val min = with(rule.density) { 48.dp.toPx() } - 1
        var box = android.graphics.Rect()
        runCatching {
            rule.waitUntil(5_000) {
                box = android.graphics.Rect().also { r -> accessibilityNode(tag)?.getBoundsInScreen(r) }
                box.width() >= min && box.height() >= min
            }
        }
        assertTrue("$screen: $tag is ${box.width()}x${box.height()} px, at least 48 dp", box.width() >= min && box.height() >= min)
    }

    /**
     * Assert what TalkBack gets for a switch row: one checkable stop with the Switch role and
     * its On/Off state, as Compose and the platform tree expose it.
     *
     * @param screen Log name.
     * @param tag Row test tag.
     * @param on Expected state.
     */
    fun assertSwitchStop(screen: String, tag: String, on: Boolean) {
        rule.onNodeWithTag(tag)
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Switch))
            .assert(SemanticsMatcher.keyIsDefined(SemanticsActions.OnClick))
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.ToggleableState, if (on) ToggleableState.On else ToggleableState.Off))
        runCatching { rule.waitUntil(10_000) { accessibilityNode(tag)?.isChecked == on } }
        val node = checkNotNull(accessibilityNode(tag)) { "$screen: $tag in the accessibility tree" }
        assertTrue("$screen: $tag is checkable", node.isCheckable)
        assertEquals("$screen: $tag checked", on, node.isChecked)
        assertEquals("$screen: $tag state", if (on) "On" else "Off", node.stateDescription?.toString())
        // Compose keeps class android.view.View on a row that merges its texts; TalkBack takes
        // "Switch" from the row's switch descendant (#428 walk: "On. New. … Switch").
        fun switchRole(n: AccessibilityNodeInfo): Boolean =
            n.className?.toString()?.endsWith("Switch") == true || AccessibilityNodeInfoCompat.wrap(n).roleDescription?.toString() == "Switch" ||
                (0 until n.childCount).any { i -> n.getChild(i)?.let(::switchRole) == true }
        assertTrue("$screen: $tag exposes the Switch role", switchRole(node))
    }

    /**
     * Assert that [text] inside the node tagged [container] is laid out at [scale] and
     * neither clipped, ellipsized nor outside the container. `hasVisualOverflow` re-lays out
     * at the parent's max width and flags short text, so each line and the paragraph are
     * compared with the laid-out box instead (`.agents/testing/android-accessibility.md`).
     *
     * @param screen Log name.
     * @param container Test tag of the row or header holding the text.
     * @param text Visible text.
     * @param scale Expected font scale.
     */
    fun assertTextUnclipped(screen: String, container: String, text: String, scale: Float) {
        val row = rule.onNodeWithTag(container, useUnmergedTree = true).fetchSemanticsNode().boundsInWindow
        val label = rule.onAllNodes(hasText(text, substring = false) and hasAnyAncestor(hasTestTag(container)), useUnmergedTree = true)[0]
        val box = label.fetchSemanticsNode().boundsInWindow
        assertTrue("$screen: \"$text\" $box inside $container $row", box.left >= row.left - 1 && box.top >= row.top - 1 && box.right <= row.right + 1 && box.bottom <= row.bottom + 1)
        val layouts = mutableListOf<TextLayoutResult>()
        label.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        val layout = layouts.single()
        assertEquals("$screen: \"$text\" laid out at ${scale}x text", scale, layout.layoutInput.density.fontScale, 0.01f)
        val lines = 0 until layout.lineCount
        assertFalse("$screen: \"$text\" is wider than its box", lines.any { layout.getLineRight(it) - layout.getLineLeft(it) > layout.size.width + 1 })
        assertFalse("$screen: \"$text\" is taller than its box", layout.multiParagraph.height > layout.size.height + 1)
        assertFalse("$screen: \"$text\" is ellipsized", lines.any(layout::isLineEllipsized))
    }

    /**
     * Scroll [tag] into view when it sits inside the scrolling [form] and the form overflows
     * (large text, compact height); otherwise it is already on screen.
     *
     * @param form Test tag of the sheet's scrolling form.
     * @param tag Test tag.
     */
    fun reveal(form: String, tag: String) {
        val inForm = rule.onAllNodes(hasTestTag(tag) and hasAnyAncestor(hasTestTag(form))).fetchSemanticsNodes().isNotEmpty()
        val scrolls = rule.onNodeWithTag(form).fetchSemanticsNode().config.contains(SemanticsActions.ScrollBy)
        if (inForm && scrolls) rule.onNodeWithTag(tag).performScrollTo()
        rule.waitForIdle()
    }

    // endregion

    companion object {
        /** Logcat tag of the reading-order dump. */
        const val READING_ORDER_TAG = "FST_A11Y"

        /** Logcat tag of Accessibility Test Framework findings. */
        const val ATF_TAG = "FST_ATF"

        /** Instrumentation argument that makes [requireHingeWhenAsked] demand a separating hinge. */
        const val REQUIRE_HINGE_ARG = "fstRequireHinge"

        /** Pause between [awaitAccessibilityTree] polls, so walking the tree leaves the UI thread room to publish. */
        private const val TREE_POLL_MILLIS = 100L
    }
}

/**
 * Marks a journey whose assertions need a half-open book fold (a separating vertical hinge).
 * The `android-fold` CI job runs only these, on a Pixel 9 Pro Fold emulator with its hinge
 * at 90°, through the runner's `annotation` argument; call [JourneyHarness.requireHingeWhenAsked]
 * once the activity is up. Tag a journey only after it passes `device.py test … --avd
 * FST_Book_Fold --posture half`.
 */
@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.FUNCTION, AnnotationTarget.CLASS)
annotation class HalfOpenFoldJourney

// endregion
