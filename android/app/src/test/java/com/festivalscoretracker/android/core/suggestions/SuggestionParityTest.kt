package com.festivalscoretracker.android.core.suggestions

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import java.io.File
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * Cross-platform parity: runs the Kotlin generator over the shared fixture that the
 * Windows lane built (`tools/windows/suggestion_parity/`) and compares every page of
 * every scenario, the rival index and raw Mulberry32 output with the **unmodified
 * Apple generator's** output (`suggestions-parity.expected.json`, which the C# port
 * also matches). The fixture is read in place so all three ports share one source.
 */
class SuggestionParityTest {
    @Serializable
    private data class FixtureScore(
        val songId: String,
        val instrument: String,
        val score: Int,
        val accuracy: Double? = null,
        val fullCombo: Boolean? = null,
        val stars: Int? = null,
        val season: Int? = null,
        val rank: Int? = null,
        val totalEntries: Int? = null,
    )

    @Serializable
    private data class Scenario(
        val name: String,
        val seed: Long,
        val disableSkipping: Boolean? = null,
        val fixedDisplayCount: Int? = null,
        val currentSeason: Int,
        val rivals: String,
        val pages: List<Int>,
        val resetPages: List<Int>? = null,
        val resetCycles: Int? = null,
    )

    @Serializable
    private data class Fixture(
        val songs: List<Song>,
        val scores: List<FixtureScore>,
        val rivalsAll: RivalsAllResponse,
        val rngSeeds: List<Long>,
        val scenarios: List<Scenario>,
    )

    private val json = Json { ignoreUnknownKeys = true }
    private val fixture: Fixture by lazy { json.decodeFromString(Fixture.serializer(), fixtureFile("suggestions-parity.json").readText()) }
    private val expected: JsonObject by lazy { json.parseToJsonElement(fixtureFile("suggestions-parity.expected.json").readText()).jsonObject }

    private fun scoreIndex(): SuggestionScoreIndex {
        val index = LinkedHashMap<String, MutableMap<Instrument, SuggestionScore>>()
        for (row in fixture.scores) {
            val instrument = requireNotNull(Instrument.fromWireId(row.instrument)) { row.instrument }
            index.getOrPut(row.songId) { LinkedHashMap() }[instrument] =
                SuggestionScore(row.score, row.accuracy, row.fullCombo, row.stars, row.season, row.rank, row.totalEntries)
        }
        return index
    }

    @Test
    fun mulberry32MatchesApple() {
        val actual = buildJsonArray {
            for (seed in fixture.rngSeeds) {
                val rng = SeededSuggestionRng(seed)
                add(
                    buildJsonObject {
                        put("seed", seed)
                        put("doubles", buildJsonArray { repeat(8) { add(JsonPrimitive(rng.nextDouble())) } })
                        put("ints", buildJsonArray { repeat(8) { add(JsonPrimitive(rng.nextInt(97))) } })
                    },
                )
            }
        }
        assertSame(expected.getValue("rng"), actual, "rng")
    }

    @Test
    fun rivalIndexMatchesApple() {
        val index = RivalDataIndex.build(fixture.rivalsAll)
        val actual = buildJsonObject {
            put(
                "songRivals",
                buildJsonArray {
                    index.songRivals.forEach {
                        add(
                            buildJsonObject {
                                put("accountId", it.accountId)
                                put("displayName", it.displayName)
                                put("direction", it.direction)
                            },
                        )
                    }
                },
            )
            put("byRivalCounts", buildJsonObject { index.byRival.forEach { (k, v) -> put(k, v.size) } })
            put("closestCount", index.closestRivalBySong.size)
        }
        assertSame(expected.getValue("rivalIndex"), actual, "rivalIndex")
    }

