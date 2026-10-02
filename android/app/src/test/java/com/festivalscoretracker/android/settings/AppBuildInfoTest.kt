package com.festivalscoretracker.android.settings

import com.festivalscoretracker.android.BuildConfig
import com.festivalscoretracker.android.core.settings.AppBuildInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AppBuildInfoTest {
    @Test
    fun stampedCommitAppendsItsFirstSevenCharacters() {
        assertEquals("0.1.0 (42) · 42edc57", AppBuildInfo.versionText("0.1.0", 42, "42edc57a1b2c3d4e5f60718293a4b5c6d7e8f901"))
    }

    @Test
    fun missingDevAndEmptyCommitsShowOnlyVersionAndCode() {
        for (sha in listOf(null, "dev", "DEV", "", "  ")) {
            assertEquals("0.1.0 (42)", AppBuildInfo.versionText("0.1.0", 42, sha))
        }
    }

    @Test
    fun nonHexValuesAreIgnored() {
        assertNull(AppBuildInfo.shortCommit("\$FST_GIT_SHA"))
        assertNull(AppBuildInfo.shortCommit("main"))
        assertNull(AppBuildInfo.shortCommit("42edc57g"))
    }

    @Test
    fun shortAndUpperCaseShasAreNormalised() {
        assertEquals("abc12", AppBuildInfo.shortCommit("ABC12"))
        assertEquals("42edc57", AppBuildInfo.shortCommit(" 42EDC57FF\n"))
    }

    @Test
    fun buildConfigTextKeepsTheExistingVersionPrefix() {
        val text = AppBuildInfo.versionText(BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE, BuildConfig.GIT_SHA)
        assertTrue(text.startsWith("${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"))
    }
}
