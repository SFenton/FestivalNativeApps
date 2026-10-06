package com.festivalscoretracker.android.shell

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.view.accessibility.AccessibilityWindowInfo
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.MainActivity
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

/**
 * App naming on a real device (issues #79, #182):
 * `device.py test com.festivalscoretracker.android.shell.AppNameDeviceTest --avd …`.
 * Launchers label the icon "FST", while the app label and the window title that TalkBack
 * announces on open keep "Festival Score Tracker". The origin is a closed loopback port,
 * so no request leaves the device.
 */
@RunWith(AndroidJUnit4::class)
class AppNameDeviceTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()

    // region Tests

    /** The launcher entry is short; App info keeps the full name. */
    @Test
    fun launcherLabelIsShortAndAppLabelIsFull() {
        val pm = context.packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER).setPackage(context.packageName)
        assertEquals("FST", pm.queryIntentActivities(launcher, 0).single().loadLabel(pm).toString())
        assertEquals(FULL_NAME, context.applicationInfo.loadLabel(pm).toString())
    }

    /** The accessibility window title TalkBack announces on open is the full name. */
    @Test
    fun talkBackWindowTitleIsTheFullName() {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        automation.serviceInfo = automation.serviceInfo.apply {
            flags = flags or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        }
        val intent = Intent(context, MainActivity::class.java)
            .putExtra("FST_ORIGIN", "http://127.0.0.1:9")
            .putExtra("FST_DEBUG_STILL_BACKGROUND", "1")
        ActivityScenario.launch<MainActivity>(intent).use { scenario ->
            scenario.onActivity { assertEquals(FULL_NAME, it.title.toString()) }
            var title: String? = null
            val deadline = SystemClock.uptimeMillis() + 10_000
            while (SystemClock.uptimeMillis() < deadline) {
                title = automation.windows
                    .firstOrNull { it.type == AccessibilityWindowInfo.TYPE_APPLICATION && it.isActive }
                    ?.title?.toString()
                if (title == FULL_NAME) break
                SystemClock.sleep(200)
            }
            assertEquals(FULL_NAME, title)
        }
    }

    // endregion

    private companion object {
        const val FULL_NAME = "Festival Score Tracker"
    }
}
