package com.festivalscoretracker.android.journeys

import android.app.ActivityManager
import android.app.UiAutomation
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.Process
import android.os.SystemClock
import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.platform.app.InstrumentationRegistry

/**
 * The one way an instrumented test reads the active window's accessibility tree. Never read
 * `UiAutomation.rootInActiveWindow` directly: `ActiveWindowReadsTest` (unit) fails the build
 * when an androidTest source does.
 *
 * A freshly booted CI emulator can raise another app's continuous ANR dialog ("Pixel Launcher
 * isn't responding", input dispatching timed out because the launcher had no focused window).
 * As the active window it hides the app from every read (#679, #692). Wait only reschedules a
 * continuous ANR: the dialog returned every ~5 s for a whole android-device run (#692). [root]
 * answers such a dialog with **Close app**, which ends that process (the system restarts its
 * launcher), then reads again until the app's window is back. While the dialog holds focus the
 * active root can also be missing; then [root] reads the focused window from `dumpsys window` and
 * force-stops the not-responding app, as Close app would. The app's own ANR is never answered:
 * it is a real failure.
 *
 * Call from the test thread only (it polls for the dialog to close).
 */
object ActiveWindow {
    /** Logcat tag shared with the reading-order dump. */
    private const val TAG = JourneyHarness.READING_ORDER_TAG

    /** Package of the platform's own windows, including app-not-responding dialogs. */
    private const val SYSTEM_PACKAGE = "android"

    /** The app-not-responding dialog's Wait button (`app_anr_dialog.xml`); only that dialog has it. */
    private const val ANR_WAIT_ID = "android:id/aerr_wait"

    /** The app-not-responding dialog's Close app button (`app_anr_dialog.xml`). */
    private const val ANR_CLOSE_ID = "android:id/aerr_close"

    /** An `AlertDialog`'s title: "<app> isn't responding" on the ANR dialog. */
    private const val ALERT_TITLE_ID = "android:id/alertTitle"

    /** How long [root] waits for a closed ANR dialog to give the active window back. */
    private const val DISMISS_MILLIS = 5_000L

    /** Pause between reads while a closed dialog leaves. */
    private const val POLL_MILLIS = 100L

    /** Minimum time between two `dumpsys window` focus checks while there is no active root. */
    private const val FOCUS_CHECK_MILLIS = 1_000L

    /** The focused-window line of `dumpsys window displays`. */
    private const val FOCUS_LINE = "mCurrentFocus="

    /** The ANR dialog's window title before its package: `Application Not Responding: <package>`. */
    private const val ANR_WINDOW = "Application Not Responding: "

    /** A package name, so nothing else reaches the shell. */
    private val PACKAGE = Regex("[A-Za-z0-9_.]+")

    private var lastFocusCheck = 0L

    private val closed = mutableListOf<String>()

    /** Titles of other apps' "isn't responding" dialogs [root] has closed in this process. */
    val closedDialogs: List<String>
        get() = synchronized(closed) { closed.toList() }

    /**
     * The active window's accessibility root, after closing another app's ANR dialog over it.
     *
     * @return The active window's root, or null when there is none.
     */
    fun root(): AccessibilityNodeInfo? {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        val root = automation.rootInActiveWindow
        val closedTitle = when {
            // A focused ANR dialog can leave no active root at all (#692): check the focus itself.
            root == null -> forceStopFocusedAnr(automation) ?: return null
            !isAnrDialog(root) || ownProcessNotResponding() -> return root
            else -> clickCloseApp(root) ?: return root
        }
        synchronized(closed) { closed += closedTitle }
        val deadline = SystemClock.uptimeMillis() + DISMISS_MILLIS
        var next: AccessibilityNodeInfo? = root
        while (SystemClock.uptimeMillis() < deadline) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) automation.clearCache()
            // Null between the dialog leaving and the app's window becoming active again.
            next = automation.rootInActiveWindow
            if (next != null && !isAnrDialog(next)) return next
            SystemClock.sleep(POLL_MILLIS)
        }
        return next
    }

    /**
     * Press Close app on another app's ANR dialog.
     *
     * @param root The ANR dialog's root.
     * @return The dialog's title, or null when it couldn't be pressed.
     */
    private fun clickCloseApp(root: AccessibilityNodeInfo): String? {
        val close = root.findAccessibilityNodeInfosByViewId(ANR_CLOSE_ID).firstOrNull() ?: return null
        val title = root.findAccessibilityNodeInfosByViewId(ALERT_TITLE_ID).firstOrNull()?.text?.toString() ?: "system ANR dialog"
        if (!close.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return null
        Log.w(TAG, "closed \"$title\" with Close app (#692)")
        return title
    }

    /**
     * With no active root, force-stop another app whose ANR dialog holds window focus, as Close
     * app would. Reads `mCurrentFocus` at most once per [FOCUS_CHECK_MILLIS].
     *
     * @param automation The instrumentation's UiAutomation.
     * @return "<package> isn't responding" when it stopped one, else null.
     */
    private fun forceStopFocusedAnr(automation: UiAutomation): String? {
        val now = SystemClock.uptimeMillis()
        if (now - lastFocusCheck < FOCUS_CHECK_MILLIS) return null
        lastFocusCheck = now
        val focus = shell(automation, "dumpsys window displays").lineSequence().firstOrNull { FOCUS_LINE in it } ?: return null
        val pkg = focus.substringAfter(ANR_WINDOW, "").substringBefore('}').trim()
        val own = InstrumentationRegistry.getInstrumentation().targetContext.packageName
        if (pkg.isEmpty() || pkg == own || !PACKAGE.matches(pkg)) return null
        shell(automation, "am force-stop $pkg")
        Log.w(TAG, "force-stopped $pkg: its \"isn't responding\" dialog held focus with no active window (#692)")
        return "$pkg isn't responding"
    }

    /**
     * Run a shell command as the instrumentation's UiAutomation.
     *
     * @param automation The instrumentation's UiAutomation.
     * @param command The command line.
     * @return Its standard output.
     */
    private fun shell(automation: UiAutomation, command: String): String =
        ParcelFileDescriptor.AutoCloseInputStream(automation.executeShellCommand(command)).bufferedReader().use { it.readText() }

    /**
     * Whether [root] is the platform's app-not-responding dialog.
     *
     * @param root An active window's root.
     * @return True for the ANR dialog.
     */
    private fun isAnrDialog(root: AccessibilityNodeInfo): Boolean =
        root.packageName == SYSTEM_PACKAGE && root.findAccessibilityNodeInfosByViewId(ANR_WAIT_ID).isNotEmpty()

    /**
     * Whether the app under test is itself in the platform's not-responding state, so a system
     * ANR dialog may be about it (a real failure the harness must not answer).
     *
     * @return True when this app's uid has a not-responding process.
     */
    private fun ownProcessNotResponding(): Boolean {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        return context.getSystemService(ActivityManager::class.java)?.processesInErrorState.orEmpty().any {
            it.uid == Process.myUid() && it.condition == ActivityManager.ProcessErrorStateInfo.NOT_RESPONDING
        }
    }
}
