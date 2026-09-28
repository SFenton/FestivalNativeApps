package com.festivalscoretracker.android.data.paths

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.paths.PathActivationRow
import com.festivalscoretracker.android.core.paths.PathCapability
import com.festivalscoretracker.android.core.paths.PathDifficulty
import com.festivalscoretracker.android.core.paths.PathImageValidation
import com.festivalscoretracker.android.core.paths.SongPathData
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.ServiceEndpoint

// region Endpoint

/**
 * `GET /api/paths/{songId}/{instrument}/{difficulty}[/data][?generationId=]`: keyless,
 * publication-bound pure read of a pre-generated artifact (`FSTService/Api/SongEndpoints.cs:259-385`).
 *
 * @param songId Catalogue song ID.
 * @param instrument Path-capable chart.
 * @param difficulty Difficulty.
 * @param text True for the JSON `/data` route, false for the PNG.
 * @param generationId Catalogue `pathArtifactGenerationId`, if any.
 * @return Endpoint.
 * @throws FestivalApiException.InvalidResource for Karaoke or an invalid generation.
 */
internal fun pathEndpoint(songId: String, instrument: Instrument, difficulty: PathDifficulty, text: Boolean, generationId: String?): ServiceEndpoint.Feature {
    if (!PathCapability.hasPaths(instrument) || (generationId != null && (generationId.isEmpty() || generationId.length > 200))) {
        throw FestivalApiException.InvalidResource()
    }
    val segments = listOf("paths", songId, instrument.wireId, difficulty.wireName) + if (text) listOf("data") else emptyList()
    return ServiceEndpoint.Feature(segments, generationId?.let { listOf("generationId" to it) } ?: emptyList())
}

// endregion

// region Payloads

/**
 * A validated path table with provenance.
 *
 * @property path Decoded artifact.
 * @property rows Resolved rows.
 * @property publicationId Header-verified publication, or null.
 * @property observedPublicationId Observed generation.
 */
class SongPathDataPayload(val path: SongPathData, val rows: List<PathActivationRow>, val publicationId: Int?, val observedPublicationId: Int)

/**
 * Validated PNG bytes (decoded by the UI layer off the main thread).
 *
 * @property bytes PNG bytes.
 * @property width Pixel width.
 * @property height Pixel height.
 * @property publicationId Header-verified publication, or null.
 * @property observedPublicationId Observed generation.
 */
class SongPathImagePayload(val bytes: ByteArray, val width: Int, val height: Int, val publicationId: Int?, val observedPublicationId: Int)

// endregion

// region Reads

/**
 * Fetch and validate the structured CHOpt table.
 *
 * @receiver Shared client.
 * @param songId Song.
 * @param instrument Chart.
 * @param difficulty Difficulty.
 * @param generationId Artifact revision.
 * @return Typed table.
 */
suspend fun FestivalApi.pathData(songId: String, instrument: Instrument, difficulty: PathDifficulty, generationId: String? = null): SongPathDataPayload {
    val read = readPinnedResponse(pathEndpoint(songId, instrument, difficulty, text = true, generationId))
    if (read.body.size > SongPathData.MAX_BYTES) throw FestivalApiException.InvalidResponse()
    val path = decode(SongPathData.serializer(), read.body)
    path.validate(difficulty)
    return SongPathDataPayload(path, path.activationRows(), read.responsePublicationId, read.observedPublicationId)
}

/**
 * Fetch and bound-check the CHOpt PNG.
 *
 * @receiver Shared client.
 * @param songId Song.
 * @param instrument Chart.
 * @param difficulty Difficulty.
 * @param generationId Artifact revision.
 * @return PNG bytes and size.
 */
suspend fun FestivalApi.pathImage(songId: String, instrument: Instrument, difficulty: PathDifficulty, generationId: String? = null): SongPathImagePayload {
    val read = readPinnedResponse(pathEndpoint(songId, instrument, difficulty, text = false, generationId))
    val (width, height) = PathImageValidation.dimensions(read.body)
    return SongPathImagePayload(read.body, width, height, read.responsePublicationId, read.observedPublicationId)
}

// endregion
