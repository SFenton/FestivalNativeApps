package com.festivalscoretracker.android.data.serviceinfo

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.service.ServiceFreezeReason
import com.festivalscoretracker.android.core.serviceinfo.ServiceInfo
import com.festivalscoretracker.android.core.serviceinfo.ServiceInfoSnapshot
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.ServiceEndpoint
import kotlinx.serialization.Serializable

// region Settings service reads

/**
 * `GET /api/service-info`: operational, unpinned and pure — in-process scrape progress plus one
 * `SELECT` (`MetaDatabase.GetServiceRuntimeState`), `FSTService/Api/HealthEndpoints.cs:62-300`.
 * Not publication-bound, so never a freeze 503; it carries the freeze header. Allowlisted in
 * `.agents/platforms/service-safety.md`.
 */
internal val SERVICE_INFO_ENDPOINT = ServiceEndpoint.Feature(listOf("service-info"), pinned = false)

/** `GET /api/version`: assembly metadata `{version}` (`HealthEndpoints.cs:18-29`), pure. */
internal val SERVICE_VERSION_ENDPOINT = ServiceEndpoint.Feature(listOf("version"), pinned = false)

@Serializable
private data class ServiceVersionBody(val version: String)

/**
 * Read live scrape, worker and publication state for the Settings Service Info card. The model
 * has no fields for the body's infrastructure details, so they are never decoded or kept.
 *
 * @return Decoded state and any freeze header.
 * @throws FestivalApiException for transport, mapped status or a malformed body.
 */
suspend fun FestivalApi.serviceInfo(): ServiceInfoSnapshot {
    val response = readUnpinnedResult(SERVICE_INFO_ENDPOINT)
    return ServiceInfoSnapshot(decode(ServiceInfo.serializer(), response.body), response.header(ServiceFreezeReason.HEADER))
}

/**
 * Read the service build version for Settings → Version.
 *
 * @return A short printable version string.
 * @throws FestivalApiException for transport, mapped status, or an empty, oversized or
 *   non-printable-ASCII value.
 */
suspend fun FestivalApi.serviceVersion(): String {
    val value = decode(ServiceVersionBody.serializer(), readUnpinned(SERVICE_VERSION_ENDPOINT)).version.trim()
    if (value.isEmpty() || value.length > 64 || !value.all { it.code in 0x20 until 0x7F }) throw FestivalApiException.InvalidResponse()
    return value
}

// endregion
