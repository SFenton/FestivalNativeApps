package com.festivalscoretracker.android.core.songs

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SongDifficulty
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.settings.MetadataField
import com.festivalscoretracker.android.core.shop.ShopHighlight
import com.festivalscoretracker.android.core.shop.ShopPresentationPolicy
import com.festivalscoretracker.android.core.shop.ShopResponse
import com.festivalscoretracker.android.core.shop.SongRelatedPublicationPolicy
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.SongsFixtures
import java.text.Collator
import java.time.ZoneOffset
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class SongsCoreTest {
    private val sorter = SongCatalogSort(Collator.getInstance(Locale.US))
    private val a = Fixtures.song("a", "Alpha", artist = "Zed", year = 2001)
    private val b = Fixtures.song("b", "Beta", artist = "Amy", year = 2010)
    private val c = Fixtures.song("c", "Gamma", artist = "Amy", year = 1999, lead = null)
    private val d = Fixtures.song("d", "Beta", artist = "Amy", year = 2003)
    private val songs = listOf(a, b, c, d)

    // region Shop models

    @Test
    fun shopDecodesValidatesAndSorts() {
        val shop = FestivalApi.JSON.decodeFromString(ShopResponse.serializer(), SongsFixtures.shopJson)
        shop.validate()
        assertEquals(listOf("s-alpha", "s-x", "s-beta"), shop.sortedSongs(Collator.getInstance(Locale.US)).map { it.songId })
        assertEquals("Band Two · 2019", shop.songs[0].subtitle)
        assertEquals("Band One", shop.songs[1].subtitle)
    }

    @Test
    fun shopRejectsBadCardinalityIdsAndLinks() {
        val ok = SongsFixtures.offer("x")
        fun invalid(response: ShopResponse) = assertThrows(FestivalApiException.InvalidResponse::class.java) { response.validate() }
        invalid(ShopResponse(2, listOf(ok)))
        invalid(ShopResponse(2, listOf(ok, ok.copy(songId = "X"))))
        invalid(ShopResponse(1, listOf(ok.copy(songId = "a/b"))))
        invalid(ShopResponse(1, listOf(ok.copy(title = ""))))
        listOf(
            "http://www.fortnite.com/item-shop/jam-tracks/x",
            "https://evil.example/item-shop/jam-tracks/x",
            "https://www.fortnite.com/item-shop/jam-tracks/",
            "https://www.fortnite.com/other/x",
            "https://www.fortnite.com:8443/item-shop/jam-tracks/x",
            "https://www.fortnite.com/item-shop/jam-tracks/x?ref=1",
            "https://www.fortnite.com/item-shop/jam-tracks/x#top",
            "https://user@www.fortnite.com/item-shop/jam-tracks/x",
            "not a url",
            "",
        ).forEach { url ->
            assertFalse(url, ShopResponse.isOfficialShopUrl(url))
            invalid(ShopResponse(1, listOf(ok.copy(shopUrl = url))))
        }
        assertTrue(ShopResponse.isOfficialShopUrl("https://WWW.fortnite.com/item-shop/jam-tracks/x"))
        assertFalse(ShopResponse.isOfficialShopUrl(null))
    }

    @Test
    fun highlightAndPublicationPolicies() {
        val leaving = SongsFixtures.offer("a", leaving = true, isNew = true)
        val fresh = SongsFixtures.offer("b", isNew = true)
        assertEquals(ShopHighlight.LeavingTomorrow, ShopPresentationPolicy.highlight(leaving, hidden = false, highlightingDisabled = false))
        assertEquals(ShopHighlight.New, ShopPresentationPolicy.highlight(fresh, hidden = false, highlightingDisabled = false))
        assertNull(ShopPresentationPolicy.highlight(SongsFixtures.offer("c"), hidden = false, highlightingDisabled = false))
        assertNull(ShopPresentationPolicy.highlight(fresh, hidden = true, highlightingDisabled = false))
        assertNull(ShopPresentationPolicy.highlight(fresh, hidden = false, highlightingDisabled = true))
        assertNull(ShopPresentationPolicy.highlight(null, hidden = false, highlightingDisabled = false))
        assertTrue(SongRelatedPublicationPolicy.matches(7, 7, 7))
        assertFalse(SongRelatedPublicationPolicy.matches(7, 8, 8))
        assertFalse(SongRelatedPublicationPolicy.matches(7, 7, 8))
        assertFalse(SongRelatedPublicationPolicy.matches(7, null, 7))
        assertFalse(SongRelatedPublicationPolicy.matches(null, 7, 7))
        assertFalse(SongRelatedPublicationPolicy.matches(7, 7, null))
        assertEquals(setOf("x"), SongsFixtures.shop(SongsFixtures.offer("x")).offersById.keys)
    }

    // endregion

    // region Filters

    @Test
    fun publicFilterMatchesChartAndIntensityBuckets() {
        assertFalse(SongFilter().isActive)
        // Intensity buckets need an instrument (web `checkDiff`).
        assertFalse(SongFilter(excludedIntensities = setOf(4)).isActive)
        assertTrue(SongFilter(excludedIntensities = setOf(4)).matches(a))
        assertFalse(SongFilter(excludedIntensities = setOf(8)).isValid)
        assertTrue(SongFilter(Instrument.Lead).matches(a))
        assertFalse(SongFilter(Instrument.Lead).matches(c))
        // Lead raw 3.0 → bucket 4 (web trunc + 1).
        assertFalse(SongFilter(Instrument.Lead, setOf(4)).matches(a))
        assertTrue(SongFilter(Instrument.Lead, setOf(1, 2, 3, 5, 6, 7, 0)).matches(a))
        assertTrue(SongFilter().matches(c))
        assertEquals(SongFilter(), SongFilter(Instrument.Bass).scopedTo(setOf(Instrument.Lead)))
        assertEquals(SongFilter(Instrument.Bass), SongFilter(Instrument.Bass).scopedTo(setOf(Instrument.Bass)))
    }

    @Test
    fun shopAvailabilityCountsLeavingOffersAsAvailable() {
        val offers = mapOf("a" to SongsFixtures.offer("a"), "b" to SongsFixtures.offer("b", leaving = true))
        assertEquals(songs, SongGeneralFilter().filterShop(songs, offers))
        assertEquals(listOf(a, b), SongGeneralFilter(shopUnavailable = false).filterShop(songs, offers))
        assertEquals(listOf(c, d), SongGeneralFilter(shopAvailable = false).filterShop(songs, offers))
        assertTrue(SongGeneralFilter(shopAvailable = false, shopUnavailable = false).filterShop(songs, offers).isEmpty())
        assertTrue(SongGeneralFilter(shopUnavailable = false).filterShop(songs, emptyMap()).isEmpty())
    }

    @Test
    fun catalogueBucketsMatchWebLabelsAndKeys() {
        assertEquals(1980, SongCatalogBuckets.decade(1989))
        assertEquals(2020, SongCatalogBuckets.decade(2020))
        assertNull(SongCatalogBuckets.decade(0))
        assertNull(SongCatalogBuckets.decade(null))
        assertEquals(0, SongCatalogBuckets.duration(59))
        assertEquals(1, SongCatalogBuckets.duration(60))
        assertEquals(9, SongCatalogBuckets.duration(599))
        assertEquals(10, SongCatalogBuckets.duration(1_200))
        assertNull(SongCatalogBuckets.duration(0))
        assertNull(SongCatalogBuckets.duration(null))
        assertEquals(listOf(1990, 2000, 2010), SongCatalogBuckets.decades(songs + a.copy(songId = "u", year = null)))
        assertEquals((0..9).toList(), SongCatalogBuckets.durations(songs))
        assertEquals((0..10).toList(), SongCatalogBuckets.durations(songs + a.copy(songId = "long", durationSeconds = 660)))
        assertEquals("1990s", SongCatalogBuckets.decadeLabel(1990))
        assertEquals("Under 1 Minute", SongCatalogBuckets.durationLabel(0))
        assertEquals("3-4 Minutes", SongCatalogBuckets.durationLabel(3))
        assertEquals("10+ Minutes", SongCatalogBuckets.durationLabel(10))
        assertTrue(SongCatalogBuckets.isDecade(1980))
        assertFalse(SongCatalogBuckets.isDecade(1985))
        assertFalse(SongCatalogBuckets.isDecade(0))
        assertTrue(SongCatalogBuckets.isDuration(10))
        assertFalse(SongCatalogBuckets.isDuration(11))
        assertFalse(SongCatalogBuckets.isDuration(-1))
    }

    @Test
    fun generalFilterMatchesYearDurationAndDoubleBass() {
        val supported = a.copy(doubleBassSupported = true)
        val unsupported = b.copy(doubleBassSupported = false)
        val unknown = c.copy(doubleBassSupported = null)
        val all = SongGeneralFilter()
        assertFalse(all.catalogActive)
        assertFalse(all.isActive(shopVisible = true))
        assertTrue(listOf(supported, unsupported, unknown).all(all::matches))
        val onlySupported = SongGeneralFilter(doubleBassUnsupported = false)
        assertTrue(onlySupported.catalogActive)
        assertEquals(listOf(supported), listOf(supported, unsupported, unknown).filter(onlySupported::matches))
        val onlyUnsupported = SongGeneralFilter(doubleBassSupported = false)
        assertEquals(listOf(unsupported), listOf(supported, unsupported, unknown).filter(onlyUnsupported::matches))
        val none = SongGeneralFilter(doubleBassSupported = false, doubleBassUnsupported = false)
        assertTrue(listOf(supported, unsupported, unknown).none(none::matches))
        // Year: hidden decade drops its songs; once narrowed, songs without a year drop too.
        val no2000s = SongGeneralFilter(excludedDecades = setOf(2000))
        assertEquals(listOf(b, c), songs.filter(no2000s::matches))
        assertFalse(no2000s.matches(a.copy(year = null)))
        // Duration: Fixtures default to 200 s (bucket 3).
        val noThree = SongGeneralFilter(excludedDurations = setOf(3))
        assertTrue(songs.none(noThree::matches))
        assertTrue(noThree.matches(a.copy(durationSeconds = 59)))
        assertFalse(noThree.matches(a.copy(durationSeconds = null)))
        // Item Shop only counts while the Shop is shown.
        val shop = SongGeneralFilter(shopUnavailable = false)
        assertFalse(shop.catalogActive)
        assertTrue(shop.isActive(shopVisible = true))
        assertFalse(shop.isActive(shopVisible = false))
        assertTrue(shop.matches(a))
        assertFalse(SongGeneralFilter(excludedDecades = setOf(1985)).isValid)
        assertFalse(SongGeneralFilter(excludedDurations = setOf(12)).isValid)
        assertTrue(no2000s.isValid)
        assertEquals(setOf(2000), no2000s.excluded(SongGeneralBucketKind.Year))
        assertEquals(setOf(4), all.withExcluded(SongGeneralBucketKind.Duration, setOf(4)).excluded(SongGeneralBucketKind.Duration))
    }

    @Test
    fun playerFilterAndWithinChartOrAcrossCharts() {
        val facts = mapOf(
            ("a" to Instrument.Lead) to ChartScoreFacts(100, true),
            ("b" to Instrument.Lead) to ChartScoreFacts(50, false),
            ("b" to Instrument.Bass) to ChartScoreFacts(0, true),
        )
        val lookup: (String, Instrument) -> ChartScoreFacts? = { id, chart -> facts[id to chart] }
        val all = Instrument.entries.toSet()
        val empty = SongPlayerScoreFilter()
        assertFalse(empty.isActive)
        assertEquals(songs, empty.filter(songs, lookup, all, null))

        val hasLead = empty.with(SongScoreFilterKind.HasScores, Instrument.Lead, true)
        assertEquals(listOf(a, b), hasLead.filter(songs, lookup, all, null))
        val hasLeadNoFc = hasLead.with(SongScoreFilterKind.MissingFCs, Instrument.Lead, true)
        assertEquals(listOf(b), hasLeadNoFc.filter(songs, lookup, all, null))
        // Uncharted Lead (song c) never matches a Lead check.
        val missingLead = empty.with(SongScoreFilterKind.MissingScores, Instrument.Lead, true)
        assertEquals(listOf(d), missingLead.filter(songs, lookup, all, null))
        // OR across charts: Missing Lead or Has FC Bass.
        val either = missingLead.with(SongScoreFilterKind.HasFCs, Instrument.Bass, true)
        assertEquals(listOf(b, d), either.filter(songs, lookup, all, null))
        // Selected instrument limits the active charts.
        assertEquals(listOf(b), either.filter(songs, lookup, all, Instrument.Bass))
        assertEquals(songs, either.filter(songs, lookup, all, Instrument.Drums))
        // Hidden charts are inactive, not erased.
        assertEquals(songs, either.filter(songs, lookup, setOf(Instrument.Drums), null))
        assertTrue(either.contains(SongScoreFilterKind.HasFCs, Instrument.Bass))
        assertEquals(setOf(Instrument.Lead), either.scopedTo(setOf(Instrument.Lead)).missingScores)
        assertFalse(either.with(SongScoreFilterKind.HasFCs, Instrument.Bass, false).contains(SongScoreFilterKind.HasFCs, Instrument.Bass))
        // Missing/has score on an empty (validated) index.
        assertEquals(listOf(a, b, d), missingLead.filter(songs, { _, _ -> null }, all, null))
    }

    @Test
    fun playerFilterGlobalSwitchesTouchOnlyVisibleCharts() {
        val visible = setOf(Instrument.Lead, Instrument.Bass)
        val base = SongPlayerScoreFilter(hasFCs = setOf(Instrument.Drums))
        val all = base.withAll(SongScoreFilterKind.HasFCs, visible, true)
        assertTrue(all.allVisible(SongScoreFilterKind.HasFCs, visible))
        assertEquals(setOf(Instrument.Drums, Instrument.Lead, Instrument.Bass), all.hasFCs)
        val cleared = all.withAll(SongScoreFilterKind.HasFCs, visible, false)
        assertEquals(setOf(Instrument.Drums), cleared.hasFCs)
        assertFalse(cleared.allVisible(SongScoreFilterKind.HasFCs, emptySet()))
        SongScoreFilterKind.entries.forEach { kind ->
            val set = SongPlayerScoreFilter().with(kind, Instrument.Vocals, true)
            assertEquals(setOf(Instrument.Vocals), set.charts(kind))
            assertTrue(set.isActive)
        }
    }

    @Test
    fun playerFilterPersistsBoundedTypedJson() {
        val filter = SongPlayerScoreFilter(missingScores = setOf(Instrument.ProDrums, Instrument.Lead), hasFCs = setOf(Instrument.Bass))
        val encoded = filter.encoded()
        assertEquals(
            """{"missingScores":["Solo_Guitar","Solo_PeripheralDrums"],"hasScores":[],"missingFCs":[],"hasFCs":["Solo_Bass"]}""",
            encoded,
        )
        assertEquals(filter, SongPlayerScoreFilter.decodeSaved(encoded))
        assertEquals("", SongPlayerScoreFilter().encoded())
        assertEquals(SongPlayerScoreFilter(), SongPlayerScoreFilter.decodeSaved(null))
        assertEquals(SongPlayerScoreFilter(), SongPlayerScoreFilter.decodeSaved(""))
        assertNull(SongPlayerScoreFilter.decodeSaved("{nope"))
        assertNull(SongPlayerScoreFilter.decodeSaved("""{"missingScores":["Solo_Nope"],"hasScores":[],"missingFCs":[],"hasFCs":[]}"""))
        assertNull(SongPlayerScoreFilter.decodeSaved("""{"missingScores":["Solo_Bass","Solo_Bass"],"hasScores":[],"missingFCs":[],"hasFCs":[]}"""))
        assertNull(SongPlayerScoreFilter.decodeSaved("""{"missingScores":[]}"""))
        assertNull(SongPlayerScoreFilter.decodeSaved("x".repeat(SongPlayerScoreFilter.MAX_STORED_BYTES + 1)))
    }

    // endregion

    // region Sort and pipeline

    @Test
    fun shopSortPutsMembersFirstWithTies() {
        val ids = setOf("c", "b")
        assertEquals(listOf("b", "c", "a", "d"), sorter.sorted(songs, SongSortMode.Shop, true, ids).map { it.songId })
        assertEquals(listOf("d", "a", "c", "b"), sorter.sorted(songs, SongSortMode.Shop, false, ids).map { it.songId })
        // Title tie (b/d both "Beta", same artist) breaks on year then ID.
        assertEquals(listOf("a", "d", "b", "c"), sorter.sorted(songs, SongSortMode.Shop, true, emptySet()).map { it.songId })
    }

    @Test
    fun shopHeadersOnlyWithTwoBuckets() {
        val offers = mapOf("a" to SongsFixtures.offer("a", leaving = true), "b" to SongsFixtures.offer("b"))
        val context = SongBucketContext(SongSortMode.Shop, null, offers)
        val (rows, headers) = SongQuickLinkBuckets.group(listOf(a, b, c, d), context)
        assertEquals(listOf("Leaving Tomorrow", "In Shop", "Not In Shop"), headers.map { it.label })
        assertEquals(listOf(0, 1, 2), headers.map { it.firstIndex })
        assertEquals(listOf("shop:leaving-tomorrow", "shop:in-shop", "shop:not-in-shop"), headers.map { it.id })
        assertEquals("fst.songs.shop-section.in-shop", headers[1].testTag)
        assertEquals(listOf(a, b, c, d), rows)
        assertTrue(SongQuickLinkBuckets.group(listOf(c, d), context).second.isEmpty())
        assertEquals(SongShopBucket.NotInShop, SongShopSections.bucket(c, offers))
    }

    @Test
    fun pipelinePausesShopChoicesWithoutValidatedData() {
        val input = SongListInputs(songs, sort = SongSortMode.Shop, general = SongGeneralFilter(shopUnavailable = false))
        val unloaded = SongListPipeline.run(input, sorter)
        assertEquals(SongSortMode.Title, unloaded.effectiveSort)
        assertEquals(4, unloaded.songs.size)
        assertTrue(unloaded.sortPaused!!.contains("until Item Shop data loads"))
        assertTrue(unloaded.shopFilterPaused!!.contains("Showing all songs"))
        assertFalse(unloaded.filtersApplied)
        assertEquals(2, unloaded.notices.size)

        val hidden = SongListPipeline.run(input.copy(hideShop = true, offers = emptyMap()), sorter)
        assertTrue(hidden.sortPaused!!.contains("hidden"))
        val mismatch = SongListPipeline.run(input.copy(shopPublicationMismatch = true), sorter)
        assertTrue(mismatch.sortPaused!!.contains("update together"))

        val offers = mapOf("b" to SongsFixtures.offer("b"), "c" to SongsFixtures.offer("c", leaving = true))
        val live = SongListPipeline.run(input.copy(offers = offers), sorter)
        assertEquals(SongSortMode.Shop, live.effectiveSort)
        assertEquals(listOf("b", "c"), live.songs.map { it.songId })
        assertTrue(live.notices.isEmpty())
        assertTrue(live.filtersApplied)
        assertEquals(listOf("In Shop", "Leaving Tomorrow"), live.headers.map { it.label })
        // A validated empty Shop gives an honest empty list.
        assertTrue(SongListPipeline.run(input.copy(offers = emptyMap()), sorter).songs.isEmpty())
    }

    @Test
    fun pipelineAppliesGeneralFiltersWithoutAPlayer() {
        val base = SongListInputs(songs.map { it.copy(doubleBassSupported = it.songId != "b") })
        val decade = SongListPipeline.run(base.copy(general = SongGeneralFilter(excludedDecades = setOf(2000))), sorter)
        assertEquals(listOf("b", "c"), decade.songs.map { it.songId }.sorted())
        assertTrue(decade.filtersApplied)
        assertTrue(decade.notices.isEmpty())
        val bass = SongListPipeline.run(base.copy(general = SongGeneralFilter(doubleBassSupported = false)), sorter)
        assertEquals(listOf("b"), bass.songs.map { it.songId })
        // Both Item Shop choices off: nothing, even before Shop data loads (web).
        val noShop = SongListPipeline.run(base.copy(general = SongGeneralFilter(shopAvailable = false, shopUnavailable = false)), sorter)
        assertTrue(noShop.songs.isEmpty())
        assertTrue(noShop.notices.isEmpty())
        // ...but a hidden Shop pauses the choice instead.
        val hidden = SongListPipeline.run(base.copy(hideShop = true, general = SongGeneralFilter(shopAvailable = false, shopUnavailable = false)), sorter)
        assertEquals(4, hidden.songs.size)
        assertTrue(hidden.shopFilterPaused!!.contains("hidden"))
        val notInShop = SongListPipeline.run(base.copy(general = SongGeneralFilter(shopAvailable = false), offers = mapOf("a" to SongsFixtures.offer("a"))), sorter)
        assertEquals(listOf("b", "c", "d"), notInShop.songs.map { it.songId }.sorted())
    }

    @Test
    fun pipelinePausesScoreFiltersUntilScoresApply() {
        val filter = SongPlayerScoreFilter(hasScores = setOf(Instrument.Lead))
        val scores: (String, Instrument) -> SongScoreDetail? = { id, _ -> if (id == "a") SongScoreDetail(1, isFullCombo = false) else null }
        val base = SongListInputs(songs, playerFilter = filter, hasPlayer = true, scores = scores)
        assertEquals(listOf("a"), SongListPipeline.run(base, sorter).songs.map { it.songId })
        fun reason(input: SongListInputs) = SongListPipeline.run(input, sorter).scoreFilterPaused!!
        assertTrue(reason(base.copy(visible = setOf(Instrument.Bass))).contains("hidden in Settings"))
        // No player: the filters don't apply and there's no notice (web).
        assertNull(SongListPipeline.run(base.copy(hasPlayer = false), sorter).scoreFilterPaused)
        assertEquals(4, SongListPipeline.run(base.copy(hasPlayer = false), sorter).songs.size)
        // Filter Invalid Scores no longer pauses: the scores are already the effective (next valid) ones.
        assertNull(SongListPipeline.run(base.copy(filterInvalidScores = true), sorter).scoreFilterPaused)
        assertTrue(reason(base.copy(scores = null)).contains("same update"))
        assertEquals(4, SongListPipeline.run(base.copy(scores = null), sorter).songs.size)
        assertNull(SongListPipeline.run(base.copy(playerFilter = SongPlayerScoreFilter()), sorter).scoreFilterPaused)
    }

    @Test
    fun yearSortUsesDecadeHeadersInsteadOfTheIndex() {
        assertTrue(SongSectionIndex.sections(songs, SongSortMode.Shop).isEmpty())
        assertTrue(SongSectionIndex.sections(songs, SongSortMode.Year).isEmpty())
        assertTrue(SongSectionIndex.chunk(emptyList()) { it.title }.isEmpty())
        val result = SongListPipeline.run(SongListInputs(songs + a.copy(songId = "u", year = null), sort = SongSortMode.Year), sorter)
        assertTrue(result.sections.isEmpty())
        assertEquals(listOf("Unknown Year", "1990s", "2000s", "2010s"), result.headers.map { it.label })
        assertEquals(listOf("year:unknown", "year:1990", "year:2000", "year:2010"), result.headers.map { it.id })
    }

    // endregion

    // region Drafts

    @Test
    fun sortDraftAppliesOnlyChanges() {
        val draft = SongSortDraft(SongSortMode.Year, false)
        assertFalse(draft.changed)
        val reset = draft.reset()
        assertEquals(SongSortMode.Title, reset.mode)
        assertTrue(reset.ascending)
        assertTrue(reset.changed)
        assertEquals(SongSortMode.entries.filter { it.group == SongSortGroup.Catalog }, SongSortDraft.modes(hideShop = false))
        assertFalse(SongSortMode.Shop in SongSortDraft.modes(hideShop = true))
    }

    @Test
    fun sortButtonStateNamesModeAndDirection() {
        assertEquals("Title, ascending", SongSortDraft.describe(SongSortMode.Title, true))
        assertEquals("Item Shop, descending", SongSortDraft.describe(SongSortMode.Shop, false))
        assertEquals("Max Score %, ascending", SongSortDraft.describe(SongSortMode.MaxDistance, true))
    }

    @Test
    fun filterDraftTracksChangesAndSanitizesHiddenCharts() {
        val visible = setOf(Instrument.Lead, Instrument.Bass)
        val saved = SongPlayerScoreFilter(hasScores = setOf(Instrument.Drums, Instrument.Lead))
        val draft = SongFilterDraft.from(SongFilter(), SongGeneralFilter(), saved, visible)
        assertFalse(draft.changed)
        assertTrue(draft.hasHiddenChecks)
        assertEquals(SongPlayerScoreFilter(hasScores = setOf(Instrument.Lead)), draft.result.third)
        val edited = draft.withInstrument(Instrument.Bass).withBucket(SongBucketKind.Intensity, 3, shown = false)
        assertEquals(SongFilter(Instrument.Bass, setOf(3)), edited.filter)
        assertEquals(setOf(3), edited.excluded(SongBucketKind.Intensity))
        assertTrue(edited.withBucket(SongBucketKind.Intensity, 3, shown = true).filter.excludedIntensities.isEmpty())
        assertTrue(edited.canApply)
        val stars = edited.withAllBuckets(SongBucketKind.Stars, SongStarsBucket.KEYS, shown = false)
        assertEquals(SongStarsBucket.KEYS.toSet(), stars.playerFilter.excludedStars)
        assertTrue(stars.withAllBuckets(SongBucketKind.Stars, SongStarsBucket.KEYS, shown = true).playerFilter.excludedStars.isEmpty())
        assertEquals(setOf(2), edited.withBucket(SongBucketKind.Season, 2, shown = false).playerFilter.excludedSeasons)
        assertEquals(setOf(10), edited.withBucket(SongBucketKind.Percentile, 10, shown = false).excluded(SongBucketKind.Percentile))
        val ok = draft.withInstrument(Instrument.Bass).withCheck(SongScoreFilterKind.HasFCs, Instrument.Bass, true).withAll(SongScoreFilterKind.MissingFCs, true)
        assertTrue(ok.canApply)
        assertTrue(ok.allOn(SongScoreFilterKind.MissingFCs))
        assertFalse(ok.allOn(SongScoreFilterKind.HasFCs))
        val general = draft.withGeneralBucket(SongGeneralBucketKind.Year, 1990, shown = false)
        assertEquals(setOf(1990), general.general.excludedDecades)
        assertTrue(general.changed)
        assertEquals(SongGeneralFilter(excludedDecades = setOf(1990)), general.result.second)
        assertTrue(general.withGeneralBucket(SongGeneralBucketKind.Year, 1990, shown = true).general.excludedDecades.isEmpty())
        val clearAll = draft.withAllGeneralBuckets(SongGeneralBucketKind.Duration, listOf(0, 1, 2), shown = false)
        assertEquals(setOf(0, 1, 2), clearAll.general.excludedDurations)
        assertTrue(clearAll.withAllGeneralBuckets(SongGeneralBucketKind.Duration, listOf(0, 1, 2), shown = true).general.excludedDurations.isEmpty())
        assertFalse(draft.copy(general = SongGeneralFilter(excludedDurations = setOf(42))).isValid)
        assertEquals(SongGeneralFilter(), clearAll.reset().general)
        val cleared = ok.reset()
        assertEquals(SongFilter(), cleared.filter)
        assertFalse(cleared.playerFilter.isActive)
        assertTrue(cleared.changed)
        assertEquals(SongFilter(Instrument.Lead), SongFilterDraft.from(SongFilter(Instrument.Lead), SongGeneralFilter(), null, visible).filter)
        assertEquals(SongFilter(), SongFilterDraft(filter = SongFilter(Instrument.Drums), visible = visible).result.first)
    }

    // endregion

    // region Row projection

    private fun detail(score: Long, fc: Boolean? = null) = SongScoreDetail(
        score, accuracy = 987_000.0, isFullCombo = fc, stars = 6, season = 15, difficulty = 3.0, rank = 3, totalEntries = 1000,
        lastPlayedAt = "2026-09-01T12:00:00Z",
    )

    @Test
    fun chipStatusesFollowChartAndScore() {
        val facts = mapOf(
            Instrument.Lead to ChartScoreFacts(10, true),
            Instrument.Bass to ChartScoreFacts(10, false),
            Instrument.Drums to ChartScoreFacts(0, true),
            Instrument.Vocals to ChartScoreFacts(10, true),
        )
        val badges = SongInstrumentStatusPolicy.badges(a, setOf(Instrument.Lead, Instrument.Bass, Instrument.Drums, Instrument.Vocals, Instrument.ProBass, Instrument.Karaoke)) { facts[it] }
        assertEquals(
            listOf(
                SongInstrumentStatus.FullCombo, SongInstrumentStatus.Scored, SongInstrumentStatus.InconsistentFullCombo,
                SongInstrumentStatus.Unavailable, SongInstrumentStatus.NoScore, SongInstrumentStatus.Unavailable,
            ),
            badges.map { it.status },
        )
        assertEquals("Lead, full combo", badges[0].announcement)
        assertEquals(SongInstrumentStatus.NoScore, SongInstrumentStatusPolicy.status(a, Instrument.Lead, ChartScoreFacts(0, null)))
        assertTrue(SongInstrumentStatusPolicy.showsChips(true, true, true, null, setOf(Instrument.Lead)))
        assertFalse(SongInstrumentStatusPolicy.showsChips(true, true, true, Instrument.Lead, setOf(Instrument.Lead)))
        assertFalse(SongInstrumentStatusPolicy.showsChips(true, false, true, null, setOf(Instrument.Lead)))
        assertFalse(SongInstrumentStatusPolicy.showsChips(true, true, false, null, setOf(Instrument.Lead)))
        assertFalse(SongInstrumentStatusPolicy.showsChips(false, true, true, null, setOf(Instrument.Lead)))
        assertFalse(SongInstrumentStatusPolicy.showsChips(true, true, true, null, emptySet()))
    }

    @Test
    fun metadataPillsFollowSettingsOrderWithLastPlayedLast() {
        val order = listOf(MetadataField.LastPlayed, MetadataField.Season, MetadataField.Score, MetadataField.Percentage, MetadataField.Percentile, MetadataField.Stars, MetadataField.Intensity, MetadataField.Difficulty)
        val pills = SongMetadataPolicy.pills(detail(95_198), Instrument.Lead, a, 15, order, order.toSet(), Locale.US, ZoneOffset.UTC)
        assertEquals(
            listOf(MetadataField.Season, MetadataField.Score, MetadataField.Percentage, MetadataField.Percentile, MetadataField.Stars, MetadataField.Intensity, MetadataField.Difficulty, MetadataField.LastPlayed),
            pills.map { it.kind },
        )
        val byKind = pills.associateBy { it.kind }
        assertEquals("95,198", byKind.getValue(MetadataField.Score).text)
        assertEquals("98.7%", byKind.getValue(MetadataField.Percentage).text)
        assertTrue(byKind.getValue(MetadataField.Percentage).tint != null)
        assertEquals("Top 1%", byKind.getValue(MetadataField.Percentile).text)
        assertEquals(SongPercentileTier.TopOne, byKind.getValue(MetadataField.Percentile).percentile)
        assertTrue(byKind.getValue(MetadataField.Stars).goldStars)
        assertEquals("5 gold stars", byKind.getValue(MetadataField.Stars).announcement)
        assertTrue(byKind.getValue(MetadataField.Season).currentSeason)
        assertEquals("Current season 15", byKind.getValue(MetadataField.Season).announcement)
        assertEquals(3.0, byKind.getValue(MetadataField.Intensity).intensityRaw!!, 0.0)
        assertEquals("X", byKind.getValue(MetadataField.Difficulty).text)
        assertEquals("Expert difficulty", byKind.getValue(MetadataField.Difficulty).announcement)
        assertEquals("Last played 1 Sep 2026", byKind.getValue(MetadataField.LastPlayed).text)
        assertTrue(SongMetadataPolicy.pills(detail(0), Instrument.Lead, a, 15, order).isEmpty())
    }

    @Test
    fun metadataFullComboAndOptionalFields() {
        val fc = SongMetadataPolicy.pills(detail(10, fc = true), Instrument.Lead, a, 14, listOf(MetadataField.Percentage, MetadataField.Season), locale = Locale.US)
        assertEquals("98.7% FC", fc[0].text)
        assertTrue(fc[0].fullCombo)
        assertEquals("Season 15", fc[1].announcement)
        val hiddenPct = SongMetadataPolicy.pills(detail(10, fc = true), Instrument.Lead, a, null, MetadataField.entries, setOf(MetadataField.Score), Locale.US)
        assertEquals(listOf("10", "FC"), hiddenPct.map { it.text })
        assertEquals("Full combo", hiddenPct[1].announcement)
        val noAcc = SongMetadataPolicy.pills(detail(10, fc = true).copy(accuracy = null), Instrument.Lead, a, null, listOf(MetadataField.Percentage))
        assertEquals("Full combo, accuracy unavailable", noAcc.single().announcement)
        val sparse = SongScoreDetail(10, stars = 1, difficulty = 1.5, season = 0, rank = 300, totalEntries = 1000, lastPlayedAt = "garbage")
        val pills = SongMetadataPolicy.pills(sparse, Instrument.Lead, c, null, MetadataField.entries)
        assertEquals(listOf(MetadataField.Score, MetadataField.Percentile, MetadataField.Stars, MetadataField.LastPlayed), pills.map { it.kind })
        assertEquals("Top 30%", pills[1].text)
        assertEquals("1 star", pills[2].announcement)
        assertEquals("Last played date unavailable", pills[3].text)
        assertEquals(SongPercentileTier.TopFive, SongMetadataPolicy.pills(detail(10).copy(rank = 50), Instrument.Lead, a, null, listOf(MetadataField.Percentile)).single().percentile)
        assertEquals("3 stars", SongMetadataPolicy.pills(detail(10).copy(stars = 3), Instrument.Lead, a, null, listOf(MetadataField.Stars)).single().announcement)
        assertNull(SongMetadataPolicy.percentileBucket(0, 10))
        assertNull(SongMetadataPolicy.percentileBucket(1, null))
        listOf(0 to "E", 1 to "M", 2 to "H").forEach { (level, letter) ->
            assertEquals(letter, SongMetadataPolicy.pills(detail(10).copy(difficulty = level.toDouble()), Instrument.Lead, a, null, listOf(MetadataField.Difficulty)).single().text)
        }
    }

    @Test
    fun projectorChoosesChipsMetadataOrState() {
        val scores = mapOf(("a" to Instrument.Lead) to detail(100, fc = true), ("a" to Instrument.Bass) to detail(50))
        val available = SongScoreSource(hasPlayer = true, detail = { id, chart -> scores[id to chart] })
        val offers = mapOf("a" to SongsFixtures.offer("a", isNew = true))
        val settings = AppSettings()

        val anonymous = SongRowProjector(settings, SongFilter(Instrument.Lead), 15, offers, SongScoreSource.NONE).project(a)
        assertEquals(ShopHighlight.New, anonymous.highlight)
        assertEquals(Instrument.Lead, anonymous.chart)
        assertEquals(3.0, anonymous.chartRaw!!, 0.0)
        assertTrue(anonymous.announcement.contains("Item Shop: New"))
        assertTrue(anonymous.announcement.contains("Lead, Difficulty 4 of 7"))

        val chips = SongRowProjector(settings, SongFilter(), 15, null, available).project(a)
        assertEquals(9, chips.chips.size)
        assertTrue(chips.announcement.contains("Lead, full combo"))

        val metadata = SongRowProjector(settings.copy(showInstrumentIcons = false), SongFilter(), 15, null, available).project(a)
        assertEquals(Instrument.Lead, metadata.chart)
        assertFalse(metadata.namesChart)
        assertTrue(metadata.metadata.isNotEmpty())
        assertNull(metadata.scoreState)

        val bass = SongRowProjector(settings, SongFilter(Instrument.Bass), 15, null, available).project(a)
        assertTrue(bass.namesChart)
        assertTrue(bass.announcement.contains("Bass chart"))

        val none = SongRowProjector(settings, SongFilter(Instrument.Drums), 15, null, available).project(a)
        assertEquals("No score", none.scoreState)
        assertEquals(1.0, none.chartRaw!!, 0.0)
        val uncharted = SongRowProjector(settings, SongFilter(Instrument.Lead), 15, null, available).project(c)
        assertEquals("No Lead chart", uncharted.scoreState)

        // Under Filter Invalid Scores the chips show the effective scores.
        val invalid = SongRowProjector(settings.copy(filterInvalidScores = true), SongFilter(), 15, null, available).project(a)
        assertNull(invalid.scoreState)
        assertFalse(invalid.chips.isEmpty())

        val syncing = SongRowProjector(settings, SongFilter(), 15, null, SongScoreSource.SYNCING).project(a)
        assertEquals("Scores syncing", syncing.scoreState)
        assertTrue(syncing.announcement.endsWith("Scores syncing"))
        assertEquals("Scores unavailable", SongScoreSource.failed("x").rowState)
        assertEquals("Player scores unavailable: x", SongScoreSource.failed("x").notice)
        assertNull(SongScoreSource.PAUSED.facts)
        assertEquals(ChartScoreFacts(100, true, stars = 6, season = 15, rank = 3, totalEntries = 1000), available.facts!!("a", Instrument.Lead))

        val hiddenFilter = SongRowProjector(settings.copy(visibleInstruments = setOf(Instrument.Bass)), SongFilter(Instrument.Lead), 15, null, SongScoreSource.NONE).project(a)
        assertNull(hiddenFilter.chart)
    }

    // endregion
}
