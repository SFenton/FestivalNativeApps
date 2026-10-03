package com.festivalscoretracker.android.privacy

import com.festivalscoretracker.android.core.privacy.PrivacyPolicy
import com.festivalscoretracker.android.core.privacy.PrivacyPolicyBlock
import java.io.File
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The bundled Privacy Policy (issue #98): identical to the shared contract, complete, and parsed defensively. */
class PrivacyPolicyTest {
    @Test
    fun bundledAssetIsByteIdenticalToTheSharedContract() {
        val contract = repoFile("contracts/privacy-policy.json")
        val asset = repoFile("android/app/src/main/assets/privacy-policy.json")
        assertArrayEquals("Copy contracts/privacy-policy.json to the Android assets", contract.readBytes(), asset.readBytes())
    }

    @Test
    fun sharedPolicyHasTheIndustryStandardSections() {
        val policy = PrivacyPolicy.parse(repoFile("contracts/privacy-policy.json").readText())
        assertEquals("Privacy Policy", policy.title)
        assertEquals("2026-10-03", policy.effectiveDate)
        assertEquals("Effective October 3, 2026", policy.effectiveDateText)
        assertEquals(
            listOf("overview", "information-collected", "how-used", "public-game-data", "third-parties", "retention", "your-rights", "children", "security", "changes", "contact"),
            policy.sections.map { it.id },
        )
        // Nothing was dropped by validation: every block of the contract is displayable.
        assertTrue(policy.sections.all { section -> section.blocks.isNotEmpty() && section.title.isNotBlank() })
        val thirdParties = policy.sections.single { it.id == "third-parties" }.blocks.flatMap { it.items }
        assertTrue(thirdParties.any { it.startsWith("Epic Games:") })
    }

    @Test
    fun malformedMissingOrNewerSchemaIsAnEmptyTitledPolicy() {
        listOf(null, "", "{", "[]", """{"schema":2,"title":"X","sections":[{"id":"a","title":"A","blocks":[{"kind":"paragraph","text":"t"}]}]}""").forEach { raw ->
            val policy = PrivacyPolicy.parse(raw)
            assertTrue(policy.isEmpty)
            assertEquals(PrivacyPolicy.DEFAULT_TITLE, policy.title)
        }
    }

    @Test
    fun invalidBlocksAndSectionsAreDropped() {
        val policy = PrivacyPolicy.parse(
            """{"schema":1,"title":"  ","extra":true,"sections":[
              {"id":"a","title":"A","blocks":[{"kind":"paragraph","text":" "},{"kind":"video","text":"x"},{"kind":"bullets","items":["one"," ","two"]},{"kind":"paragraph","text":"p","items":["stray"]}]},
              {"id":"b","title":"","blocks":[{"kind":"paragraph","text":"untitled"}]},
              {"id":"c","title":"C","blocks":[{"kind":"bullets","items":[" "]}]}]}""",
        )
        assertEquals(PrivacyPolicy.DEFAULT_TITLE, policy.title)
        assertEquals(listOf("a"), policy.sections.map { it.id })
        assertEquals(
            listOf(PrivacyPolicyBlock("bullets", items = listOf("one", "two")), PrivacyPolicyBlock("paragraph", text = "p")),
            policy.sections.single().blocks,
        )
        assertTrue(policy.sections.single().blocks.first().isBullets)
    }

    @Test
    fun linkRangesFindHttpsLinksWithoutTrailingPunctuation() {
        val text = "Open https://github.com/SFenton/FestivalNativeApps/issues. Or https://a.example, not http://b.example or https://."
        val links = PrivacyPolicy.linkRanges(text).map { text.substring(it) }
        assertEquals(listOf("https://github.com/SFenton/FestivalNativeApps/issues", "https://a.example"), links)
        assertTrue(PrivacyPolicy.linkRanges("No links here.").isEmpty())
    }

    /** Find a repository file by walking up from the Gradle module directory. */
    private fun repoFile(path: String): File {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val candidate = File(dir, path)
            if (candidate.isFile) return candidate
            dir = dir.parentFile
        }
        error("$path not found above ${File("").absolutePath}")
    }
}
