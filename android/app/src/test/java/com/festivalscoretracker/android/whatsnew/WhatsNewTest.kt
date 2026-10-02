package com.festivalscoretracker.android.whatsnew

import com.festivalscoretracker.android.core.firstrun.FirstRunMode
import com.festivalscoretracker.android.core.firstrun.FirstRunPageKey
import com.festivalscoretracker.android.core.firstrun.FirstRunSeenStore
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.settings.MemoryBlobStore
import com.festivalscoretracker.android.core.settings.ResetPolicy
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.core.whatsnew.Changelog
import com.festivalscoretracker.android.core.whatsnew.ChangelogEntry
import com.festivalscoretracker.android.core.whatsnew.ChangelogGroup
import com.festivalscoretracker.android.core.whatsnew.ChangelogSection
import com.festivalscoretracker.android.core.whatsnew.ChangelogSeenRecord
import com.festivalscoretracker.android.core.whatsnew.ChangelogSeenStore
import com.festivalscoretracker.android.core.whatsnew.InstallChannel
import com.festivalscoretracker.android.core.whatsnew.TesterNotes
import com.festivalscoretracker.android.core.whatsnew.WhatsNewBlock
import com.festivalscoretracker.android.core.whatsnew.WhatsNewGate
import com.festivalscoretracker.android.core.whatsnew.WhatsNewMode
import com.festivalscoretracker.android.presentation.firstrun.FirstRunCenter
import com.festivalscoretracker.android.presentation.whatsnew.WhatsNewController
import com.festivalscoretracker.android.presentation.whatsnew.WhatsNewPresentation
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of Apple `ChangelogTests`/`WhatsNewTests` plus the Android slot, store and controller. */
class WhatsNewTest {
    // region Changelog

    private val sampleDocument = """
        {"schema": 1, "platform": "android", "version": "2610.01.04", "baseline": "2610.01.03", "extra": true,
         "entries": [
          {"version": "2610.01.04", "released": false, "items": ["Rivals refresh correctly.", "  "]},
          {"version": "2610.01.03", "released": true, "items": ["The Item Shop badge is back.", "Songs load faster."]},
          {"version": "2610.01.02", "released": true, "items": []},
          {"version": "2610.01.01", "items": ["The first release."]}
         ]}
    """.trimIndent()

    @Test
    fun decodesOneVersionSectionPerEntry() {
        val entries = Changelog.decode(sampleDocument)
        assertEquals(listOf("2610.01.04", "2610.01.03", "2610.01.01"), entries.map { it.version })
        assertEquals(listOf(false, true, true), entries.map { it.released })
        assertEquals(listOf(ChangelogSection("Version 2610.01.04", listOf("Rivals refresh correctly."))), entries[0].sections)
        assertEquals("Version 2610.01.03", entries[1].sections.single().displayTitle)
    }

    @Test
    fun decodeBoundsAndRejectsMalformedDocuments() {
        val many = (0 until 50).joinToString(",") { """{"version":"2610.$it","items":["${"a".repeat(2000)}"]}""" }
        val entries = Changelog.decode("""{"entries":[$many]}""")
        assertEquals(Changelog.MAX_ENTRIES, entries.size)
        assertEquals(Changelog.MAX_ITEM_LENGTH, entries[0].sections[0].items[0].length)
        for (bad in listOf("[]", "{}", """{"entries":[{"items":[]}]}""", "not json")) {
            assertTrue(bad, runCatching { Changelog.decode(bad) }.isFailure)
        }
    }

    @Test
    fun loadFallsBackToEmptyAndReadsTheBundledPlaceholder() {
        assertEquals(emptyList<ChangelogEntry>(), Changelog.load { null })
        assertEquals(emptyList<ChangelogEntry>(), Changelog.load { "nope".byteInputStream() })
        assertEquals(3, Changelog.load { sampleDocument.byteInputStream() }.size)
        // src/main/resources/WhatsNew.json is on the unit-test classpath.
        assertEquals(listOf("2610.01.01"), Changelog.entries.map { it.version })
    }

    @Test
    fun hashChangesWithVersionsAndEmptyIsNeverShown() = runBlocking {
        val one = Changelog.decode("""{"entries":[{"version":"2610.01.01","items":["a"]}]}""")
        val two = Changelog.decode("""{"entries":[{"version":"2610.01.02","items":["a"]},{"version":"2610.01.01","items":["a"]}]}""")
        assertTrue(Changelog.hash(one) != Changelog.hash(two))
        // JS: calculateChangelogHash([]) → "[]" → ((91*31)+93).toString(36).
        assertEquals(Integer.toString(91 * 31 + 93, 36), Changelog.emptyHash)
        assertFalse(ChangelogSeenStore(MemoryBlobStore()).shouldShow(Changelog.emptyHash))
    }

