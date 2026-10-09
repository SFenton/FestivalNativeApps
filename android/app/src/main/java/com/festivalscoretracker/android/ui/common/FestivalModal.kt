package com.festivalscoretracker.android.ui.common

import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionOnScreen
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.LocalViewConfiguration
import androidx.compose.ui.platform.ViewConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.festivalscoretracker.android.core.nav.DialogHinge
import com.festivalscoretracker.android.core.nav.HingeSide
import com.festivalscoretracker.android.presentation.ModalCoverage
import com.festivalscoretracker.android.ui.design.popupTestTags
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

// region Backdrop coverage

/**
 * How many Festival modals enclose the current content: 0 on a page, 1 inside a sheet or
 * dialog, 2 inside an alert over a sheet. Decorative loops compare it with
 * [ModalCoverage.covers] so a page behind a modal holds still while the top modal's own
 * content keeps animating (issue #186).
 */
val LocalModalDepth = compositionLocalOf { 0 }

/**
 * Registers the calling modal with [ModalCoverage] while it is in the composition, so the
 * shared backdrop holds its frame instead of animating unseen behind it (issue #83), and
 * gives [content] (the modal's window) one more [LocalModalDepth].
 *
 * @param coverage Open-modal counter.
 * @param content The modal (its `Dialog`/`ModalBottomSheet` call).
 */
@Composable
internal fun CoversBackdrop(coverage: ModalCoverage = ModalCoverage.shared, content: @Composable () -> Unit) {
    DisposableEffect(coverage) {
        coverage.open()
        onDispose { coverage.close() }
    }
    CompositionLocalProvider(LocalModalDepth provides LocalModalDepth.current + 1, content = content)
}

/**
 * Whether a newer Festival modal covers the calling content (`modal-shell` R10). Continuous
 * decorative motion (marquees, Shop pulses, status pulses) holds a still frame while it does,
 * like the backdrop: the scrim hides it and the frames are wasted work.
 *
 * @param coverage Open-modal counter.
 * @return `true` while a modal opened above this content is on screen.
 */
@Composable
fun coveredByModal(coverage: ModalCoverage = ModalCoverage.shared): Boolean = coverage.covers(LocalModalDepth.current)

/**
 * Test seam for R10 loops whose motion is otherwise unobservable in Robolectric (a pulse's
 * alpha): receives `(loop, value)` each time the loop's drawn value changes, and the still
 * value (1) while it holds. `null` in the app, so production pays nothing.
 */
internal val LocalMotionProbe = staticCompositionLocalOf<((String, Float) -> Unit)?> { null }

/** [LocalMotionProbe] loop names. */
internal object MotionProbes {
    /** The first-run demo highlight pulse. */
    const val FIRST_RUN_DEMO_PULSE = "first-run.demo.pulse"

    /** The retrying service-status icon pulse. */
    const val SERVICE_STATUS_PULSE = "service-status.pulse"
}

// endregion

// region Close button

/** TalkBack label of every modal's close button (the icon has no visible text). */
const val MODAL_CLOSE_LABEL = "Close"

/**
 * The one close affordance every Festival modal carries at the top end of its header
 * (issue #23; Apple `FestivalSheetCloseItem`, Windows `FestivalDialog`): Material's
 * standard close icon button (`Icons.Filled.Close`, 48 dp target, no visible text), as
 * in M3 full-screen dialogs and side sheets.
 *
 * @param onClick Closes the modal.
 * @param tag Test tag (existing modals keep theirs).
 * @param modifier Modifier.
 */
@Composable
fun FestivalModalCloseButton(onClick: () -> Unit, tag: String, modifier: Modifier = Modifier) {
    IconButton(onClick = onClick, modifier = modifier.testTag(tag)) {
        Icon(Icons.Filled.Close, contentDescription = MODAL_CLOSE_LABEL, tint = BrandTokens.textPrimary)
    }
}

// endregion

// region Header

/**
 * Shared modal header: a Title Case heading that takes the free width, optional actions,
 * then [FestivalModalCloseButton] at the end.
 *
 * @param title Heading text.
 * @param closeTag Close button test tag.
 * @param onClose Closes the modal.
 * @param modifier Modifier.
 * @param titleTag Optional heading test tag.
 * @param titleStyle Heading style.
 * @param actions Extra header actions placed before Close (e.g. Reset).
 */
