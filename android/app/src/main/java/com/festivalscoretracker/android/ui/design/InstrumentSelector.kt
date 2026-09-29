package com.festivalscoretracker.android.ui.design

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.foundation.Image
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.songs.InstrumentSelection
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility

// region Instrument selector

/**
 * Port of the web's shared **Instrument Selector** (`components/common/InstrumentSelector.tsx`,
 * operator batch 6, item 6.36): a centred row of 64 dp circle buttons whose selected
 * chart fills with a green circle (scale-in, 300 ms), or — when the row can't fit every
 * button — compact ‹ chart › arrow cycling. Used by the Songs Filter, Paths, the Song
 * Detail score history and (other lanes) Suggestions/Profile.
 *
 * Modes: optional selection (tap the selected chart again to clear) or [required];
 * [hidden] charts are not rendered, [disabled] ones render greyed (28%) and can't be
 * chosen, [muted] ones render greyed (42%) but can; [deferSelection] makes compact
 * arrows move a local preview until the centre button commits it. [content] expands
 * below the row while a chart is selected (web collapsible children).
 *
 * Accessibility: one selectable group; each chart is a radio-style element named by
 * its label ("selected" / "unavailable" states); compact arrows are labelled buttons.
 *
 * @param instruments Charts in order.
 * @param selected Selected chart, or null.
 * @param onSelect New selection (null clears).
 * @param modifier Modifier.
 * @param hidden Charts removed from the rendered selector.
 * @param disabled Charts shown but not selectable.
 * @param muted Charts shown as conflicting but still selectable.
 * @param required The selection can't be cleared.
 * @param compact true = always arrows, false = always the full row, null = auto by width.
 * @param deferSelection Compact arrows preview until committed.
 * @param keyboard Keys artwork for Lead/Pro Lead (song signature).
 * @param previousLabel Compact previous-arrow label.
 * @param nextLabel Compact next-arrow label.
 * @param tag Test tag root (`$tag.<wireId>`, `$tag.previous`, `$tag.next`, `$tag.preview`).
 * @param content Content revealed while a chart is selected.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun InstrumentSelector(
    instruments: List<Instrument>,
    selected: Instrument?,
    onSelect: (Instrument?) -> Unit,
    modifier: Modifier = Modifier,
    hidden: Set<Instrument> = emptySet(),
    disabled: Set<Instrument> = emptySet(),
    muted: Set<Instrument> = emptySet(),
    required: Boolean = false,
    compact: Boolean? = null,
    deferSelection: Boolean = false,
    keyboard: Boolean = false,
    previousLabel: String = "Previous instrument",
    nextLabel: String = "Next instrument",
    tag: String = "fst.instrument-selector",
    content: (@Composable () -> Unit)? = null,
) {
    val available = remember(instruments, hidden) { InstrumentSelection.available(instruments, hidden) }
    val effective = InstrumentSelection.effective(selected, available)
    var previewIndex by rememberSaveable { mutableIntStateOf(0) }
    LaunchedEffect(available.size) { previewIndex = 0 }
    Column(modifier.fillMaxWidth().testTag(tag)) {
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val isCompact = available.isNotEmpty() && (compact ?: InstrumentSelection.needsCompact(maxWidth.value, available.size))
            if (isCompact) {
                val preview = effective ?: available.getOrNull(previewIndex) ?: available.first()
                fun apply(result: InstrumentSelection.Cycle) {
                    when (result) {
                        InstrumentSelection.Cycle.None -> Unit
                        is InstrumentSelection.Cycle.Preview -> previewIndex = result.index
                        is InstrumentSelection.Cycle.Select -> onSelect(result.instrument)
                    }
                }
                Row(
                    horizontalArrangement = Arrangement.spacedBy(InstrumentSelection.GAP_DP.dp, Alignment.CenterHorizontally),
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth().selectableGroup(),
                ) {
                    IconButton(
                        onClick = { apply(InstrumentSelection.cycle(available, effective, previewIndex, -1, deferSelection, disabled)) },
                        modifier = Modifier.testTag("$tag.previous"),
                    ) { Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = previousLabel, tint = BrandTokens.textPrimary) }
                    SelectorButton(
                        instrument = preview,
                        isSelected = effective != null,
                        isDisabled = preview in disabled,
                        isMuted = effective == null && preview in muted,
                        keyboard = keyboard,
                        tag = "$tag.preview",
                        onClick = { apply(InstrumentSelection.compactPress(effective, preview, required)) },
                    )
                    IconButton(
                        onClick = { apply(InstrumentSelection.cycle(available, effective, previewIndex, 1, deferSelection, disabled)) },
                        modifier = Modifier.testTag("$tag.next"),
                    ) { Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = nextLabel, tint = BrandTokens.textPrimary) }
                }
            } else {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(InstrumentSelection.GAP_DP.dp, Alignment.CenterHorizontally),
                    verticalArrangement = Arrangement.spacedBy(InstrumentSelection.GAP_DP.dp),
                    modifier = Modifier.fillMaxWidth().selectableGroup(),
                ) {
                    available.forEach { chart ->
                        val isSelected = chart == effective
                        SelectorButton(
                            instrument = chart,
                            isSelected = isSelected,
                            isDisabled = chart in disabled,
                            isMuted = !isSelected && chart in muted,
                            keyboard = keyboard,
                            tag = "$tag.${chart.wireId}",
                            onClick = { onSelect(InstrumentSelection.press(effective, chart, required)) },
                        )
                    }
                }
            }
        }
        if (content != null) {
            AnimatedVisibility(
                visible = effective != null,
                enter = expandVertically(tween(SELECTOR_ANIMATION_MS)) + fadeIn(tween(SELECTOR_ANIMATION_MS)),
                exit = shrinkVertically(tween(SELECTOR_ANIMATION_MS)) + fadeOut(tween(SELECTOR_ANIMATION_MS)),
            ) { Column { content() } }
        }
    }
}

/**
 * One 64 dp circle: green fill scaling in when selected (drawn, so the scale never
 * relayouts), the 48 dp chart icon, greyscale for disabled/muted.
 */
