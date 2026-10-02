package com.festivalscoretracker.android.core

import com.festivalscoretracker.android.BuildConfig
import com.festivalscoretracker.android.core.appinfo.AppBuildInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AppBuildInfoTest {
    @Test
    fun releaseVersionShowsCodeAndShortCommit() {
        assertEquals(
            "2610.01.01 (261001010) · 42edc57",
            AppBuildInfo.versionText("2610.01.01", 261001010, "42EDC57a1b2c3d4e5f60718293a4b5c6d7e8f901"),
        )
    }

    @Test
    fun unknownCommitShowsVersionOnly() {
        for (sha in listOf(null, "", "  ", "dev", "DEV", "abc12", "zzzzzzzzz", "\$(FST_GIT_SHA)")) {
            assertEquals("0.2.0 (1)", AppBuildInfo.versionText("0.2.0", 1, sha))
        }
    }

    @Test
    fun missingVersionPartsDegradeReadably() {
        assertEquals("— (1)", AppBuildInfo.versionText(" ", 1, null))
        assertEquals("2610.01.02 · abcdef0", AppBuildInfo.versionText("2610.01.02", null, " abcdef0 "))
    }

    @Test
    fun shortCommitTakesSevenLowerCaseHexCharacters() {
        assertEquals("abcdef0", AppBuildInfo.shortCommit("ABCDEF0123"))
        assertNull(AppBuildInfo.shortCommit("dev"))
    }

    @Test
    fun buildConfigStampsTheCheckedOutCommit() {
        // Gradle stamps `git rev-parse HEAD` (or -PfstGitSha); empty only when git is unavailable.
        val sha = BuildConfig.GIT_SHA
        assertTrue("GIT_SHA=$sha", sha.isEmpty() || AppBuildInfo.shortCommit(sha) != null)
    }
}
