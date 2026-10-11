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

    /** Songs in each decade and minute bucket. */
    const val SECTION_SIZE = 10

    /** `GET /api/songs` body. */
    val catalogueJson: String
        get() {
            val songs = (0 until SIZE).joinToString(",") { i ->
                val section = i / SECTION_SIZE
                """{"songId":"s-$i","title":"Song $i","artist":"Artist","year":${1970 + section * 10},"durationSeconds":${90 + section * 60},"difficulty":{"guitar":2}}"""
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

    /**
     * A catalogue with chosen section sizes (issue #560): section `i` holds [sizes]`[i]` songs
     * (at most ten), `s-<10i>` onward, so song `s-<n>` is still in section `n / 10`. Short last
     * sections make the list's last scroll position fall inside a section push.
     *
     * @param sizes Songs per section, in list order (up to four sections).
     * @return `GET /api/songs` body.
     */
    fun sectionsCatalogueJson(sizes: List<Int>): String {
        val ids = sizes.flatMapIndexed { section, size -> (section * SECTION_SIZE) until (section * SECTION_SIZE + size) }
        val songs = ids.joinToString(",") { i ->
            val section = i / SECTION_SIZE
            """{"songId":"s-$i","title":"Song $i","artist":"Artist","year":${1970 + section * 10},"durationSeconds":${90 + section * 60},"difficulty":{"guitar":2}}"""
        }
        return """{"count":${ids.size},"currentSeason":15,"songs":[$songs]}"""
    }

    /**
     * A standard transport serving [sectionsCatalogueJson] for publication 7.
     *
     * @param sizes Songs per section.
     * @return Fixture transport.
     */
    fun sectionsTransport(sizes: List<Int>): FakeTransport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { sectionsCatalogueJson(sizes) }
    }
}
