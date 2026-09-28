package com.festivalscoretracker.android.core.model

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.SerializationException
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder

// region Population tiers

/**
 * One chart's precomputed filtered-population curve from `/api/songs`
 * (`populationTiers[chart]`, wire `{bc, t: [{l, t}]}`): how many entries remain at
 * each invalid-score leeway. Stored as parallel primitive arrays because the
 * catalogue carries thousands of changepoints.
 *
 * @property baseCount Entries always under the threshold band (`bc`).
 * @property leeways Changepoint leeways, ascending (`t[].l`).
 * @property totals Filtered totals at each changepoint (`t[].t`).
 */
@Serializable(with = PopulationTiersSerializer::class)
class PopulationTiers(val baseCount: Int, val leeways: DoubleArray, val totals: IntArray) {
    /**
     * Filtered population at a leeway (web `getFilteredTotal`): the last changepoint
     * at or below it, else [baseCount].
     *
     * @param leeway Leeway percent.
     * @return Filtered total.
     */
    fun total(leeway: Double): Int {
        var result = baseCount
        for (index in leeways.indices) {
            if (leeways[index] <= leeway) result = totals[index] else break
        }
        return result
    }

    /** Whether counts are non-negative, leeways finite and ascending. */
    val isWellFormed: Boolean
        get() = baseCount >= 0 && leeways.size == totals.size && totals.all { it >= 0 } &&
            leeways.all { it.isFinite() } && leeways.indices.drop(1).all { leeways[it - 1] <= leeways[it] }
}

@Serializable
private data class WireTier(@SerialName("l") val leeway: Double, @SerialName("t") val total: Int)

@Serializable
private data class WireTiers(@SerialName("bc") val baseCount: Int = 0, @SerialName("t") val tiers: List<WireTier> = emptyList())

/**
 * Decodes the compact wire into primitive arrays. A malformed curve decodes as an
 * ill-formed value (never used) instead of failing the whole catalogue. Encoding is
 * only for tests and fixtures.
 */
object PopulationTiersSerializer : KSerializer<PopulationTiers> {
    override val descriptor: SerialDescriptor = WireTiers.serializer().descriptor

    /** Placeholder for an unreadable curve ([PopulationTiers.isWellFormed] is false). */
    private val INVALID = PopulationTiers(-1, DoubleArray(0), IntArray(0))

    override fun deserialize(decoder: Decoder): PopulationTiers {
        val json = decoder as? JsonDecoder ?: return fromWire(decoder.decodeSerializableValue(WireTiers.serializer()))
        val element = json.decodeJsonElement()
        return try {
            fromWire(json.json.decodeFromJsonElement(WireTiers.serializer(), element))
        } catch (error: SerializationException) {
            INVALID
        } catch (error: IllegalArgumentException) {
            INVALID
        }
    }

    private fun fromWire(wire: WireTiers) = PopulationTiers(
        wire.baseCount,
        DoubleArray(wire.tiers.size) { wire.tiers[it].leeway },
        IntArray(wire.tiers.size) { wire.tiers[it].total },
    )

    override fun serialize(encoder: Encoder, value: PopulationTiers) {
        encoder.encodeSerializableValue(
            WireTiers.serializer(),
            WireTiers(value.baseCount, value.leeways.indices.map { WireTier(value.leeways[it], value.totals[it]) }),
        )
    }
}

// endregion
