package com.festivalscoretracker.android.data

import java.io.StringReader
import java.io.File
import java.net.URI
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Test

/** Host-side fixture, publication-cache and transport-policy checks. */
class SongCatalogTest {
    private val valid = """{"publication":"Preview","songs":[
        {"id":"a","title":"First","artist":"Artist","difficulty":1},
        {"id":"b","title":"Last","artist":"Artist","difficulty":7}]}"""

    @Test fun decodesBothDifficultyBounds() {
        val result = SongCatalogDecoder.decode(StringReader(valid))
        assertEquals("Preview", result.publication)
        assertEquals(listOf(1, 7), result.songs.map(Song::difficulty))
    }

    @Test fun bundledFixtureMatchesDecoderContract() {
        val fixture = File("src/main/assets/songs.json")
        val result = fixture.bufferedReader().use(SongCatalogDecoder::decode)
        assertEquals(2, result.songs.size)
    }

    @Test fun rejectsInvalidOrDuplicateSongs() {
        assertThrows(IllegalArgumentException::class.java) {
            SongCatalogDecoder.decode(StringReader(valid.replace("\"difficulty\":7", "\"difficulty\":8")))
        }
        assertThrows(IllegalArgumentException::class.java) {
            SongCatalogDecoder.decode(StringReader(valid.replace("\"id\":\"b\"", "\"id\":\"a\"")))
        }
        assertThrows(IllegalStateException::class.java) {
            SongCatalogDecoder.decode(StringReader(valid.replace("\"difficulty\":7", "\"difficulty\":3.5")))
        }
        assertThrows(IllegalStateException::class.java) {
            SongCatalogDecoder.decode(StringReader(valid.replace("\"title\":\"First\"", "\"title\":42")))
        }
    }

    @Test fun cachePinsThenExpiresAndInvalidates() {
        var time = 0L
        var loads = 0
        val repository = SongCatalogRepository(
            CatalogSource {
                loads++
                SongCatalog("version $loads", emptyList())
            },
            MonotonicClock { time },
            100,
        )
        val first = repository.get()
        time = 99
        assertSame(first, repository.get())
        time = 100
        assertEquals("version 2", repository.get().publication)
        repository.invalidate()
        assertEquals("version 3", repository.get().publication)
        assertEquals(3, loads)
    }

    @Test fun failedReloadDoesNotReturnStaleCatalog() {
        var time = 0L
        val repository = SongCatalogRepository(
            CatalogSource {
                if (time > 0) error("fixture unavailable")
                SongCatalog("initial", emptyList())
            },
            MonotonicClock { time },
            10,
        )
        repository.get()
        time = 10
        assertThrows(IllegalStateException::class.java) { repository.get() }
    }

    @Test fun transportRejectsNonFixtureDebugAndInsecureRelease() {
        TransportPolicy(URI("http://10.0.2.2:8080/"), true)
        TransportPolicy(URI("https://festivalscoretracker.com/"), false)
        assertThrows(IllegalArgumentException::class.java) {
            TransportPolicy(URI("https://festivalscoretracker.com/"), true)
        }
        assertThrows(IllegalArgumentException::class.java) {
            TransportPolicy(URI("http://festivalscoretracker.com/"), false)
        }
    }
}