    @Test
    fun canonicalJsonMatchesJsonStringify() {
        val entries = listOf(ChangelogEntry(listOf(ChangelogSection("A \"B\"", listOf("x\\y", "n\nr\rt\tb\bf\u000Cz\u0001", "é🎸")))))
        assertEquals(
            "[{\"sections\":[{\"title\":\"A \\\"B\\\"\",\"items\":[\"x\\\\y\",\"n\\nr\\rt\\tb\\bf\\fz\\u0001\",\"é🎸\"]}]}]",
            Changelog.canonicalJson(entries),
        )
        assertEquals("[]", Changelog.canonicalJson(emptyList()))
    }

    @Test
    fun titleCaseKeepsMinorWordsLowerAfterTheFirst() {
        assertEquals("Song Details", Changelog.titleCase("SONG DETAILS"))
        assertEquals("Item Shop", ChangelogSection("ITEM SHOP", emptyList()).displayTitle)
        assertEquals("The Best of the Rest", Changelog.titleCase("THE  BEST OF THE REST"))
        assertEquals("", Changelog.titleCase(""))
    }

    @Test
    fun displayEntriesDropManualMentionsAndEmptySections() {
        val entries = listOf(
            ChangelogEntry(
                listOf(
                    ChangelogSection("MANUAL", listOf("Anything")),
                    ChangelogSection("SONGS", listOf("See the Manual page.", "Kept item.", "Manually sorted stays.")),
                    ChangelogSection("RIVALS", listOf("manual-only bullet")),
                ),
            ),
            ChangelogEntry(listOf(ChangelogSection("USER MANUAL", listOf("x")))),
        )
        val display = Changelog.displayEntries(entries)
        assertEquals(1, display.size)
        assertEquals(listOf(ChangelogSection("SONGS", listOf("Kept item.", "Manually sorted stays."))), display.single().sections)
        // The shipping changelog has no Manual mentions: displayed verbatim.
        assertEquals(Changelog.entries, Changelog.displayEntries())
        val versioned = listOf(ChangelogEntry(listOf(ChangelogSection("Version 2610.01.02", listOf("Kept.", "Manual gone."))), "2610.01.02", false))
        assertEquals(listOf(ChangelogEntry(listOf(ChangelogSection("Version 2610.01.02", listOf("Kept."))), "2610.01.02", false)), Changelog.displayEntries(versioned))
    }

    // endregion

    // region Groups and tester notes

    private val groupedDocument = """
        {"schema": 1, "platform": "android", "version": "2610.02.02", "baseline": "2610.01.03",
         "entries": [
          {"version": "2610.02.02", "released": false,
           "items": ["Songs: Rows load faster.", "Rivals: Lists refresh.", "A loose note."],
           "groups": [{"category": "Songs", "items": ["Rows load faster."]},
                      {"category": "Rivals", "items": ["Lists refresh.", "See the Manual."]},
                      {"category": null, "items": ["A loose note."]}, 5, {"category": "Bands", "items": []}],
           "testflight": {"since": "2610.02.01", "new": ["Songs: Rows load faster."], "release": "2610.01.03",
                          "vs_release": ["Songs: Rows load faster.", "Songs: Filter fixed.", "General: Polish."],
                          "groups": [{"category": "Songs", "items": ["Rows load faster.", "Filter fixed."]},
                                     {"category": "General", "items": ["Polish."]}]}},
          {"version": "2610.01.03", "released": true, "items": ["The first release."]}
         ]}
    """.trimIndent()

    @Test
    fun decodesGroupsAndTesterNotesVerbatim() {
        val entries = Changelog.decode(groupedDocument)
        assertEquals(
            listOf(
                ChangelogGroup("Songs", listOf("Rows load faster.")),
                ChangelogGroup("Rivals", listOf("Lists refresh.", "See the Manual.")),
                ChangelogGroup(null, listOf("A loose note.")),
            ),
            entries[0].groups,
        )
        assertEquals(
            TesterNotes("2610.01.03", listOf(ChangelogGroup("Songs", listOf("Rows load faster.", "Filter fixed.")), ChangelogGroup("General", listOf("Polish.")))),
            entries[0].tester,
        )
        // No groups in the document: the flat items become one uncategorized group (never re-classified).
        assertEquals(listOf(ChangelogGroup(null, listOf("The first release."))), entries[1].groups)
        assertNull(entries[1].tester)
        // The show-once hash still follows the release items only.
        assertEquals(
            Changelog.hash(entries.map { it.copy(groups = emptyList(), tester = null) }),
            Changelog.hash(entries),
        )
    }

