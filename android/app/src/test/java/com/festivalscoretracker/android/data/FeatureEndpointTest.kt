package com.festivalscoretracker.android.data

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.testing.FakeTransport
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.Serializable
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class FeatureEndpointTest {
    @Serializable
    private data class Echo(val value: Int)

    @Test
    fun featureEndpointBuildsEncodedSegmentsAndQuery() {
        val base = "https://fixture.test".toHttpUrl()
        val url = ServiceEndpoint.Feature(listOf("rankings", "bands", "Band_Duets", "a:b", "history"), listOf("days" to "30", "q" to "x y")).url(base)
        assertEquals("https://fixture.test/api/rankings/bands/Band_Duets/a:b/history?days=30&q=x%20y", url)
    }

    @Test
    fun featureEndpointRejectsUnsafeOrEmptySegments() {
        val base = "https://fixture.test".toHttpUrl()
        listOf(emptyList(), listOf("a", ".."), listOf("a/b"), listOf(""), listOf("."), listOf("a\\b")).forEach { segments ->
            assertThrows(FestivalApiException.InvalidResource::class.java) { ServiceEndpoint.Feature(segments).url(base) }
        }
    }

    @Test
    fun featureReadsUseThePinnedGateAndDecoder() = runTest {
        val transport = FakeTransport.standard().apply {
            on("/api/feature/ok", headers = mapOf("X-FST-Publication-Id" to "7")) { """{"value":3,"extra":true}""" }
            on("/api/feature/bad") { "not json" }
        }
        val api = FestivalApi("https://fixture.test", transport)
        val (body, publication) = api.readPinned(ServiceEndpoint.Feature(listOf("feature", "ok")))
        assertEquals(7, publication)
        assertEquals(Echo(3), api.decode(Echo.serializer(), body))
        val (bad, _) = api.readPinned(ServiceEndpoint.Feature(listOf("feature", "bad")))
        assertThrows(FestivalApiException.InvalidResponse::class.java) { api.decode(Echo.serializer(), bad) }
        transport.requests.forEach { RequestGate.validateKeyless(it) }
    }
}