    /**
     * Every page of every scenario matches the Apple reference. While the shared reference
     * still predates the #656 named-rival fix (it holds a named-rival card listing several
     * rivals; only the Mac toolchain can regenerate it from the fixed Apple sources), each
     * scenario must match strictly up to its first difference, and that difference must be a
     * named-rival card: the fixed selection is the only intended change, and every later
     * category follows from it through the shared seeded RNG and session state. Once the
     * reference is regenerated the comparison is strict again with no code change.
     */
    @Test
    fun everyScenarioMatchesApple() {
        val expectedScenarios = expected.getValue("scenarios").jsonArray.associateBy { it.jsonObject.getValue("name").jsonPrimitive.content }
        assertEquals(fixture.scenarios.size, expectedScenarios.size)
        val pre656 = referencePredatesNamedRivalFix(expectedScenarios.values)
        var pages = 0
        var strictScenarios = 0
        for (scenario in fixture.scenarios) {
            val (pageList, resetList) = run(scenario)
            val actualPages = buildJsonArray { pageList.forEach { add(page(it)) } }
            val actualResets = buildJsonArray { resetList.forEach { add(page(it)) } }
            val want = expectedScenarios.getValue(scenario.name).jsonObject
            pages += actualPages.size + actualResets.size
            if (pre656) {
                val sequence = listOf("pages" to actualPages, "resetPages" to actualResets).flatMap { (label, list) ->
                    list.mapIndexed { i, page -> Triple("${scenario.name}.$label[$i]", want.getValue(label).jsonArray[i].jsonArray, page.jsonArray) }
                }
                val diverged = sequence.firstOrNull { (_, e, a) -> !sameJson(e, a) }
                if (diverged == null) {
                    strictScenarios++
                    continue
                }
                val (path, e, a) = diverged
                val index = (0 until maxOf(e.size, a.size)).first { it >= e.size || it >= a.size || !sameJson(e[it], a[it]) }
                val keys = listOfNotNull(e.getOrNull(index), a.getOrNull(index)).map { it.jsonObject.getValue("key").jsonPrimitive.content }
                assertTrue("$path[$index]: first difference from the pre-#656 reference is $keys, not a named-rival card", keys.any { it in namedRivalKeys })
            } else {
                assertSame(want.getValue("pages"), actualPages, "${scenario.name}.pages")
                assertSame(want.getValue("resetPages"), actualResets, "${scenario.name}.resetPages")
            }
        }
        assertEquals("228 scenario pages + 27 endless-remix pages", 255, pages)
        if (pre656) assertTrue("rival-free scenarios still match the pre-#656 reference exactly", strictScenarios > 0)
    }

    /** True when a reference named-rival card lists more than one rival (Apple output from before #656). */
    private fun referencePredatesNamedRivalFix(scenarios: Collection<JsonElement>): Boolean =
        scenarios.flatMap { s -> listOf("pages", "resetPages").flatMap { s.jsonObject.getValue(it).jsonArray } }
            .flatMap { it.jsonArray }
            .map { it.jsonObject }
            .filter { it.getValue("key").jsonPrimitive.content in namedRivalKeys }
            .any { card -> card.getValue("songs").jsonArray.mapNotNull { it.jsonObject["rivalAccountId"]?.jsonPrimitive?.content }.toSet().size > 1 }

    /**
     * Issue #656: a card whose title names one rival ("Climb Past {name}", "Gain Stars & Beat
     * {name}", "FC These to Beat {name}!") lists only songs against that rival, on every page
     * of every shared scenario. The pre-fix generator titled from the first row and kept every
     * other row's own closest rival.
     */
    @Test
    fun namedRivalCardsListOnlyTheTitlesRival() {
        val titles = mapOf<String, (String) -> String>(
            "song_rival_pct_push" to { "Climb Past $it" },
            "song_rival_star_gains" to { "Gain Stars & Beat $it" },
            "song_rival_near_fc" to { "FC These to Beat $it!" },
        )
        val seen = HashMap<String, Int>()
        for (scenario in fixture.scenarios) {
            val (pageList, resetList) = run(scenario)
            for (category in (pageList + resetList).flatten()) {
                val title = titles[category.key] ?: continue
                val names = category.songs.map { it.rivalName }
                val rival = requireNotNull(names.first()) { "${scenario.name}/${category.key} has no rival" }
                assertEquals("${scenario.name}/${category.key} title", title(rival), category.title)
                assertEquals("${scenario.name}/${category.key} rows", List(names.size) { rival }, names)
                assertEquals("${scenario.name}/${category.key} rival ids", 1, category.songs.mapNotNull { it.rivalAccountId }.toSet().size)
                if (category.key != "song_rival_near_fc") {
                    assertTrue("${scenario.name}/${category.key}: the rival leads every row", category.songs.all { (it.rivalRankDelta ?: 0) < 0 })
                }
                seen[category.key] = (seen[category.key] ?: 0) + 1
            }
        }
        assertEquals("every named family emits in the shared scenarios", namedRivalKeys, seen.keys)
    }