    @Test
    fun testerFallsBackToVsReleaseAndIsBounded() {
        val fallback = Changelog.decode(
            """{"entries":[{"version":"1","items":["a"],"testflight":{"release":null,"vs_release":["Songs: x"," "]}}]}""",
        ).single().tester
        assertEquals(TesterNotes(null, listOf(ChangelogGroup(null, listOf("Songs: x")))), fallback)
        assertEquals("Changes So Far", fallback!!.title)
        assertNull(Changelog.decode("""{"entries":[{"version":"1","items":["a"],"testflight":{"vs_release":[]}}]}""").single().tester)
        val many = (0 until 30).joinToString(",") { """{"category":"${"C".repeat(50)}$it","items":[${(0 until 10).joinToString(",") { "\"n\"" }}]}""" }
        val tester = Changelog.decode("""{"entries":[{"version":"1","items":["a"],"testflight":{"groups":[$many]}}]}""").single().tester!!
        assertEquals(Changelog.MAX_TESTER_ITEMS, tester.groups.sumOf { it.items.size })
        assertTrue(tester.groups.size <= Changelog.MAX_GROUPS)
        assertEquals(Changelog.MAX_CATEGORY_LENGTH, tester.groups[0].category!!.length)
        val groups = Changelog.decodeGroups(Json.parseToJsonElement("""[{"category":"","items":["x"]},{"items":["y"]}]"""), 1)
        assertEquals(listOf(ChangelogGroup(null, listOf("x"))), groups)
    }

    @Test
    fun displayBlocksPickTheChannelsNotesWithCategoryHeadings() {
        val entries = Changelog.decode(groupedDocument)
        val store = Changelog.displayBlocks(entries, InstallChannel.Store)
        assertEquals(listOf("Version 2610.02.02", "Version 2610.01.03"), store.map { it.title })
        // Manual bullets are dropped; empty groups vanish; uncategorized notes come last under "Other".
        assertEquals(listOf("Songs", "Rivals", "Other"), store[0].groups.map { it.displayTitle })
        assertEquals(listOf("Lists refresh."), store[0].groups[1].items)
        assertTrue(store[0].headed)
        // Without any category there are no headings (TestFlight's rule).
        assertFalse(store[1].headed)
        val tester = Changelog.displayBlocks(entries, InstallChannel.Tester)
        assertEquals(listOf("Changes Since Release 2610.01.03", "Version 2610.01.03"), tester.map { it.title })
        assertEquals(listOf("Rows load faster.", "Filter fixed.", "Polish."), tester[0].groups.flatMap { it.items })
        // Entries without groups (older documents, the placeholder) keep their release bullets for both channels.
        assertEquals(
            listOf(WhatsNewBlock("Version 2610.01.01", listOf(ChangelogGroup(null, listOf("The first release of Festival Score Tracker for Android."))))),
            Changelog.displayBlocks(channel = InstallChannel.Tester),
        )
        val manual = listOf(ChangelogEntry(listOf(ChangelogSection("MANUAL", listOf("x")))), ChangelogEntry(listOf(ChangelogSection("Version 1", listOf("Manual only.")))))
        assertEquals(emptyList<WhatsNewBlock>(), Changelog.displayBlocks(manual, InstallChannel.Store))
    }

    @Test
    fun installChannelComesFromTheInstallerWithADebugOverride() {
        assertEquals(InstallChannel.Store, InstallChannel.fromInstaller("com.android.vending"))
        for (other in listOf(null, "", "com.google.android.packageinstaller", "com.amazon.venezia", "adb")) {
            assertEquals(other, InstallChannel.Tester, InstallChannel.fromInstaller(other))
        }
        assertEquals(InstallChannel.Store, InstallChannel.resolve(null, debugBuild = false) { "com.android.vending" })
        assertEquals(InstallChannel.Tester, InstallChannel.resolve(null, debugBuild = false) { error("no install source") })
        // The override works in debug launches only, and an unknown value falls back to the installer.
        assertEquals(InstallChannel.Tester, InstallChannel.resolve("tester", debugBuild = true) { "com.android.vending" })
        assertEquals(InstallChannel.Store, InstallChannel.resolve("STORE", debugBuild = true) { null })
        assertEquals(InstallChannel.Store, InstallChannel.resolve("tester", debugBuild = false) { "com.android.vending" })
        assertEquals(InstallChannel.Tester, InstallChannel.resolve("bogus", debugBuild = true) { null })
        assertEquals("store", DebugLaunch.parse(mapOf("FST_DEBUG_DISTRIBUTION" to "store")).distribution)
        assertEquals(InstallChannel.Store, WhatsNewController(ChangelogSeenStore(MemoryBlobStore()), center(), WhatsNewMode.Off, "1").channel)
    }