@Composable
fun FestivalModalHeader(
    title: String,
    closeTag: String,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
    titleTag: String? = null,
    titleStyle: TextStyle = MaterialTheme.typography.titleLarge,
    actions: @Composable RowScope.() -> Unit = {},
) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = modifier.fillMaxWidth().padding(start = 24.dp, end = 8.dp)) {
        Text(
            title,
            style = titleStyle,
            fontWeight = FontWeight.Bold,
            color = BrandTokens.textPrimary,
            modifier = Modifier
                .weight(1f)
                .semantics { heading() }
                .then(if (titleTag != null) Modifier.testTag(titleTag) else Modifier),
        )
        actions()
        FestivalModalCloseButton(onClose, closeTag)
    }
}

// endregion

// region Body

/**
 * The modal body below [FestivalModalHeader] (modal-shell R5): no body node's touch or
 * TalkBack bounds reach above its top edge, so a row or field scrolled under the header never
 * takes part of Submit, Reset or Close.
 *
 * Compose 1.9 lets a node clipped by its scroll viewport keep touch bounds up to half the
 * minimum touch target (24 dp) past that edge, and TalkBack gives an overlap to the node later
 * in the tree, the body: a feedback field scrolled under the header cut Submit's TalkBack
 * target to 47 dp at 200% text (issue #422; fixed in Compose after BOM 2025.10.01). This
 * column is a clipping layer whose own view configuration has no minimum touch target, so
 * those bounds stop exactly at its edge (a layer clip extends by the clipping node's
 * `minimumTouchTargetSize`); [content] gets the original [ViewConfiguration] back, so body
 * controls keep their 48 dp touch targets. The header keeps its place in the tree, so reading
 * order is unchanged. The sheet and dialog surfaces already clip the sides and bottom, so only the
 * top edge is new to drawing.
 *
 * @param modifier Column modifier.
 * @param content Body below the header.
 */
@Composable
fun FestivalModalBody(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val configuration = LocalViewConfiguration.current
    val exactEdge = remember(configuration) {
        object : ViewConfiguration by configuration {
            override val minimumTouchTargetSize: DpSize get() = DpSize.Zero
        }
    }
    CompositionLocalProvider(LocalViewConfiguration provides exactEdge) {
        Column(modifier.fillMaxWidth().clipToBounds()) {
            CompositionLocalProvider(LocalViewConfiguration provides configuration) { content() }
        }
    }
}

// endregion

// region Sheet

/**
 * Shared modal bottom sheet: Material's `ModalBottomSheet` on the card colour, kept below
 * the status bar ([festivalSheetTop]) and on one side of a separating hinge
 * ([festivalSheetHingeSide]), titled for TalkBack (`paneTitle`) and headed by
 * [FestivalModalHeader]. Material's drag handle keeps a 48 dp touch target. The close button
 * slides the sheet away (instantly under Reduce
 * Motion) before [onDismissRequest]; swipe down, a scrim tap and back call it directly.
 *
 * @param title Header and pane title.
 * @param closeTag Close button test tag.
 * @param onDismissRequest Called once the sheet is closed in any way.
 * @param modifier Sheet modifier (test tags, extra semantics).
 * @param titleTag Optional heading test tag.
 * @param skipPartiallyExpanded Open fully expanded (default) or allow the half-height stop.
 * @param headerActions Extra header actions placed before Close.
 * @param content Sheet body below the header.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FestivalModalSheet(
    title: String,
    closeTag: String,
    onDismissRequest: () -> Unit,
    modifier: Modifier = Modifier,
    titleTag: String? = null,
    skipPartiallyExpanded: Boolean = true,
    headerActions: @Composable RowScope.() -> Unit = {},
    content: @Composable ColumnScope.() -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = skipPartiallyExpanded)
    val scope = rememberCoroutineScope()
    val reduceMotion = LocalFestivalAccessibility.current.reduceMotion
    val close: () -> Unit = {
        if (reduceMotion) {
            onDismissRequest()
        } else {
            scope.launch { sheetState.hide() }.invokeOnCompletion { onDismissRequest() }
        }
    }
    // The sheet's own fade window (load-transition R5): its first-load fades rush when it scrolls.
    val fadeIn = rememberPageFadeInWindow()
    CoversBackdrop {
        ModalBottomSheet(
            onDismissRequest = onDismissRequest,
            sheetState = sheetState,
            containerColor = BrandTokens.cardBackground,
            modifier = Modifier.festivalSheetTop().festivalSheetHingeSide().popupTestTags().then(modifier).semantics { paneTitle = title }
                .fadeInRushOnScroll(fadeIn),
            // Material's handle is 32 dp wide; once the sheet can collapse it is a 48 dp touch target.
            dragHandle = { BottomSheetDefaults.DragHandle(Modifier.minimumInteractiveComponentSize()) },
        ) {
            FestivalModalHeader(title, closeTag, close, titleTag = titleTag, actions = headerActions)
            FestivalModalBody { CompositionLocalProvider(LocalFadeInWindow provides fadeIn) { content() } }
        }
    }
}

// endregion

// region Dialog

/** Widest a Festival modal dialog grows. */
val MODAL_DIALOG_MAX_WIDTH: Dp = 560.dp