    /** Run one fixture scenario: its pages, then its endless-remix pages. */
    private fun run(scenario: Scenario): Pair<List<List<SuggestionCategory>>, List<List<SuggestionCategory>>> {
        val scores = scoreIndex()
        val rivals = RivalDataIndex.build(fixture.rivalsAll)
        val generator = SuggestionGenerator(
            SuggestionGenerator.Options(
                seed = scenario.seed,
                disableSkipping = scenario.disableSkipping ?: false,
                fixedDisplayCount = scenario.fixedDisplayCount,
                currentSeason = scenario.currentSeason,
            ),
        )
        generator.setSource(fixture.songs, scores)
        if (scenario.rivals == "early") generator.setRivalData(rivals)
        val pages = ArrayList<List<SuggestionCategory>>()
        scenario.pages.forEachIndexed { n, count ->
            pages += generator.getNext(count)
            if (n == 0 && scenario.rivals == "late") generator.setRivalData(rivals)
        }
        val resets = ArrayList<List<SuggestionCategory>>()
        scenario.resetPages?.let { counts ->
            repeat(scenario.resetCycles ?: 1) {
                generator.resetForEndless()
                counts.forEach { resets += generator.getNext(it) }
            }
        }
        return pages to resets
    }

    private fun page(categories: List<SuggestionCategory>): JsonArray = buildJsonArray {
        for (c in categories) {
            add(
                buildJsonObject {
                    put("key", c.key)
                    put("title", c.title)
                    put("description", c.description)
                    put("type", c.type.key)
                    c.instrument?.let { put("instrument", it.wireId) }
                    put("songs", buildJsonArray { c.songs.forEach { add(item(it)) } })
                },
            )
        }
    }

    private fun item(item: SuggestionSongItem): JsonObject = buildJsonObject {
        put("id", item.id)
        item.stars?.let { put("stars", it) }
        item.percent?.let { put("percent", it) }
        item.fullCombo?.let { put("fullCombo", it) }
        item.percentileDisplay?.let { put("percentileDisplay", it) }
        item.rivalName?.let { put("rivalName", it) }
        item.rivalAccountId?.let { put("rivalAccountId", it) }
        item.rivalRankDelta?.let { put("rivalRankDelta", it) }
    }

    /** Deep equality with numbers compared as doubles; fails at the first differing path. */
    private fun assertSame(expected: JsonElement, actual: JsonElement, path: String) {
        when (expected) {
            is JsonObject -> {
                val a = actual as? JsonObject ?: return fail("$path: expected object, got $actual")
                assertEquals("$path keys", expected.keys.sorted(), a.keys.sorted())
                for ((key, value) in expected) assertSame(value, a.getValue(key), "$path.$key")
            }
            is JsonArray -> {
                val a = actual as? JsonArray ?: return fail("$path: expected array, got $actual")
                for (i in 0 until minOf(expected.size, a.size)) assertSame(expected[i], a[i], "$path[$i]")
                assertEquals("$path length", expected.size, a.size)
            }
            JsonNull -> assertEquals(path, JsonNull, actual)
            is JsonPrimitive -> {
                val a = actual as? JsonPrimitive ?: return fail("$path: expected primitive, got $actual")
                if (expected.isString) {
                    assertTrue("$path: $a is not a string", a.isString)
                    assertEquals(path, expected.content, a.content)
                } else if (expected.doubleOrNull != null) {
                    assertEquals(path, expected.doubleOrNull!!, a.doubleOrNull ?: Double.NaN, 0.0)
                } else {
                    assertEquals(path, expected.content, a.content)
                }
            }
        }
    }

    /** Deep equality with the same rules as [assertSame], without failing. */
    private fun sameJson(expected: JsonElement, actual: JsonElement): Boolean = when (expected) {
        is JsonObject -> actual is JsonObject && expected.keys == actual.keys && expected.all { (k, v) -> sameJson(v, actual.getValue(k)) }
        is JsonArray -> actual is JsonArray && expected.size == actual.size && expected.indices.all { sameJson(expected[it], actual[it]) }
        JsonNull -> actual == JsonNull
        is JsonPrimitive -> actual is JsonPrimitive && when {
            expected.isString -> actual.isString && expected.content == actual.content
            expected.doubleOrNull != null -> expected.doubleOrNull == actual.doubleOrNull
            else -> expected.content == actual.content
        }
    }

    private companion object {
        /** Cross-pollination families whose title names one rival (issue #656). */
        val namedRivalKeys = setOf("song_rival_pct_push", "song_rival_star_gains", "song_rival_near_fc")
        /** Find the shared Windows fixture by walking up from the Gradle module directory. */
        fun fixtureFile(name: String): File {
            var dir: File? = File("").absoluteFile
            while (dir != null) {
                val candidate = File(dir, "windows/Festival.Core.Tests/Fixtures/$name")
                if (candidate.isFile) return candidate
                dir = dir.parentFile
            }
            error("Shared Suggestions parity fixture $name not found above ${File("").absolutePath}")
        }
    }
}
