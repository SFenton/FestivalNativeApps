package com.festivalscoretracker.android.core.whatsnew

// region Install channel

/**
 * How this copy of the app was installed, which picks the What's New notes (Apple `AppDistribution`,
 * Windows `InstallChannel`).
 */
enum class InstallChannel {
    /** Installed by Google Play: the store's release notes. */
    Store,

    /** Anything else (sideloads, internal test APKs, emulator builds): the tester notes, like TestFlight. */
    Tester;

    companion object {
        /** Google Play Store's installer package name. */
        const val PLAY_STORE_INSTALLER = "com.android.vending"

        /**
         * Channel from the installing package.
         *
         * @param installer `InstallSourceInfo.installingPackageName` (or the legacy installer name); null when
         *   unknown, e.g. `adb install`.
         * @return [Store] only for Google Play.
         */
        fun fromInstaller(installer: String?): InstallChannel =
            if (installer?.trim() == PLAY_STORE_INSTALLER) Store else Tester

        /**
         * Resolve the channel, honouring the debug-only `FST_DEBUG_DISTRIBUTION=store|tester` override (for
         * screenshots of either view).
         *
         * @param debugOverride Raw extra; ignored outside debug launches and when unrecognised.
         * @param debugBuild Debug or benchmark build ([com.festivalscoretracker.android.BuildConfig.DEBUG_LAUNCH]).
         * @param installer Reads the installing package; only called without an override, and a failure counts
         *   as unknown.
         * @return The channel.
         */
        fun resolve(debugOverride: String?, debugBuild: Boolean, installer: () -> String?): InstallChannel {
            if (debugBuild) {
                when (debugOverride?.trim()?.lowercase()) {
                    "store", "play" -> return Store
                    "tester", "testflight" -> return Tester
                }
            }
            return fromInstaller(runCatching(installer).getOrNull())
        }
    }
}

// endregion