/**
 * Shared modal dialog for wider windows and the first-run guide: an M3 dialog surface
 * (28 dp corners, card colour) headed by [FestivalModalHeader]. An outside tap, back and
 * Close all call [onDismissRequest].
 *
 * The surface always takes the window width less 16 dp margins, capped at
 * [MODAL_DIALOG_MAX_WIDTH] (M3 "Centered dialog (max 560dp wide)"), never the platform's
 * preferred dialog width, which measured about 320 dp on a landscape phone (issues #139, #183).
 *
 * @param title Header and pane title.
 * @param closeTag Close button test tag.
 * @param onDismissRequest Called when the dialog is closed in any way.
 * @param modifier Surface modifier (test tags).
 * @param titleTag Optional heading test tag.
 * @param paneTitle TalkBack pane title (defaults to [title]).
 * @param maxHeight Height cap ([Dp.Unspecified] for none).
 * @param titleStyle Header title style.
 * @param avoidHinge Keep the dialog on one side of a separating fold or hinge
 *   ([DialogHinge]) instead of centring it across the hinge (default; M3: never place
 *   interactive content across the hinge, issue #146).
 * @param content Dialog body below the header.
 */
@Composable
fun FestivalModalDialog(
    title: String,
    closeTag: String,
    onDismissRequest: () -> Unit,
    modifier: Modifier = Modifier,
    titleTag: String? = null,
    paneTitle: String = title,
    maxHeight: Dp = Dp.Unspecified,
    titleStyle: TextStyle = MaterialTheme.typography.titleLarge,
    avoidHinge: Boolean = true,
    content: @Composable ColumnScope.() -> Unit,
) {
    val hingeArea = if (avoidHinge) dialogHingeArea() else null
    // The dialog's own fade window (load-transition R5): its first-load fades rush when it scrolls.
    val fadeIn = rememberPageFadeInWindow()
    val surface: @Composable (Modifier) -> Unit = { placement ->
        Surface(
            shape = RoundedCornerShape(28.dp),
            color = BrandTokens.cardBackground,
            modifier = Modifier
                .padding(16.dp)
                .widthIn(max = MODAL_DIALOG_MAX_WIDTH)
                .heightIn(max = maxHeight)
                .fillMaxWidth()
                .then(placement)
                .popupTestTags()
                .then(modifier)
                .semantics { this.paneTitle = paneTitle }
                .fadeInRushOnScroll(fadeIn),
        ) {
            Column(Modifier.padding(top = 12.dp)) {
                FestivalModalHeader(title, closeTag, onDismissRequest, titleTag = titleTag, titleStyle = titleStyle)
                FestivalModalBody { CompositionLocalProvider(LocalFadeInWindow provides fadeIn) { content() } }
            }
        }
    }
    // A display-size (density) change, such as moving between a phone and a tablet or desktop
    // display, removes the dialog's window while the composition still holds it, leaving an
    // invisible modal (issue #139); a fresh window per density keeps it on screen.
    key(LocalConfiguration.current.densityDpi) {
        CoversBackdrop {
            if (hingeArea == null) {
                Dialog(onDismissRequest = onDismissRequest, properties = DialogProperties(usePlatformDefaultWidth = false)) {
                    surface(Modifier)
                }
            } else {
                Dialog(
                    onDismissRequest = onDismissRequest,
                    properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
                ) {
                    HingeSideDialogLayout(hingeArea, onDismissRequest, surface)
                }
            }
        }
    }
}

/**
 * The area beside a separating hinge to centre a dialog in, in screen pixels; read from the
 * activity window (outside the dialog), or null without a separating hinge.
 *
 * @return The [DialogHinge] area, or null.
 */
