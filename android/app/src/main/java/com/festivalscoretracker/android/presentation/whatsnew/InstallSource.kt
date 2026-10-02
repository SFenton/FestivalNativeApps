package com.festivalscoretracker.android.presentation.whatsnew

import android.content.Context
import android.os.Build

// region Install source

/**
 * The package that installed this app (`com.android.vending` for Google Play).
 *
 * @param context Any context of this app.
 * @return The installing package name, or null when unknown (e.g. `adb install`) or unreadable.
 */
fun installerPackage(context: Context): String? = runCatching {
    val manager = context.packageManager
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        manager.getInstallSourceInfo(context.packageName).installingPackageName
    } else {
        @Suppress("DEPRECATION")
        manager.getInstallerPackageName(context.packageName)
    }
}.getOrNull()

// endregion
