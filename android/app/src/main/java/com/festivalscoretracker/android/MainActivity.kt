package com.festivalscoretracker.android

import android.os.Bundle
import android.view.KeyEvent
import android.view.KeyboardShortcutGroup
import android.view.KeyboardShortcutInfo
import android.view.Menu
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.search.ShellShortcuts
import com.festivalscoretracker.android.ui.shell.FestivalApp
import com.festivalscoretracker.android.ui.shell.ShellShortcutBridge

// region Activity

/** The single activity: edge-to-edge Compose host for the whole app. */
class MainActivity : ComponentActivity() {
    private val shortcuts = ShellShortcutBridge()

    override fun onCreate(savedInstanceState: Bundle?) {
        // SplashScreen API: icon on #1A0830 (Theme.Festival.Starting), dismissed on the first frame.
        installSplashScreen()
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)
        val launch = if (BuildConfig.DEBUG) parseDebugLaunch() else DebugLaunch.NONE
        val container = (application as FestivalApplication).container(launch)
        setContent {
            FestivalApp(
                container = container,
                launch = if (savedInstanceState == null) {
                    launch
                } else {
                    launch.copy(route = null, songQuery = null, opensDrawer = false, opensProfileSheet = false, searchQuery = null)
                },
                shortcuts = shortcuts,
            )
        }
    }

    /**
     * App shortcuts before the view hierarchy, so they work with nothing focused:
     * Ctrl+K / Search key → global search, Ctrl+F → page find (global-search android.md).
     */
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
            val shortcut = ShellShortcuts.resolve(event.keyCode, event.isCtrlPressed, event.isAltPressed, event.isShiftPressed, event.isMetaPressed)
            if (shortcut != null && shortcuts.dispatch(shortcut)) return true
        }
        return super.dispatchKeyEvent(event)
    }

    /** List the shortcuts in the system Keyboard Shortcuts Helper (Meta+/). */
    override fun onProvideKeyboardShortcuts(data: MutableList<KeyboardShortcutGroup>, menu: Menu?, deviceId: Int) {
        super.onProvideKeyboardShortcuts(data, menu, deviceId)
        data += KeyboardShortcutGroup(
            "Festival Score Tracker",
            listOf(
                KeyboardShortcutInfo("Search songs and players", KeyEvent.KEYCODE_K, KeyEvent.META_CTRL_ON),
                KeyboardShortcutInfo("Find in page", KeyEvent.KEYCODE_F, KeyEvent.META_CTRL_ON),
            ),
        )
    }

    private fun parseDebugLaunch(): DebugLaunch {
        val extras = intent?.extras ?: return DebugLaunch.NONE
        val values = extras.keySet().mapNotNull { key -> extras.getString(key)?.let { key to it } }.toMap()
        return DebugLaunch.parse(values)
    }
}

// endregion
