package com.festivalscoretracker.android

import android.app.Application
import coil3.ImageLoader
import coil3.PlatformContext
import coil3.SingletonImageLoader
import coil3.memory.MemoryCache
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import coil3.request.crossfade
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.data.OkHttpTransport

// region Application

/**
 * Owns the process-lifetime container and the artwork image loader.
 *
 * Artwork is decorative and ephemeral (AGENTS.md): a bounded in-process memory
 * cache only, no disk cache, sharing the cache-less HTTP client.
 */
class FestivalApplication : Application(), SingletonImageLoader.Factory {
    private val httpClient by lazy { OkHttpTransport.defaultClient() }
    private var container: AppContainer? = null

    /**
     * Create the container on first use; later launches in the same process reuse it.
     *
     * @param launch Debug launch extras for this first activity creation.
     * @return The process container.
     */
    fun container(launch: DebugLaunch): AppContainer =
        container ?: AppContainer(this, httpClient, launch).also { container = it }

    override fun newImageLoader(context: PlatformContext): ImageLoader =
        ImageLoader.Builder(context)
            .components { add(OkHttpNetworkFetcherFactory(callFactory = { httpClient })) }
            .memoryCache { MemoryCache.Builder().maxSizePercent(context, MEMORY_CACHE_FRACTION).build() }
            .diskCache(null)
            .crossfade(true)
            .build()

    private companion object {
        /** Share of the app's memory budget for decoded artwork. */
        const val MEMORY_CACHE_FRACTION = 0.2
    }
}

// endregion