@Composable
internal fun dialogHingeArea(): HingeSide.Rect? {
    val posture = shellPosture()
    val hinge = posture.hingeList.firstOrNull { it.isSeparating } ?: return null
    val root = LocalView.current.rootView
    val density = LocalDensity.current
    val direction = LocalLayoutDirection.current
    val origin = IntArray(2).also(root::getLocationOnScreen)
    val x = origin[0].toFloat()
    val y = origin[1].toFloat()
    val safe = WindowInsets.safeDrawing
    val safeArea = HingeSide.Rect(
        left = x + safe.getLeft(density, direction),
        top = y + safe.getTop(density),
        right = x + root.width - safe.getRight(density, direction),
        bottom = y + root.height - safe.getBottom(density),
    )
    val bounds = hinge.bounds
    return DialogHinge.area(
        safe = safeArea,
        hinge = HingeSide.Rect(x + bounds.left, y + bounds.top, x + bounds.right, y + bounds.bottom),
        vertical = hinge.isVertical,
        separating = true,
        rtl = direction == LayoutDirection.Rtl,
    )
}

/**
 * Full-window dialog content that centres [surface] in [area] (screen pixels) and treats a tap
 * anywhere outside the surface as an outside tap, like an ordinary dialog's scrim.
 *
 * @param area Area beside the hinge.
 * @param onDismissRequest Called for a tap outside the surface.
 * @param surface The dialog surface; apply the given modifier after its outer margin.
 */
@Composable
internal fun HingeSideDialogLayout(
    area: HingeSide.Rect,
    onDismissRequest: () -> Unit,
    surface: @Composable (Modifier) -> Unit,
) {
    var origin by remember { mutableStateOf(Offset.Zero) }
    var surfaceBounds by remember { mutableStateOf(Rect.Zero) }
    Layout(
        content = { surface(Modifier.onGloballyPositioned { surfaceBounds = it.boundsInRoot() }) },
        modifier = Modifier
            .fillMaxSize()
            .onGloballyPositioned { origin = it.positionOnScreen() }
            .pointerInput(onDismissRequest) {
                detectTapGestures { if (!surfaceBounds.contains(it)) onDismissRequest() }
            },
    ) { measurables, constraints ->
        val local = HingeSide.Rect(area.left - origin.x, area.top - origin.y, area.right - origin.x, area.bottom - origin.y)
        val placeable = measurables.single().measure(
            Constraints(
                maxWidth = local.width.roundToInt().coerceIn(0, constraints.maxWidth),
                maxHeight = local.height.roundToInt().coerceIn(0, constraints.maxHeight),
            ),
        )
        layout(constraints.maxWidth, constraints.maxHeight) {
            val (left, top) = DialogHinge.place(local, placeable.width.toFloat(), placeable.height.toFloat())
            placeable.place(left.roundToInt(), top.roundToInt())
        }
    }
}

// endregion

// region Alert

/**
 * Shared confirmation / notice alert: Material's `AlertDialog` on the card colour with a
 * text confirm button and a text dismiss button (the platform's standard way to close an
 * alert, together with back and an outside tap).
 *
 * @param title Alert title.
 * @param text Body.
 * @param tag Dialog test tag.
 * @param confirmLabel Confirm button text.
 * @param confirmTag Confirm button test tag.
 * @param onConfirm Confirm action (callers close the alert).
 * @param dismissLabel Dismiss button text.
 * @param dismissTag Dismiss button test tag.
 * @param onDismissRequest Back, an outside tap, or (by default) the dismiss button.
 * @param onDismissButton Dismiss button action when it differs from [onDismissRequest].
 * @param textTag Optional body test tag.
 * @param destructive Confirm in the error colour (e.g. Reset).
 */
@Composable
fun FestivalAlertDialog(
    title: String,
    text: String,
    tag: String,
    confirmLabel: String,
    confirmTag: String,
    onConfirm: () -> Unit,
    dismissLabel: String,
    dismissTag: String,
    onDismissRequest: () -> Unit,
    onDismissButton: () -> Unit = onDismissRequest,
    textTag: String? = null,
    destructive: Boolean = false,
) {
    CoversBackdrop {
        AlertDialog(
            onDismissRequest = onDismissRequest,
            title = { Text(title) },
            text = { Text(text, modifier = if (textTag != null) Modifier.testTag(textTag) else Modifier) },
            confirmButton = {
                TextButton(
                    onClick = onConfirm,
                    colors = if (destructive) ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error) else ButtonDefaults.textButtonColors(),
                    modifier = Modifier.testTag(confirmTag),
                ) { Text(confirmLabel) }
            },
            dismissButton = { TextButton(onClick = onDismissButton, modifier = Modifier.testTag(dismissTag)) { Text(dismissLabel) } },
            containerColor = BrandTokens.cardBackground,
            modifier = Modifier.popupTestTags().testTag(tag),
        )
    }
}

// endregion
