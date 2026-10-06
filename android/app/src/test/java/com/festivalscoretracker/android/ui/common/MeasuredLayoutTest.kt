package com.festivalscoretracker.android.ui.common

import androidx.compose.runtime.MutableFloatState
import androidx.compose.runtime.MutableState
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.isSpecified
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

// region Measured layout

/**
 * Measured layout state survives the destination being saved and restored, as when Back returns
 * to a page (issues #82, #185), so its first frame draws the last column plan and hinge split.
 */
@RunWith(AndroidJUnit4::class)
class MeasuredLayoutTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun measurementsAreRestoredWithTheDestination() {
        val tester = StateRestorationTester(rule)
        lateinit var px: MutableFloatState
        lateinit var bounds: MutableState<Pair<Int, Int>?>
        lateinit var origin: MutableState<Offset>
        tester.setContent {
            px = rememberMeasuredPx(Float.NaN)
            bounds = rememberMeasuredBounds()
            origin = rememberMeasuredOffset(Offset.Unspecified)
        }
        assertTrue(px.floatValue.isNaN())
        assertNull(bounds.value)
        rule.runOnIdle {
            px.floatValue = 812f
            bounds.value = 96 to 1824
            origin.value = Offset(96f, 210f)
        }
        tester.emulateSavedInstanceStateRestore()
        rule.runOnIdle {
            assertEquals(812f, px.floatValue)
            assertEquals(96 to 1824, bounds.value)
            assertEquals(Offset(96f, 210f), origin.value)
        }
    }

    @Test
    fun unmeasuredStateRestoresAsUnmeasured() {
        val tester = StateRestorationTester(rule)
        lateinit var bounds: MutableState<Pair<Int, Int>?>
        lateinit var origin: MutableState<Offset>
        tester.setContent {
            bounds = rememberMeasuredBounds()
            origin = rememberMeasuredOffset(Offset.Unspecified)
        }
        tester.emulateSavedInstanceStateRestore()
        rule.runOnIdle {
            assertNull(bounds.value)
            assertFalse(origin.value.isSpecified)
        }
    }
}

// endregion
