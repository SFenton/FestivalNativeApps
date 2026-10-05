package com.festivalscoretracker.android.testing

/**
 * Synthetic catalogue for the Songs section index (`fst.songs.section-index.*`): two songs in
 * each of the 27 title sections (#, A–Z), three artist sections (A, M, Z) and three decades
 * (1990s, 2000s, 2010s). Song `s-<section>-<n>` is the n-th song of title section `section`.
 */
object SectionIndexFixtures {
    /** Title section labels in list order. */
    val labels: List<String> = listOf("#") + ('A'..'Z').map { it.toString() }

    /**
     * Artist of every song in a title section.
     *
     * @param section Title section index.
     * @return Artist name.
     */
    fun artistOf(section: Int): String = listOf("Alpha Artist", "Mid Artist", "Zulu Artist")[section % 3]

    /** `GET /api/songs` body. */
    val catalogueJson: String
        get() {
            val songs = labels.flatMapIndexed { section, label ->
                (1..2).map { n ->
                    val title = if (label == "#") "$n$section Tune" else "${label}tune $n"
                    """{"songId":"s-$section-$n","title":"$title","artist":"${artistOf(section)}","year":${1990 + section % 3 * 10},"durationSeconds":180,"difficulty":{"guitar":2}}"""
                }
            }
            return """{"count":${songs.size},"currentSeason":15,"songs":[${songs.joinToString(",")}]}"""
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
