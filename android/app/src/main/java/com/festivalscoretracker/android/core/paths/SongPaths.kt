package com.festivalscoretracker.android.core.paths

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import java.text.NumberFormat
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToLong
import kotlinx.serialization.Serializable

// region Difficulty

/**
 * CHOpt difficulties in the public path route (Apple `PathDifficulty`).
 *
 * @property wireName URL segment.
 * @property label Display label.
 */
enum class PathDifficulty(val wireName: String, val label: String) {
    Easy("easy", "Easy"),
    Medium("medium", "Medium"),
    Hard("hard", "Hard"),
    Expert("expert", "Expert"),
}

/** Which charts have CHOpt paths (Karaoke has none). */
object PathCapability {
    /**
     * Whether a chart can have a CHOpt path.
     *
     * @param instrument Chart.
     * @return False for Karaoke.
     */
    fun hasPaths(instrument: Instrument): Boolean = instrument != Instrument.Karaoke

    /**
     * Path-capable charts for the Paths menu: visible, charted and not Karaoke, in canonical order.
     *
     * @param visible Settings-visible charts.
     * @param supports Whether the song charts an instrument.
     * @return Menu charts; empty hides the Paths action.
     */
    fun menuInstruments(visible: Set<Instrument>, supports: (Instrument) -> Boolean): List<Instrument> =
        Instrument.entries.filter { it in visible && hasPaths(it) && supports(it) }

    /**
     * Whether the Karaoke warning applies (Karaoke is visible but never has a path).
     *
     * @param visible Settings-visible charts.
     * @param dismissed Saved "Don't show again".
     * @return True when the warning should show on opening.
     */
    fun showsKaraokeWarning(visible: Set<Instrument>, dismissed: Boolean): Boolean = Instrument.Karaoke in visible && !dismissed
}

// endregion

// region Wire

/**
 * A chart note used to identify frets at an activation anchor.
 *
 * @property beat Beat position.
 * @property seconds Time.
 * @property isSpNote Star-power note.
 * @property frets Fret name to sustain length in beats.
 */
@Serializable
data class PathNote(val beat: Double, val seconds: Double? = null, val isSpNote: Boolean = false, val frets: Map<String, Double> = emptyMap())

/**
 * A scored note included in an activation (schema 2).
 *
 * @property beat Beat.
 * @property seconds Time.
 * @property cumulativeScore Score so far.
 * @property noteValue Note value.
 * @property odPercent OD fraction 0–1.
 * @property isSpGranting Grants star power.
 */
@Serializable
data class PathStartNote(
    val beat: Double,
    val seconds: Double? = null,
    val cumulativeScore: Long = 0,
    val noteValue: Long = 0,
    val odPercent: Double = 0.0,
    val isSpGranting: Boolean = false,
)

/**
 * One CHOpt activation.
 *
 * @property startBeat Start beat.
 * @property endBeat End beat.
 * @property startSeconds Start time.
 * @property activationBeat Activation beat.
 * @property activationSeconds Activation time.
 * @property anchorBeat Anchor note beat.
 * @property odAtActivation OD fraction 0–1.
 * @property scoreBeforeActivation Score before activating.
 * @property instruction Human instruction.
 * @property startNotes Scored notes.
 */
@Serializable
data class PathActivation(
    val startBeat: Double,
    val endBeat: Double,
    val startSeconds: Double? = null,
    val activationBeat: Double? = null,
    val activationSeconds: Double? = null,
    val anchorBeat: Double? = null,
    val odAtActivation: Double? = null,
    val scoreBeforeActivation: Long? = null,
    val instruction: String? = null,
    val startNotes: List<PathStartNote>? = null,
)

/**
 * Structured `/api/paths/{song}/{chart}/{difficulty}/data` artifact (Apple `SongPathData`).
 *
 * @property schemaVersion 1 or 2.
 * @property songName Song name.
 * @property artist Artist.
 * @property charter Charter.
 * @property difficulty Difficulty name.
 * @property totalScore Optimal path score.
 * @property pathSummary CHOpt summary line.
 * @property activations Activations.
 * @property notes Chart notes.
 */