    // endregion

    // region Seen store

    @Test
    fun seenStoreRoundTripsValidatesAndResets() = runBlocking {
        val blob = MemoryBlobStore()
        val store = ChangelogSeenStore(blob)
        assertNull(store.load())
        assertTrue(store.shouldShow())
        store.markSeen("0.2.0")
        assertEquals(ChangelogSeenRecord("0.2.0", Changelog.currentHash), store.load())
        assertFalse(store.shouldShow())
        assertTrue(store.shouldShow("other"))
        store.markSeen("v".repeat(100), "h")
        assertEquals(64, store.load()!!.version.length)
        store.reset()
        assertNull(blob.value)
        assertTrue(store.shouldShow())
    }

    @Test
    fun seenStoreTreatsCorruptOrOversizedAsUnseen() {
        assertNull(ChangelogSeenStore.decode(null))
        assertNull(ChangelogSeenStore.decode(""))
        assertNull(ChangelogSeenStore.decode("not json"))
        assertNull(ChangelogSeenStore.decode("[]"))
        assertNull(ChangelogSeenStore.decode("""{"version":"1"}"""))
        assertNull(ChangelogSeenStore.decode("""{"version":1,"hash":"h"}"""))
        assertNull(ChangelogSeenStore.decode("""{"version":"1","hash":""}"""))
        assertNull(ChangelogSeenStore.decode("""{"version":"1","hash":"${"h".repeat(33)}"}"""))
        assertNull(ChangelogSeenStore.decode("""{"version":"${"v".repeat(65)}","hash":"h"}"""))
        assertNull(ChangelogSeenStore.decode("""{"version":"1","hash":"h","pad":"${"x".repeat(1100)}"}"""))
        // Web records carry extra keys in future versions: ignored.
        assertEquals(ChangelogSeenRecord("0.1.133", "-6p8bh3"), ChangelogSeenStore.decode("""{"version":"0.1.133","hash":"-6p8bh3","extra":true}"""))
        assertEquals("""{"version":"1","hash":"h"}""", ChangelogSeenStore.encode(ChangelogSeenRecord("1", "h")))
    }

    @Test
    fun seenKeyIsRegisteredAndSurvivesReset() {
        val entry = SettingsRegistry.entries.single { it.key == SettingsRegistry.CHANGELOG_SEEN }
        assertEquals(ResetPolicy.Kept, entry.policy)
        assertEquals("fst.changelog.seen.v1", SettingsRegistry.CHANGELOG_SEEN)
    }

    // endregion

    // region Gate and debug extra

    @Test
    fun modeParsesDebugExtraAndReleaseIsAlwaysNormal() {
        assertEquals(WhatsNewMode.Off, WhatsNewMode.parse(null, debugBuild = true))
        assertEquals(WhatsNewMode.Off, WhatsNewMode.parse("off", debugBuild = true))
        assertEquals(WhatsNewMode.Off, WhatsNewMode.parse("bogus", debugBuild = true))
        assertEquals(WhatsNewMode.Normal, WhatsNewMode.parse(" ON ", debugBuild = true))
        assertEquals(WhatsNewMode.Fresh, WhatsNewMode.parse("fresh", debugBuild = true))
        assertEquals(WhatsNewMode.Force, WhatsNewMode.parse("force", debugBuild = true))
        assertEquals(WhatsNewMode.Normal, WhatsNewMode.parse("off", debugBuild = false))
        assertEquals(WhatsNewMode.Normal, WhatsNewMode.parse(null, debugBuild = false))
        assertEquals("force", DebugLaunch.parse(mapOf("FST_DEBUG_WHATS_NEW" to "force")).whatsNew)
        assertNull(DebugLaunch.parse(emptyMap()).whatsNew)
    }

