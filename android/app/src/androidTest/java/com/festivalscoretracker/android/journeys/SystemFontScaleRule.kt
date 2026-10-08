package com.festivalscoretracker.android.journeys

import android.content.res.Resources
import android.os.ParcelFileDescriptor
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.rules.TestRule
import org.junit.runner.Description
import org.junit.runners.model.Statement

/**
 * Runs the annotated test at a system font scale (Settings › Font size).
 *
 * @property scale Font scale, e.g. 2.0 for Android's 200% text.
 */
@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.FUNCTION)
annotation class SystemFontScale(val scale: Float)

/**
 * Applies a test's [SystemFontScale] to the whole device before the activity launches and
 * restores the previous value afterwards. Order it before the compose rule
 * (`@get:Rule(order = 0)`). Unlike `DeviceConfigurationOverride.FontScale` or a
 * `LocalDensity` override, which only reach the composition they wrap, this also scales
 * bottom sheets, dialogs and popups, which compose in their own windows with the system density
 * (issue #428). Tests without the annotation run at the device's own scale.
 */
class SystemFontScaleRule : TestRule {
    override fun apply(base: Statement, description: Description): Statement {
        val scale = description.getAnnotation(SystemFontScale::class.java)?.scale ?: return base
        return object : Statement() {
            override fun evaluate() {
                val previous = shell("settings get system font_scale").trim()
                try {
                    shell("settings put system font_scale $scale")
                    awaitScale(scale)
                    base.evaluate()
                } finally {
                    shell(if (previous.isEmpty() || previous == "null") "settings delete system font_scale" else "settings put system font_scale $previous")
                    awaitScale(previous.toFloatOrNull() ?: 1f)
                }
            }
        }
    }

    /**
     * Wait (up to 5 s) for the process configuration to report [scale].
     *
     * @param scale Expected font scale.
     */
    private fun awaitScale(scale: Float) {
        val deadline = System.currentTimeMillis() + 5_000
        while (System.currentTimeMillis() < deadline && Resources.getSystem().configuration.fontScale != scale) Thread.sleep(100)
    }

    /**
     * Run a shell command as the shell user and return its output.
     *
     * @param command Command line.
     * @return Standard output.
     */
    private fun shell(command: String): String {
        val fd = InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command)
        return ParcelFileDescriptor.AutoCloseInputStream(fd).bufferedReader().use { it.readText() }
    }
}
