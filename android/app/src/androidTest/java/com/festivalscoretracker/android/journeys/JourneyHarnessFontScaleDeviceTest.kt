package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.testing.FakeTransport
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The journey harness's text-scale override stays inside its own activity (issue #528). A
 * `launch(fontScale = …)` journey scales the activity's shared `Resources` so dialogs and sheets
 * follow it; before the fix that scale outlived the activity, and every later test class in the
 * same `connectedDebugAndroidTest` process ran at 200 % text (Feedback's Submit fell under 48 dp
 * and Quick Links titles broke mid-word). Run with `device.py test
 * com.festivalscoretracker.android.journeys.JourneyHarnessFontScaleDeviceTest --avd …`.
 */
@RunWith(AndroidJUnit4::class)
class JourneyHarnessFontScaleDeviceTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    @Test
    fun fontScaleOverrideEndsWithItsActivity() {
        val deviceScale = rule.activity.resources.configuration.fontScale
        val scale = if (deviceScale == LARGE_TEXT) 1.5f else LARGE_TEXT
        h.launch(DebugLaunch(stillBackground = true), FakeTransport.standard(), fontScale = { scale })
        rule.waitForIdle()
        assertEquals("the override reaches the activity's resources", scale, rule.activity.resources.configuration.fontScale)

        rule.activityRule.scenario.recreate()
        rule.waitForIdle()
        assertEquals(
            "the next activity starts at the device's text scale",
            deviceScale,
            rule.activity.resources.configuration.fontScale,
        )
    }

    private companion object {
        /** 200 % text. */
        const val LARGE_TEXT = 2f
    }
}
