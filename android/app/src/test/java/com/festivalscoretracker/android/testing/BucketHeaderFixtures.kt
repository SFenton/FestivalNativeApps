package com.festivalscoretracker.android.testing

/**
 * Synthetic catalogue for the Songs bucket headers (issues #91, #189): forty songs, ten per
 * decade (1970s–2000s, tokens `1970` … `2000`) and ten per minute bucket (1–2 … 4–5 Minutes,
 * tokens `1to2` … `4to5`), so every Year or Duration section is taller than a phone screen and
 * rows scroll under a pinned header. Song `s-<n>` is in decade and minute bucket `n / 10`.
 */
object BucketHeaderFixtures {
    /** Songs in the catalogue. */
    const val SIZE = 40

    /** `GET /api/songs` body. */
    val catalogueJson: String
        get() {
            val songs = (0 until SIZE).joinToString(",") { i ->
                """{"songId":"s-$i","title":"Song $i","artist":"Artist","year":${1970 + i / 10 * 10},"durationSeconds":${90 + i / 10 * 60},"difficulty":{"guitar":2}}"""
            }
            return """{"count":$SIZE,"currentSeason":15,"songs":[$songs]}"""
        }

    /**
     * A standard transport serving [catalogueJson] for publication 7.
     *
     * @return Fixture transport.
     */
    fun transport(): FakeTransport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { catalogueJson }
    }
}
