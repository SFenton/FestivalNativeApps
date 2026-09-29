package com.festivalscoretracker.android.ui.settings

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DragIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.festivalscoretracker.android.ui.theme.BrandTokens

// region Reorder list

/**
 * Drag-to-reorder list like the web's `ReorderList` (dnd-kit, `components/sort/ReorderList.tsx`):
 * one bordered block of rows on the subtle surface, each with a ⋮⋮ handle and a semibold label,
 * no numbers or arrow buttons (operator batch 6.11). Long-pressing anywhere on a row (the web's
 * 150 ms touch activation) or dragging its handle lifts the row; it moves one slot each time it
 * passes half a row height, and each step goes through [onMove], so the order persists as the
 * finger moves. TalkBack and Switch Access get "Move up" / "Move down" custom actions instead.
 *
 * @param labels Items in order (unique; they key the rows).
 * @param tag Test-tag prefix (`<tag>.<index>`, `<tag>.<index>.handle`).
 * @param onMove (index, offset) move request.
 */
@Composable
internal fun ReorderList(labels: List<String>, tag: String, onMove: (Int, Int) -> Unit) {
    val drag = remember { ReorderDrag() }
    val latestMove by rememberUpdatedState(onMove)
    val latestCount by rememberUpdatedState(labels.size)
    val haptics = LocalHapticFeedback.current
    val shape = RoundedCornerShape(REORDER_CORNER_DP.dp)
    Column(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .border(BorderStroke(1.dp, BrandTokens.glassBorder), shape)
            .testTag(tag),
    ) {
        labels.forEachIndexed { index, label ->
            key(label) {
                val lifted = drag.label == label
                val onStart: (Offset) -> Unit = {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    drag.start(label, labels.indexOf(label))
                }
                val onDrag: (Float) -> Unit = { dy -> drag.by(dy, latestCount) { from, offset -> latestMove(from, offset) } }
                if (index > 0) HorizontalDivider(color = BrandTokens.glassBorder)
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 48.dp)
                        .onSizeChanged { drag.heights[label] = it.height }
                        .zIndex(if (lifted) 1f else 0f)
                        .graphicsLayer {
                            translationY = if (lifted) drag.offset else 0f
                            shadowElevation = if (lifted) 8.dp.toPx() else 0f
                            alpha = if (lifted) LIFTED_ALPHA else 1f
                        }
                        .background(if (lifted) BrandTokens.surfaceMuted else BrandTokens.surfaceSubtle)
                        .pointerInput(label) {
                            detectDragGesturesAfterLongPress(
                                onDragStart = onStart,
                                onDragEnd = drag::end,
                                onDragCancel = drag::end,
                                onDrag = { change, amount -> change.consume(); onDrag(amount.y) },
                            )
                        }
                        .padding(end = 16.dp)
                        .testTag("$tag.$index")
                        // One TalkBack stop: label and position, with Move up/down actions.
                        .semantics(mergeDescendants = true) {
                            contentDescription = "$label, position ${index + 1} of ${labels.size}"
                            customActions = buildList {
                                if (index > 0) add(CustomAccessibilityAction("Move up") { onMove(index, -1); true })
                                if (index < labels.lastIndex) add(CustomAccessibilityAction("Move down") { onMove(index, 1); true })
                            }
                        },
                ) {
                    Icon(
                        Icons.Filled.DragIndicator,
                        contentDescription = null,
                        tint = BrandTokens.textMuted,
                        modifier = Modifier
                            .size(48.dp)
                            .padding(12.dp)
                            .testTag("$tag.$index.handle")
                            .pointerInput(label) {
                                detectDragGestures(
                                    onDragStart = onStart,
                                    onDragEnd = drag::end,
                                    onDragCancel = drag::end,
                                    onDrag = { change, amount -> change.consume(); onDrag(amount.y) },
                                )
                            },
                    )
                    Text(
                        label,
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.SemiBold,
                        color = BrandTokens.textPrimary,
                        modifier = Modifier.weight(1f).clearAndSetSemantics { },
                    )
                }
            }
        }
    }
}

/** Drag state shared by the rows of one [ReorderList]. */
@Stable
private class ReorderDrag {
    var label by mutableStateOf<String?>(null)
    var index by mutableIntStateOf(-1)
    var offset by mutableFloatStateOf(0f)
    val heights = mutableStateMapOf<String, Int>()

    fun start(label: String, index: Int) {
        this.label = label
        this.index = index
        offset = 0f
    }

    fun end() {
        label = null
        offset = 0f
    }

    /**
     * Follow the finger, stepping the row one slot per half row height passed.
     *
     * @param dy Vertical drag delta in pixels.
     * @param count Rows in the list.
     * @param move Persist one step (from index, ±1).
     */
    fun by(dy: Float, count: Int, move: (Int, Int) -> Unit) {
        val current = label ?: return
        offset += dy
        val half = (heights[current] ?: return) / 2f
        if (offset > half && index < count - 1) {
            move(index, 1)
            index += 1
            offset -= half * 2
        } else if (offset < -half && index > 0) {
            move(index, -1)
            index -= 1
            offset += half * 2
        }
    }
}

/** Corner radius of the bordered block (web `Radius.xs`). */
private const val REORDER_CORNER_DP = 8

/** Opacity of the lifted row (web dnd-kit `opacity: 0.85`). */
private const val LIFTED_ALPHA = 0.85f

// endregion
