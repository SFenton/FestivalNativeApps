package com.festivalscoretracker.android.ui.common

import androidx.compose.material3.adaptive.HingeInfo
import androidx.compose.material3.adaptive.Posture
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

// region Shell posture

/**
 * A page composed inside the shell sees the shell's hinge on its very first composition, as when
 * Back recomposes a destination on a half-open fold (issue #185).
 */
@RunWith(AndroidJUnit4::class)
class ShellPostureTest {
    @get:Rule
    val rule = createComposeRule()

    private val hinge = HingeInfo(Rect(400f, 0f, 420f, 900f), isFlat = false, isVertical = true, isSeparating = true, isOccluding = true)

    @Test
    fun aNewlyComposedPageSeesTheShellHingeOnItsFirstComposition() {
        val posture = Posture(hingeList = listOf(hinge))
        var shown by mutableStateOf(false)
        val firstSeen = mutableListOf<Posture>()
        rule.setContent {
            CompositionLocalProvider(LocalShellPosture provides posture) {
                if (shown) {
                    val seen = shellPosture()
                    if (firstSeen.isEmpty()) firstSeen += seen
                }
            }
        }
        rule.runOnIdle { shown = true }
        rule.waitForIdle()
        assertEquals(listOf(posture), firstSeen)
    }

    @Test
    fun outsideTheShellItReadsTheWindowPosture() {
        lateinit var seen: Posture
        rule.setContent { seen = shellPosture() }
        rule.runOnIdle { assertTrue(seen.hingeList.isEmpty()) }
    }
}

// endregion
