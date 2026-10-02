package com.festivalscoretracker.android.core.appinfo

/**
 * Formats the app's own build identity for Settings → App Version, so a bug report names the exact
 * build: `2610.01.01 (261001010) · 42edc57` (iPhone parity, `apple/.../AppBuildInfo.swift`, issues #3/#21).
 *
 * Release builds take the version from the `android/v<YYMM.DD.NN>` tag that `version-bump.yml` creates on
 * every app-changing merge to master (`-PfstVersionName/-PfstVersionCode`); every build stamps its git
 * commit as `BuildConfig.GIT_SHA` (`-PfstGitSha`, otherwise `git rev-parse HEAD`, otherwise empty).
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
     * The version name, version code and, when known, the short commit.
     *
     * @param versionName `BuildConfig.VERSION_NAME`; blank shows `—`.
     * @param versionCode `BuildConfig.VERSION_CODE`; null drops the parentheses.
     * @param gitSha `BuildConfig.GIT_SHA`.
     * @return `"<name> (<code>)"`, plus `" · <sha7>"` when [gitSha] is a commit.
     */
    fun versionText(versionName: String?, versionCode: Int?, gitSha: String?): String {
        val name = versionName?.trim().takeUnless { it.isNullOrEmpty() } ?: "—"
        val base = versionCode?.let { "$name ($it)" } ?: name
        val sha = shortCommit(gitSha) ?: return base
        return base + COMMIT_SEPARATOR + sha
    }

    /**
     * The first seven characters of a stamped commit SHA.
     *
     * @param raw The stamped value, if any.
     * @return The lower-case short SHA, or null when [raw] is absent, blank, `dev`, shorter than
     *   [SHORT_SHA_LENGTH] or not hexadecimal.
     */
    fun shortCommit(raw: String?): String? {
        val value = raw?.trim().orEmpty()
        if (value.length < SHORT_SHA_LENGTH) return null
        if (!value.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }) return null
        return value.take(SHORT_SHA_LENGTH).lowercase()
    }

    // endregion
}
