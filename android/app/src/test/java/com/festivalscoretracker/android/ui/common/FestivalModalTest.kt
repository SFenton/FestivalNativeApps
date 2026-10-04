package com.festivalscoretracker.android.ui.common

import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.ext.junit.runners.AndroidJUnit4
import android.os.Looper
import java.time.Duration
import org.robolectric.Shadows.shadowOf
import com.festivalscoretracker.android.presentation.ModalCoverage
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** Issue #23: every Festival modal shares one header whose Close (✕) button dismisses it. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class FestivalModalTest {
    @get:Rule
    val rule = createComposeRule()

    /** Runs the paused Robolectric looper so sheet show/hide animations finish. */
    private fun settle() {
        repeat(4) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100))
            rule.waitForIdle()
        }
    }

    private fun hasDescription(text: String) =
        SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf(text))

    @Test
    fun sheetHeaderShowsTitleAndCloseDismisses() {
        var dismissed = 0
        rule.setContent {
            FestivalTheme {
                FestivalModalSheet(title = "Sort Songs", closeTag = "t.close", onDismissRequest = { dismissed++ }, titleTag = "t.title") {
                    Text("Body")
                }
            }
        }
        settle()
        rule.onNodeWithTag("t.title", useUnmergedTree = true).assertIsDisplayed()
        rule.onNodeWithText("Body").assertIsDisplayed()
        rule.onNodeWithTag("t.close").assertHasClickAction().assert(hasDescription(MODAL_CLOSE_LABEL)).performSemanticsAction(SemanticsActions.OnClick)
        rule.waitUntil(5_000) { settle(); dismissed == 1 }
        assertEquals(1, dismissed)
    }

    @Test
    fun sheetHeaderActionsSitBeforeClose() {
        var reset = 0
        rule.setContent {
            FestivalTheme {
                FestivalModalSheet(
                    title = "Sort Scores",
                    closeTag = "t.close",
                    onDismissRequest = {},
                    headerActions = { TextButton(onClick = { reset++ }) { Text("Reset") } },
                ) { Text("Body") }
            }
        }
        settle()
        rule.onNodeWithText("Reset").performSemanticsAction(SemanticsActions.OnClick)
        assertEquals(1, reset)
        rule.onNodeWithTag("t.close").assertIsDisplayed()
    }

    @Test
    fun dialogHeaderCloseDismisses() {
        var dismissed = 0
        rule.setContent {
            FestivalTheme {
                FestivalModalDialog(title = "What's New", closeTag = "d.close", onDismissRequest = { dismissed++ }, titleTag = "d.title") {
                    Text("Notes")
                }
            }
        }
        rule.onNodeWithTag("d.title", useUnmergedTree = true).assertIsDisplayed()
        rule.onNodeWithTag("d.close").assert(hasDescription(MODAL_CLOSE_LABEL)).performSemanticsAction(SemanticsActions.OnClick)
        assertEquals(1, dismissed)
    }

    @Test
    fun compactDialogCloseDismisses() {
        var dismissed = 0
        rule.setContent {
            FestivalTheme {
                FestivalModalDialog(title = "Songs", closeTag = "c.close", onDismissRequest = { dismissed++ }, compact = true, paneTitle = "Feature tour: Songs") {
                    Text("Slide")
                }
            }
        }
        rule.onNodeWithTag("c.close").performSemanticsAction(SemanticsActions.OnClick)
        assertEquals(1, dismissed)
    }

    @Test
    fun alertRoutesConfirmAndDismissButtons() {
        var confirmed = 0
        var dismissed = 0
        var dismissButton = 0
        rule.setContent {
            FestivalTheme {
                FestivalAlertDialog(
                    title = "Reset Settings",
                    text = "Restore defaults?",
                    tag = "a",
                    textTag = "a.message",
                    confirmLabel = "Reset",
                    confirmTag = "a.ok",
                    onConfirm = { confirmed++ },
                    dismissLabel = "Don't Show Again",
                    dismissTag = "a.never",
                    onDismissRequest = { dismissed++ },
                    onDismissButton = { dismissButton++ },
                    destructive = true,
                )
            }
        }
        rule.onNodeWithTag("a.message", useUnmergedTree = true).assertIsDisplayed()
        rule.onNodeWithTag("a.ok").performSemanticsAction(SemanticsActions.OnClick)
        rule.onNodeWithTag("a.never").performSemanticsAction(SemanticsActions.OnClick)
        assertEquals(listOf(1, 0, 1), listOf(confirmed, dismissed, dismissButton))
    }

    @Test
    fun alertDismissButtonDefaultsToDismissRequest() {
        var dismissed = 0
        rule.setContent {
            FestivalTheme {
                FestivalAlertDialog(
                    title = "Remove", text = "Sure?", tag = "b", confirmLabel = "OK", confirmTag = "b.ok", onConfirm = {},
                    dismissLabel = "Cancel", dismissTag = "b.cancel", onDismissRequest = { dismissed++ },
                )
            }
        }
        rule.onNodeWithTag("b.cancel").performSemanticsAction(SemanticsActions.OnClick)
        assertEquals(1, dismissed)
    }

    /** Issue #83: every open modal covers the backdrop so it holds its frame instead of animating unseen. */
    @Test
    fun openModalsCoverTheBackdropUntilTheyLeave() {
        val coverage = ModalCoverage.shared
        val before = coverage.openCount.value
        var sheet by mutableStateOf(true)
        var dialog by mutableStateOf(true)
        var alert by mutableStateOf(true)
        rule.setContent {
            FestivalTheme {
                if (sheet) FestivalModalSheet(title = "Sort", closeTag = "s.close", onDismissRequest = {}) { Text("Sheet") }
                if (dialog) FestivalModalDialog(title = "Tour", closeTag = "d.close", onDismissRequest = {}) { Text("Dialog") }
                if (alert) {
                    FestivalAlertDialog(
                        title = "Reset", text = "Sure?", tag = "r", confirmLabel = "OK", confirmTag = "r.ok", onConfirm = {},
                        dismissLabel = "Cancel", dismissTag = "r.cancel", onDismissRequest = {},
                    )
                }
            }
        }
        settle()
        assertEquals(before + 3, coverage.openCount.value)
        sheet = false
        settle()
        assertEquals(before + 2, coverage.openCount.value)
        dialog = false
        alert = false
        settle()
        assertEquals(before, coverage.openCount.value)
    }
}
