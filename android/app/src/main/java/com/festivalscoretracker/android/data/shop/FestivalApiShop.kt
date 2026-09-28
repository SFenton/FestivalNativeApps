package com.festivalscoretracker.android.data.shop

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.shop.ShopPayload
import com.festivalscoretracker.android.core.shop.ShopResponse
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.ServiceEndpoint

// region Shop read

/** `GET /api/shop`: keyless, publication-bound, pure read (service-safety allowlist). */
internal val ShopEndpoint = ServiceEndpoint.Feature(listOf("shop"))

/**
 * Fetch and validate the public Item Shop (Apple `FestivalAPI.shop()`).
 *
 * `FSTService/Api/SongEndpoints.cs:244-255` serves the cached shop payload; no
 * writes. Outbound links are validated to the official Fortnite Shop host.
 *
 * @receiver Shared client.
 * @return Validated offers with publication provenance.
 * @throws FestivalApiException for status, oversized or malformed data.
 */
suspend fun FestivalApi.shop(): ShopPayload {
    val read = readPinnedResponse(ShopEndpoint)
    if (read.body.size > ShopResponse.MAX_BYTES) throw FestivalApiException.InvalidResponse()
    val shop = decode(ShopResponse.serializer(), read.body)
    shop.validate()
    return ShopPayload(shop, shop.sortedSongs(), read.responsePublicationId, read.observedPublicationId)
}

// endregion
