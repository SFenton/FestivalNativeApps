package com.festivalscoretracker.android.core.settings

/**
 * Formats the app's own build identity for Settings → App Version, so a bug report names the
 * exact build: `0.2.0 (1) · 42edc57` (iOS `AppBuildInfo.swift` parity).
 *
 * Release builds stamp the git commit into `BuildConfig.GIT_SHA` with `-PfstGitSha=<sha>` or the
 * `FST_GIT_SHA` environment variable (`android/app/build.gradle.kts`); local builds keep the
 * `dev` default and show no commit.
 */
object AppBuildInfo {
    // region Constants

    /** Number of SHA characters shown (git's conventional short SHA). */
    const val SHORT_SHA_LENGTH = 7

    /** Separator between the version/build and the short commit. */
    const val COMMIT_SEPARATOR = " · "

    // endregion

    // region Formatting

    /**
     * The version name, version code and, for stamped builds, the short commit.
     *
     * @param versionName `BuildConfig.VERSION_NAME`.
     * @param versionCode `BuildConfig.VERSION_CODE`.
     * @param gitSha `BuildConfig.GIT_SHA`, if any.
     * @return `"<name> (<code>)"`, plus `" · <sha7>"` when [gitSha] is a commit.
     */
    fun versionText(versionName: String, versionCode: Int, gitSha: String?): String {
        val base = "$versionName ($versionCode)"
        val sha = shortCommit(gitSha) ?: return base
        return base + COMMIT_SEPARATOR + sha
    }

    /**
     * The first seven characters of a stamped commit SHA.
     *
     * @param raw The stamped value, if present.
     * @return The lower-case short SHA, or null when the value is absent, empty, `dev` or not
     *   hexadecimal (e.g. an unexpanded placeholder).
     */
    fun shortCommit(raw: String?): String? {
        val value = raw?.trim().orEmpty()
        if (value.isEmpty() || value.equals("dev", ignoreCase = true)) return null
        if (!value.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }) return null
        return value.take(SHORT_SHA_LENGTH).lowercase()
    }

    // endregion
}