@Serializable
data class SongPathData(
    val schemaVersion: Int? = null,
    val songName: String,
    val artist: String,
    val charter: String = "",
    val difficulty: String,
    val totalScore: Long,
    val pathSummary: String = "",
    val activations: List<PathActivation> = emptyList(),
    val notes: List<PathNote> = emptyList(),
) {
    /**
     * Reject malformed, mismatched or oversized path data.
     *
     * @param requested Difficulty whose endpoint produced this response.
     * @throws FestivalApiException.InvalidResponse when invalid.
     */
    fun validate(requested: PathDifficulty) {
        val valid = (schemaVersion == null || schemaVersion in 1..2) &&
            difficulty.equals(requested.wireName, ignoreCase = true) &&
            songName.isNotEmpty() && artist.isNotEmpty() && totalScore > 0 &&
            activations.size <= 128 && notes.size <= 25_000 &&
            activations.all(::validActivation) && notes.all(::validNote)
        if (!valid) throw FestivalApiException.InvalidResponse()
    }

    /**
     * Resolve table rows with the source's ±0.02-beat note-anchor tolerance.
     *
     * @return One row per activation, in order.
     */
    fun activationRows(): List<PathActivationRow> {
        val ordered = notes.sortedBy { it.beat }
        return activations.mapIndexed { index, activation ->
            val first = activation.startNotes?.firstOrNull()
            val beat = activation.activationBeat ?: first?.beat ?: activation.startBeat
            val anchor = activation.anchorBeat ?: first?.beat ?: nearbyAnchor(beat, ordered)
            PathActivationRow(
                number = index + 1,
                instruction = activation.instruction,
                beat = beat,
                seconds = activation.activationSeconds ?: first?.seconds ?: activation.startSeconds ?: 0.0,
                odPercent = activation.odAtActivation?.let { it * 100 } ?: first?.let { it.odPercent * 100 },
                scoreBeforeActivation = activation.scoreBeforeActivation ?: first?.cumulativeScore,
                frets = anchor?.let { chordFrets(it, ordered) } ?: emptyList(),
            )
        }
    }

    companion object {
        /** Fret names in the source's visible order. */
        val FRET_ORDER = listOf("green", "red", "yellow", "blue", "orange", "open")

        /** Largest accepted path body (image or text). */
        const val MAX_BYTES = 8_000_000

        private const val TOLERANCE = 0.02

        private fun validBeat(beat: Double) = beat.isFinite() && beat in 0.0..1_000_000.0
        private fun validSeconds(seconds: Double) = seconds.isFinite() && seconds in 0.0..86_400.0
        private fun validFraction(value: Double) = value.isFinite() && value in 0.0..1.0

        private fun validActivation(a: PathActivation): Boolean =
            validBeat(a.startBeat) && validBeat(a.endBeat) && a.endBeat >= a.startBeat &&
                listOfNotNull(a.activationBeat, a.anchorBeat).all(::validBeat) &&
                listOfNotNull(a.startSeconds, a.activationSeconds).all(::validSeconds) &&
                (a.odAtActivation?.let(::validFraction) ?: true) &&
                (a.scoreBeforeActivation?.let { it >= 0 } ?: true) &&
                (a.instruction?.let { it.length <= 500 } ?: true) &&
                (a.startNotes?.size ?: 0) <= 256 &&
                a.startNotes.orEmpty().all { n ->
                    validBeat(n.beat) && (n.seconds?.let(::validSeconds) ?: true) &&
                        n.cumulativeScore >= 0 && n.noteValue >= 0 && validFraction(n.odPercent)
                }

        private fun validNote(n: PathNote): Boolean =
            validBeat(n.beat) && (n.seconds?.let(::validSeconds) ?: true) &&
                n.frets.all { (fret, sustain) -> fret in FRET_ORDER && validBeat(sustain) }

        private fun chordFrets(anchor: Double, ordered: List<PathNote>): List<String> {
            var low = 0
            var high = ordered.size
            while (low < high) {
                val middle = (low + high) / 2
                if (ordered[middle].beat < anchor - TOLERANCE) low = middle + 1 else high = middle
            }
            val found = HashSet<String>()
            while (low < ordered.size && ordered[low].beat < anchor + TOLERANCE) {
                if (abs(ordered[low].beat - anchor) < TOLERANCE) found += ordered[low].frets.keys
                low++
            }
            return FRET_ORDER.filter(found::contains)
        }

        private fun nearbyAnchor(beat: Double, ordered: List<PathNote>): Double? {
            var prior: Double? = null
            var sustained: Double? = null
            for (note in ordered) {
                if (note.beat > beat + TOLERANCE) break
                prior = note.beat
                val sustain = note.frets.values.maxOrNull() ?: 0.0
                if (note.beat + sustain >= beat - TOLERANCE) sustained = note.beat
            }
            return sustained ?: prior?.takeIf { abs(it - beat) < TOLERANCE }
        }
    }
}

