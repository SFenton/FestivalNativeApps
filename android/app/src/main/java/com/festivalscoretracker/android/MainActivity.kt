package com.festivalscoretracker.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.ui.shell.FestivalApp

// region Activity

/** The single activity: edge-to-edge Compose host for the whole app. */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)
        val launch = if (BuildConfig.DEBUG) parseDebugLaunch() else DebugLaunch.NONE
        val container = (application as FestivalApplication).container(launch)
        setContent {
            FestivalApp(container = container, launch = if (savedInstanceState == null) launch else launch.copy(route = null, songQuery = null, opensDrawer = false, opensProfileSheet = false))
        }
    }

    private fun parseDebugLaunch(): DebugLaunch {
        val extras = intent?.extras ?: return DebugLaunch.NONE
        val values = extras.keySet().mapNotNull { key -> extras.getString(key)?.let { key to it } }.toMap()
        return DebugLaunch.parse(values)
    }
}

// endregion
