package com.festivalscoretracker.android.core.model

// region Instrument

/**
 * Exact service identifiers and labels for the nine solo instrument charts.
 *
 * Mirrors Apple's `Instrument` (`FestivalCore/SongCatalog.swift`); declaration
 * order is the web's canonical chart order and drives every chart list.
 *
 * @property wireId Service instrument key used in URLs and `maxScores`.
 * @property label User-facing name matching the web client.
 */
enum class Instrument(val wireId: String, val label: String) {
    Lead("Solo_Guitar", "Lead"),
    Bass("Solo_Bass", "Bass"),
    Drums("Solo_Drums", "Drums"),
    Vocals("Solo_Vocals", "Tap Vocals"),
    ProLead("Solo_PeripheralGuitar", "Pro Lead"),
    ProBass("Solo_PeripheralBass", "Pro Bass"),
    Karaoke("Solo_PeripheralVocals", "Karaoke"),
    ProCymbals("Solo_PeripheralCymbals", "Pro Drums + Cymbals"),
    ProDrums("Solo_PeripheralDrums", "Pro Drums");

    /**
     * Resolve the bundled icon resource name, preferring the keys artwork for
     * Lead/Pro Lead when the song's controller signature is `Keyboard`.
     *
     * @param keyboard Whether the song uses the keyboard signature.
     * @return Drawable resource name without extension.
     */
    fun iconName(keyboard: Boolean = false): String {
        val file = when (this) {
            Lead -> if (keyboard) "keys" else "guitar"
            Bass -> "bass"
            Drums -> "drums"
            Vocals -> "vocals"
            ProLead -> if (keyboard) "pro_keys" else "pro_guitar"
            ProBass -> "pro_bass"
            Karaoke -> "peripheral_vocals"
            ProCymbals -> "peripheral_cymbals"
            ProDrums -> "peripheral_drums"
        }
        return "instrument_$file"
    }

    companion object {
        /**
         * Parse a service instrument key.
         *
         * @param wireId Value such as `Solo_Guitar`.
         * @return The matching chart, or null for an unknown key.
         */
        fun fromWireId(wireId: String?): Instrument? = entries.firstOrNull { it.wireId == wireId }
    }
}

// endregion