// endregion

// region Rows

/**
 * One text-table row resolved from activations and notes.
 *
 * @property number One-based activation number.
 * @property instruction Optional instruction.
 * @property beat Activation beat.
 * @property seconds Activation time.
 * @property odPercent OD 0–100, or null.
 * @property scoreBeforeActivation Score before activating, or null.
 * @property frets Anchor chord frets.
 */
data class PathActivationRow(
    val number: Int,
    val instruction: String?,
    val beat: Double,
    val seconds: Double,
    val odPercent: Double?,
    val scoreBeforeActivation: Long?,
    val frets: List<String>,
) {
    /**
     * Beat with two decimals.
     *
     * @param locale Formatting locale.
     * @return For example `12.50`.
     */
    fun beatText(locale: Locale = Locale.getDefault()): String = String.format(locale, "%.2f", beat)

    /** `mm:ss:mmm` like the web table. */
    val timeText: String
        get() {
            val millis = (seconds * 1_000).roundToLong()
            return String.format(Locale.ROOT, "%02d:%02d:%03d", millis / 60_000, millis / 1_000 % 60, millis % 1_000)
        }

    /** Rounded OD percent or "Unavailable". */
    val odText: String get() = odPercent?.let { "${it.roundToLong()}%" } ?: "Unavailable"

    /**
     * Grouped score or "Unavailable".
     *
     * @param locale Formatting locale.
     * @return Text.
     */
    fun scoreText(locale: Locale = Locale.getDefault()): String =
        scoreBeforeActivation?.let { NumberFormat.getIntegerInstance(locale).format(it) } ?: "Unavailable"

    /** Comma-joined frets or "No anchor". */
    val fretsText: String get() = if (frets.isEmpty()) "No anchor" else frets.joinToString(", ")
}

// endregion

// region Image validation

/** Bounded PNG header validation before any decode (Apple `SongPathImageDecoding`). */
object PathImageValidation {
    private val SIGNATURE = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
    private val IHDR = byteArrayOf(0x49, 0x48, 0x44, 0x52)

    /**
     * Read and bound a PNG's IHDR dimensions.
     *
     * @param bytes Response body.
     * @return Width and height.
     * @throws FestivalApiException.InvalidResponse for a non-PNG or oversized image.
     */
    fun dimensions(bytes: ByteArray): Pair<Int, Int> {
        if (bytes.size < 33 || bytes.size > SongPathData.MAX_BYTES ||
            !bytes.copyOfRange(0, 8).contentEquals(SIGNATURE) || !bytes.copyOfRange(12, 16).contentEquals(IHDR)
        ) {
            throw FestivalApiException.InvalidResponse()
        }
        val width = readInt(bytes, 16)
        val height = readInt(bytes, 20)
        if (width !in 1..8_192 || height !in 1..30_000 || width.toLong() * height > 24_000_000L) {
            throw FestivalApiException.InvalidResponse()
        }
        return width to height
    }

    private fun readInt(bytes: ByteArray, at: Int): Int =
        ((bytes[at].toInt() and 0xFF) shl 24) or ((bytes[at + 1].toInt() and 0xFF) shl 16) or
            ((bytes[at + 2].toInt() and 0xFF) shl 8) or (bytes[at + 3].toInt() and 0xFF)
}

// endregion