@Composable
private fun SelectorButton(
    instrument: Instrument,
    isSelected: Boolean,
    isDisabled: Boolean,
    isMuted: Boolean,
    keyboard: Boolean,
    tag: String,
    onClick: () -> Unit,
) {
    val still = LocalFestivalAccessibility.current.reduceMotion
    val fill by animateFloatAsState(if (isSelected) 1f else 0f, if (still) tween(0) else tween(SELECTOR_ANIMATION_MS), label = "selectorFill")
    val side: Dp = InstrumentSelection.BUTTON_DP.dp
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(side)
            .clip(CircleShape)
            .drawBehind { if (fill > 0f) drawCircle(BrandTokens.statusGreen, radius = size.minDimension / 2 * fill) }
            .selectable(selected = isSelected, enabled = !isDisabled, role = Role.RadioButton, onClick = onClick)
            .semantics {
                contentDescription = instrument.label
                if (isDisabled) stateDescription = "Unavailable" else if (isMuted) stateDescription = "Conflicts with another choice"
            }
            .testTag(tag),
    ) {
        Image(
            painter = painterResource(instrumentIconRes(instrument, keyboard)),
            contentDescription = null,
            colorFilter = if (isDisabled || isMuted) GREYSCALE else null,
            modifier = Modifier
                .size(ICON_SIZE)
                .graphicsLayer { alpha = if (isDisabled) DISABLED_ALPHA else if (isMuted) MUTED_ALPHA else 1f },
        )
    }
}

/** Web `TRANSITION_MS`. */
private const val SELECTOR_ANIMATION_MS = 300

/** Web `Size.iconInstrument` (`InstrumentSize.md`). */
private val ICON_SIZE = 48.dp

/** Web disabled opacity. */
private const val DISABLED_ALPHA = 0.28f

/** Web muted (conflict) opacity. */
private const val MUTED_ALPHA = 0.42f

private val GREYSCALE = ColorFilter.colorMatrix(ColorMatrix().apply { setToSaturation(0f) })

// endregion
