package com.festivalscoretracker.android.journeys

import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.platform.ViewRootForTest
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.ComposeAccessibilityValidator
import androidx.compose.ui.test.ComposeTimeoutException
import androidx.compose.ui.test.DeviceConfigurationOverride
import androidx.compose.ui.test.FontScale
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.unit.dp
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.emptyPreferences
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
     *   it in place (backed by snapshot state); `null` keeps the device's own.
     */
    fun launch(
        debug: DebugLaunch,
        transport: FakeTransport,
        preferences: DataStore<Preferences> = MemoryPreferences(),
        fontScale: (() -> Float)? = null,
    ) {
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = preferences)
        rule.setContent {
            if (fontScale == null) {
                FestivalApp(container, debug)
            } else {
                DeviceConfigurationOverride(DeviceConfigurationOverride.FontScale(fontScale())) { FestivalApp(container, debug) }
            }
        }
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
     */
    fun publishTalkBackTree() {
        InstrumentationRegistry.getInstrumentation().uiAutomation
        val manager = rule.activity.getSystemService(android.view.accessibility.AccessibilityManager::class.java)
        rule.waitUntil(10_000) { manager.isEnabled }
        rule.waitForIdle()
        rule.runOnUiThread {
            fun roots(view: android.view.View): List<ViewRootForTest> = when {
                view is ViewRootForTest -> listOf(view)
                view is android.view.ViewGroup -> (0 until view.childCount).flatMap { roots(view.getChildAt(it)) }
                else -> emptyList()
            }
            val found = roots(rule.activity.window.decorView)
            assertTrue("no Compose view to publish", found.isNotEmpty())
            found.forEach { it.forceAccessibilityForTesting(true) }
        }
        talkBackTree = true
        rule.waitForIdle()
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
                        val line = "$type | ${result.sourceCheckClass.simpleName} | $element | ${result.getMessage(Locale.US)}"
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

    /** Checks the current window when accessibility checks are on. */
    private var checkNow: () -> Unit = {}

    /** Tags whose missing-label finding proved to be a clipped label (resolved while composed). */
    private val labelledTags = mutableSetOf<String>()

    /** Fail with every ATF error collected during the journey (warnings only log). */
    fun assertAccessible() {
        val errors = accessibilityFindings.filter { finding ->
            finding.startsWith("ERROR") &&
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
     * @param present Test tag (exposed as the node's resource id) that must be in the tree.
     * @param absent Test tag that must have left the tree, or `null`.
     */
    fun awaitAccessibilityTree(present: String, absent: String? = null) {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        fun ids(node: AccessibilityNodeInfo?, into: MutableSet<String> = mutableSetOf()): Set<String> {
            node ?: return into
            node.viewIdResourceName?.let(into::add)
            for (i in 0 until node.childCount) ids(node.getChild(i), into)
            return into
        }
        rule.waitUntil(15_000) {
            val seen = ids(automation.rootInActiveWindow)
            present in seen && (absent == null || absent !in seen)
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
    fun readingOrder(screen: String, fresh: Boolean = false): List<String> {
        rule.waitForIdle()
        checkNow()
        // Resolve clipping artifacts while the flagged nodes are still composed.
        accessibilityFindings.forEach { clippedTouchTarget(it) }
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
        val labels = mutableListOf<String>()
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
            labels += label.ifEmpty { "<unlabelled>" }
            Log.i(READING_ORDER_TAG, "$screen | ${labels.size} | $role | ${labels.last()} | ${bounds.width()}x${bounds.height()}")
        }
        return labels
    }

    companion object {
        /** Logcat tag of the reading-order dump. */
        const val READING_ORDER_TAG = "FST_A11Y"

        /** Logcat tag of Accessibility Test Framework findings. */
        const val ATF_TAG = "FST_ATF"
    }
}

// endregion
