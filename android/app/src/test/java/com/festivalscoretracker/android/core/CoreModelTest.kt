package com.festivalscoretracker.android.core

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.LeaderboardEntry
import com.festivalscoretracker.android.core.model.LeaderboardPaging
import com.festivalscoretracker.android.core.model.LeaderboardResponse
import com.festivalscoretracker.android.core.model.ProfileSearchText
import com.festivalscoretracker.android.core.model.Publication
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.model.SongDifficulty
import com.festivalscoretracker.android.core.model.SongsResponse
import com.festivalscoretracker.android.core.settings.SettingsCodec
import com.festivalscoretracker.android.testing.Fixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class CoreModelTest {
    // region Instrument and song

    @Test
    fun instrumentWireIdsAndIconsMatchApple() {
        assertEquals(9, Instrument.entries.size)
        assertEquals(Instrument.ProCymbals, Instrument.fromWireId("Solo_PeripheralCymbals"))
        assertNull(Instrument.fromWireId("Solo_Unknown"))
        assertNull(Instrument.fromWireId(null))
        val icons = Instrument.entries.map { it.iconName() } + listOf(Instrument.Lead.iconName(true), Instrument.ProLead.iconName(true))
        assertEquals(
            listOf(
                "instrument_guitar", "instrument_bass", "instrument_drums", "instrument_vocals", "instrument_pro_guitar",
                "instrument_pro_bass", "instrument_peripheral_vocals", "instrument_peripheral_cymbals", "instrument_peripheral_drums",
                "instrument_keys", "instrument_pro_keys",
            ),
            icons,
        )
    }

    @Test
    fun chartedValueRejectsSentinelNegativeAndNonFinite() {
        val difficulty = SongDifficulty(guitar = 3.0, bass = 99.0, drums = -1.0, vocals = Double.NaN, proGuitar = 0.0, proBass = 1.0, proDrums = 2.0, proCymbals = 4.0, proVocals = 6.0)
        assertEquals(3.0, difficulty.chartedValue(Instrument.Lead)!!, 0.0)
        assertNull(difficulty.chartedValue(Instrument.Bass))
        assertNull(difficulty.chartedValue(Instrument.Drums))
        assertNull(difficulty.chartedValue(Instrument.Vocals))
        assertEquals(0.0, difficulty.chartedValue(Instrument.ProLead)!!, 0.0)
        assertEquals(1.0, difficulty.chartedValue(Instrument.ProBass)!!, 0.0)
        assertEquals(2.0, difficulty.chartedValue(Instrument.ProDrums)!!, 0.0)
        assertEquals(4.0, difficulty.chartedValue(Instrument.ProCymbals)!!, 0.0)
        assertEquals(6.0, difficulty.chartedValue(Instrument.Karaoke)!!, 0.0)
        assertNull(SongDifficulty().chartedValue(Instrument.Lead))
    }

    @Test
    fun songDerivedFields() {
        val song = Fixtures.song("a", "A").copy(sig = "Keyboard", maxScores = mapOf("Solo_Guitar" to 100, "Solo_Bass" to 0))
        assertTrue(song.usesKeyboardIcon)
        assertTrue(song.supports(Instrument.Lead))
        assertFalse(song.supports(Instrument.Vocals))
        assertFalse(song.copy(difficulty = null).supports(Instrument.Lead))
        assertEquals(100, song.maxScore(Instrument.Lead))
        assertNull(song.maxScore(Instrument.Bass))
        assertNull(song.maxScore(Instrument.Drums))
        assertEquals("3:20", song.formattedDuration)
        assertEquals("1:02:05", song.copy(durationSeconds = 3725).formattedDuration)
        assertEquals("0:09", song.copy(durationSeconds = 9).formattedDuration)
        assertNull(song.copy(durationSeconds = 0).formattedDuration)
        assertNull(song.copy(durationSeconds = null).formattedDuration)
        assertEquals("Synthetic Artist · 2020 · 3:20", song.subtitle)
        assertEquals("Synthetic Artist", song.copy(year = 0, durationSeconds = null).subtitle)
    }

    @Test
    fun songsResponseValidation() {
        val songs = listOf(Fixtures.song("a", "A"))
        SongsResponse(1, 15, songs).validate()
        assertThrows(FestivalApiException.InvalidCatalogue::class.java) { SongsResponse(2, null, songs).validate() }
        assertThrows(FestivalApiException.InvalidCatalogue::class.java) { SongsResponse(-1, null, emptyList()).validate() }
        assertThrows(FestivalApiException.InvalidCatalogue::class.java) { SongsResponse(1, null, listOf(Fixtures.song("", "A"))).validate() }
        assertThrows(FestivalApiException.InvalidCatalogue::class.java) { SongsResponse(1, null, listOf(Fixtures.song("a", ""))).validate() }
    }

    // endregion

    // region Publication and leaderboard

    @Test
    fun publicationValidationAndPinning() {
        val publication = Publication(1, 5, 9, readyForPinning = true, pinningEnabled = true)
        publication.validate()
        assertTrue(publication.pins)
        assertFalse(publication.copy(pinningEnabled = false).pins)
        assertFalse(publication.copy(readyForPinning = false).pins)
        assertThrows(FestivalApiException.InvalidPublication::class.java) { publication.copy(contractVersion = 0).validate() }
        assertThrows(FestivalApiException.InvalidPublication::class.java) { publication.copy(publicationId = 0).validate() }
        assertThrows(FestivalApiException.InvalidPublication::class.java) { publication.copy(publishedScrapeId = 0).validate() }
    }

    @Test
    fun leaderboardPagingAndValidation() {
        val entry = LeaderboardEntry("x", "P", 10, 1)
        val board = LeaderboardResponse("s", "Solo_Guitar", 1, 60, 51, listOf(entry))
        assertEquals(3, board.pageCount())
        assertEquals(6, board.pageCount(10))
        assertEquals(3, board.copy(localEntries = null).pageCount())
        assertEquals(1, board.copy(localEntries = 0).pageCount())
        board.validate("s", Instrument.Lead, 10)
        assertThrows(FestivalApiException.InvalidLeaderboard::class.java) { board.validate("other", Instrument.Lead, 10) }
        assertThrows(FestivalApiException.InvalidLeaderboard::class.java) { board.validate("s", Instrument.Bass, 10) }
        assertThrows(FestivalApiException.InvalidLeaderboard::class.java) { board.copy(count = 2).validate("s", Instrument.Lead, 10) }
        assertThrows(FestivalApiException.InvalidLeaderboard::class.java) { board.validate("s", Instrument.Lead, 0) }
        assertThrows(FestivalApiException.InvalidLeaderboard::class.java) { board.copy(totalEntries = -1).validate("s", Instrument.Lead, 10) }
        assertThrows(FestivalApiException.InvalidLeaderboard::class.java) { board.copy(localEntries = -1).validate("s", Instrument.Lead, 10) }
        assertEquals(1, LeaderboardPaging.corrected(0, 5))
        assertEquals(5, LeaderboardPaging.corrected(9, 5))
        assertEquals(1, LeaderboardPaging.corrected(3, 0))
        assertEquals(2, LeaderboardPaging.pageForRank(26))
        assertEquals(1, LeaderboardPaging.pageForRank(25))
        assertEquals(1, LeaderboardPaging.pageForRank(0))
        assertEquals(1, LeaderboardPaging.pageForRank(5, 0))
    }

    // endregion

    // region Player identity

    @Test
    fun profileSearchValidation() {
        assertTrue(ProfileSearchText.isValidAccountId(Fixtures.ACCOUNT_A))
        assertTrue(ProfileSearchText.isValidAccountId(Fixtures.ACCOUNT_A.uppercase()))
        assertFalse(ProfileSearchText.isValidAccountId("xyz"))
        assertTrue(ProfileSearchText.isValidQuery("ab"))
        assertFalse(ProfileSearchText.isValidQuery("a"))
        assertFalse(ProfileSearchText.isValidQuery(" ab"))
        assertFalse(ProfileSearchText.isValidQuery("a\u0007b"))
        assertFalse(ProfileSearchText.isValidQuery("a‮b"))
        assertFalse(ProfileSearchText.isValidQuery("a⁧b"))
        assertFalse(ProfileSearchText.isValidQuery("x".repeat(201)))
    }

    @Test
    fun selectedPlayerInitialsAndValidation() {
        assertEquals("SP", SelectedPlayer(Fixtures.ACCOUNT_A, "synthetic player").initials)
        assertEquals("S", SelectedPlayer(Fixtures.ACCOUNT_A, "synthetic").initials)
        assertEquals("AB", SelectedPlayer(Fixtures.ACCOUNT_A, "a.b_c").initials)
        assertEquals("?", SelectedPlayer(Fixtures.ACCOUNT_A, "  ").initials)
        assertEquals("Name", SelectedPlayer.validated(Fixtures.ACCOUNT_A, " Name ")?.displayName)
        assertNull(SelectedPlayer.validated("bad", "Name"))
        assertNull(SelectedPlayer.validated(Fixtures.ACCOUNT_A, " "))
    }

    // endregion

    // region Errors and settings codec

    @Test
    fun errorMessagesNeverExposeServerText() {
        assertEquals("That song or chart is no longer available.", FestivalApiException.HttpStatus(404).message)
        assertEquals("Too many requests. Try again shortly.", FestivalApiException.HttpStatus(429).message)
        assertEquals("The service is temporarily unavailable. Try again.", FestivalApiException.HttpStatus(500).message)
        assertEquals("The service could not load this content (HTTP 418).", FestivalApiException.HttpStatus(418).message)
        assertEquals("Scores are updating. Try again shortly.", FestivalApiException.PublicReadFrozen("scrape", "30").message)
        assertEquals("The service is temporarily unavailable. Try again.", FestivalApiException.PublicReadFrozen("maintenance", null).message)
        listOf(
            FestivalApiException.InsecureBaseUrl(), FestivalApiException.InvalidPublication(), FestivalApiException.InvalidResponse(),
            FestivalApiException.InvalidResource(), FestivalApiException.InvalidCatalogue(), FestivalApiException.InvalidLeaderboard(),
            FestivalApiException.InvalidSearchQuery(), FestivalApiException.UnexpectedNotModified(), FestivalApiException.Unavailable(null),
            FestivalApiException.Syncing(), FestivalApiException.ForbiddenRequest(),
        ).forEach { assertTrue(it.message!!.isNotBlank()) }
    }

    @Test
    fun instrumentSetCodecRoundTripsAndToleratesUnknownTokens() {
        val set = setOf(Instrument.ProDrums, Instrument.Lead)
        val encoded = SettingsCodec.encodeInstruments(set)
        assertEquals("Solo_Guitar,Solo_PeripheralDrums", encoded)
        assertEquals(set, SettingsCodec.decodeInstruments(encoded))
        assertEquals(Instrument.entries.toSet(), SettingsCodec.decodeInstruments(null))
        assertEquals(emptySet<Instrument>(), SettingsCodec.decodeInstruments(""))
        assertEquals(setOf(Instrument.Bass), SettingsCodec.decodeInstruments("Solo_Bass, Solo_Removed"))
    }

    // endregion
}