    @Test
    fun gatePendingRulesAndTitle() {
        assertFalse(WhatsNewGate.isPending(WhatsNewMode.Off, hasUnseenChangelog = true))
        assertTrue(WhatsNewGate.isPending(WhatsNewMode.Force, hasUnseenChangelog = false))
        assertTrue(WhatsNewGate.isPending(WhatsNewMode.Normal, hasUnseenChangelog = true))
        assertFalse(WhatsNewGate.isPending(WhatsNewMode.Normal, hasUnseenChangelog = false))
        assertTrue(WhatsNewGate.isPending(WhatsNewMode.Fresh, hasUnseenChangelog = true))
        assertEquals("What's New · 0.2.0", WhatsNewGate.title("0.2.0"))
        assertEquals("What's New", WhatsNewGate.title(" "))
    }

    // endregion

    // region Slot and controller

    private fun center(mode: FirstRunMode = FirstRunMode.Normal) = FirstRunCenter(FirstRunSeenStore(MemoryBlobStore()), mode)

    @Test
    fun slotClaimExcludesCarouselsAndOtherClaimants() = runBlocking {
        val center = center()
        assertTrue(center.claim("whats-new"))
        assertTrue(center.claim("whats-new"))
        assertFalse(center.claim("other"))
        assertEquals("whats-new", center.claimed.value)
        assertNull(center.tryBegin(FirstRunPageKey.Songs, AppSettings(), compact = true))
        assertNull(center.beginReplay(FirstRunPageKey.Songs, compact = true))
        center.release("other")
        assertEquals("whats-new", center.claimed.value)
        center.release("whats-new")
        assertNull(center.claimed.value)
        val carousel = center.tryBegin(FirstRunPageKey.Songs, AppSettings(), compact = true)
        assertNotNull(carousel)
        assertFalse(center.claim("whats-new"))
        center.complete(carousel!!)
        assertTrue(center.claim("whats-new"))
    }

    @Test
    fun normalLaunchPresentsOncePerHashAfterTheCarousel() = runBlocking {
        val blob = MemoryBlobStore()
        val center = center()
        val controller = WhatsNewController(ChangelogSeenStore(blob), center, WhatsNewMode.Normal, "0.2.0")
        val carousel = center.tryBegin(FirstRunPageKey.Songs, AppSettings(), compact = true)!!
        assertFalse(controller.presentIfOwed())
        center.complete(carousel)
        assertTrue(controller.presentIfOwed())
        assertEquals(WhatsNewPresentation(isReplay = false), controller.shown.value)
        assertFalse(controller.presentIfOwed())
        assertNull(center.tryBegin(FirstRunPageKey.Leaderboards, AppSettings(), compact = true))
        controller.dismiss()
        assertNull(controller.shown.value)
        assertNull(center.claimed.value)
        assertEquals(ChangelogSeenRecord("0.2.0", Changelog.currentHash), ChangelogSeenStore.decode(blob.value))
        controller.dismiss() // no-op when nothing shows
        assertFalse(controller.presentIfOwed())
        // A new process with the same hash owes nothing.
        assertFalse(WhatsNewController(ChangelogSeenStore(blob), center(), WhatsNewMode.Normal, "0.2.0").presentIfOwed())
    }

    @Test
    fun offFreshForceAndReplay() = runBlocking {
        val blob = MemoryBlobStore(ChangelogSeenStore.encode(ChangelogSeenRecord("0.1", Changelog.currentHash)))
        val off = WhatsNewController(ChangelogSeenStore(blob), center(), WhatsNewMode.Off, "0.2.0")
        assertFalse(off.resolveIfNeeded())
        assertFalse(off.presentIfOwed())
        // Replay ignores the gate and the stored dismissal.
        assertTrue(off.replay())
        assertEquals(WhatsNewPresentation(isReplay = true), off.shown.value)
        assertFalse(off.replay())
        off.dismiss()
        assertEquals("0.2.0", ChangelogSeenStore.decode(blob.value)!!.version)

        assertFalse(WhatsNewController(ChangelogSeenStore(blob), center(), WhatsNewMode.Normal, "0.2.0").presentIfOwed())
        assertTrue(WhatsNewController(ChangelogSeenStore(blob), center(), WhatsNewMode.Force, "0.2.0").presentIfOwed())
        val fresh = WhatsNewController(ChangelogSeenStore(blob), center(), WhatsNewMode.Fresh, "0.2.0")
        assertTrue(fresh.resolveIfNeeded())
        assertNull(blob.value)
        assertTrue(fresh.presentIfOwed())

        // Replay waits while a carousel holds the slot.
        val busy = center()
        busy.beginReplay(FirstRunPageKey.Songs, compact = true)
        assertFalse(WhatsNewController(ChangelogSeenStore(MemoryBlobStore()), busy, WhatsNewMode.Off, "1").replay())
    }

    // endregion
}
