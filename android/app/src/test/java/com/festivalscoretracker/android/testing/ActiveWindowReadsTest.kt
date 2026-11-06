package com.festivalscoretracker.android.testing

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Instrumented tests read the active window only through `journeys/ActiveWindow.kt`, which
 * closes another app's ANR dialog over the app (issues #679, #692). A raw
 * `UiAutomation.rootInActiveWindow` read sees that dialog instead and returns an empty tree.
 */
class ActiveWindowReadsTest {
    /** The androidTest sources, from the module directory Gradle runs unit tests in. */
    private val sources = listOf(File("src/androidTest/java"), File("app/src/androidTest/java")).first { it.isDirectory }

    @Test
    fun onlyActiveWindowReadsTheActiveWindowRoot() {
        val kotlin = sources.walkTopDown().filter { it.isFile && it.extension == "kt" }.toList()
        assertTrue("androidTest sources found under ${sources.absolutePath}", kotlin.any { it.name == "JourneyHarness.kt" })
        val raw = kotlin.filter { it.name != "ActiveWindow.kt" && "rootInActiveWindow" in it.readText() }
            .map { it.relativeTo(sources).invariantSeparatorsPath }
        assertEquals("read the active window through ActiveWindow.root()", emptyList<String>(), raw)
    }
}
