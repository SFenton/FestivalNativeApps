package com.festivalscoretracker.android.testing

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.profile.PlayerProfilePayload
import com.festivalscoretracker.android.core.profile.PlayerProfileResponse
import com.festivalscoretracker.android.core.profile.PlayerProfileState
import com.festivalscoretracker.android.core.profile.PlayerScore
import com.festivalscoretracker.android.core.shop.ShopPayload
import com.festivalscoretracker.android.core.shop.ShopResponse
import com.festivalscoretracker.android.core.shop.ShopSong

// region Songs fixtures

/** Synthetic Shop, Paths and player-score fixtures (made-up IDs, titles and URLs). */
object SongsFixtures {
    /** Official-shape synthetic Shop URL. */
    fun shopUrl(slug: String) = "https://www.fortnite.com/item-shop/jam-tracks/$slug"

    /**
     * One offer.
     *
     * @param id Song ID.
     * @param leaving Leaving tomorrow.
     * @param isNew New.
     * @return Offer.
     */
    fun offer(id: String, leaving: Boolean = false, isNew: Boolean = false) =
        ShopSong(id, "Title $id", "Artist $id", 2020, null, shopUrl("slug-$id"), leaving, isNew)

    /**
     * Shop payload.
     *
     * @param offers Offers.
     * @param observed Observed publication.
     * @return Payload.
     */
    fun shop(vararg offers: ShopSong, observed: Int = 7): ShopPayload {
        val response = ShopResponse(offers.size, offers.toList())
        return ShopPayload(response, response.sortedSongs(), observed, observed)
    }

    /** `/api/shop` JSON with an extra key the decoder must skip. */
    val shopJson = """
        {"count":3,"lastUpdated":"2026-09-28T00:00:00Z","newSongs":["s-beta"],"extra":1,"songs":[
          {"songId":"s-beta","title":"Beta Song","artist":"Band Two","year":2019,"albumArt":"b.jpg","shopUrl":"${shopUrl("beta")}","leavingTomorrow":false,"isNew":true},
          {"songId":"s-alpha","title":"Alpha Tune","artist":"Band One","shopUrl":"${shopUrl("alpha")}","leavingTomorrow":true,"isNew":false},
          {"songId":"s-x","title":"Alpha Tune","artist":"Other","shopUrl":"${shopUrl("x")}"}
        ]}
    """.trimIndent()

    /**
     * `/api/songs` JSON long enough to scroll: [count] songs over [count] years, so the Year sort has
     * several Quick Links sections (issues #52/#160 pinned page controls).
     *
     * @param count Songs (`s-1` … `s-<count>`).
     * @return Catalogue JSON.
     */
    fun scrollingCatalogueJson(count: Int = 40): String {
        val songs = (1..count).joinToString(",") { i ->
            """{"songId":"s-$i","title":"${'A' + (i - 1) / 2} Song ${"%02d".format(i)}","artist":"Band $i","year":${1980 + i},"durationSeconds":120,"difficulty":{"guitar":1}}"""
        }
        return """{"count":$count,"currentSeason":15,"songs":[$songs]}"""
    }

    /** Standard transport serving [scrollingCatalogueJson] at publication 7. */
    fun scrollingCatalogueTransport(): FakeTransport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { scrollingCatalogueJson() }
    }

    /** Schema-2 path JSON (Expert) with one note-anchored and one start-note activation. */
    val pathJson = """
        {"schemaVersion":2,"songName":"Alpha Tune","artist":"Band One","charter":"Synthetic","difficulty":"expert","totalScore":123456,
         "pathSummary":"2(+1) 1","activations":[
           {"startBeat":10,"endBeat":14,"activationBeat":10.01,"activationSeconds":65.4321,"odAtActivation":0.5,"scoreBeforeActivation":45000,"instruction":"Activate after the chord"},
           {"startBeat":20,"endBeat":22,"startNotes":[{"beat":20,"seconds":90.5,"cumulativeScore":90000,"noteValue":50,"odPercent":0.25,"isSpGranting":false}]},
           {"startBeat":30,"endBeat":31,"startSeconds":120}
         ],
         "notes":[
           {"beat":10,"seconds":65.4,"frets":{"green":0,"red":0}},
           {"beat":10.01,"frets":{"open":0}},
           {"beat":20,"frets":{"yellow":1.5}},
           {"beat":29,"frets":{"blue":0}}
         ]}
    """.trimIndent()

    /**
     * Minimal valid PNG header with the given size.
     *
     * @param width Width.
     * @param height Height.
     * @return Bytes.
     */
    fun png(width: Int = 100, height: Int = 200): ByteArray {
        val bytes = ByteArray(40)
        byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A).copyInto(bytes)
        byteArrayOf(0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52).copyInto(bytes, 8)
        fun put(at: Int, value: Int) {
            bytes[at] = (value ushr 24).toByte()
            bytes[at + 1] = (value ushr 16).toByte()
            bytes[at + 2] = (value ushr 8).toByte()
            bytes[at + 3] = value.toByte()
        }
        put(16, width)
        put(20, height)
        return bytes
    }

    /**
     * One compact player score.
     *
     * @param songId Song.
     * @param instrument Chart.
     * @param score Score.
     * @param fc Full combo.
     * @return Score.
     */
    fun score(songId: String, instrument: Instrument, score: Int, fc: Boolean? = null, rank: Int? = 3, total: Int? = 1000) = PlayerScore(
        songId = songId,
        instrumentCode = "%02x".format(1 shl instrument.ordinal),
        score = score,
        rawAccuracy = 987.0,
        isFullCombo = fc,
        stars = 6,
        season = 15,
        difficulty = 3.0,
        rank = rank,
        totalEntries = total,
        lastPlayedAt = "2026-09-01T12:00:00Z",
    )

    /**
     * Available profile payload.
     *
     * @param scores Scores.
     * @param observed Observed publication.
     * @param state Available or syncing.
     * @return Payload.
     */
    fun profile(vararg scores: PlayerScore, observed: Int = 7, state: PlayerProfileState = PlayerProfileState.Available) = PlayerProfilePayload(
        PlayerProfileResponse(Fixtures.ACCOUNT_A, "Synthetic Player", scores.size, scores.toList()),
        state,
        observed,
        observed,
    )
}

// endregion
