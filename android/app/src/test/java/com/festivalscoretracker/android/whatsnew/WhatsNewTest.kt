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
import com.festivalscoretracker.android.core.whatsnew.ChangelogSection
import com.festivalscoretracker.android.core.whatsnew.ChangelogSeenRecord
import com.festivalscoretracker.android.core.whatsnew.ChangelogSeenStore
import com.festivalscoretracker.android.core.whatsnew.WhatsNewGate
import com.festivalscoretracker.android.core.whatsnew.WhatsNewMode
import com.festivalscoretracker.android.presentation.firstrun.FirstRunCenter
import com.festivalscoretracker.android.presentation.whatsnew.WhatsNewController
import com.festivalscoretracker.android.presentation.whatsnew.WhatsNewPresentation
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of Apple `ChangelogTests`/`WhatsNewTests` plus the Android slot, store and controller. */
class WhatsNewTest {
    // region Changelog

    @Test
    fun hashMatchesTheWebPrecomputedHash() {
        assertEquals(Changelog.WEB_HASH, Changelog.currentHash)
        assertEquals(Changelog.WEB_HASH, Changelog.hash(Changelog.entries))
        // JS: calculateChangelogHash([]) → "[]" → ((91*31)+93).toString(36).
        assertEquals(Integer.toString(91 * 31 + 93, 36), Changelog.hash(emptyList()))
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
