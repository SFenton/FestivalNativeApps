package com.festivalscoretracker.android.ui.design

import android.content.res.Resources
import android.util.SparseArray
import androidx.annotation.DrawableRes
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.painter.BitmapPainter
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.imageResource

// region Bundled bitmaps

/**
 * Decoded bundled PNG drawables (instrument icons, star images), shared process-wide.
 *
 * `painterResource` decodes a PNG again for every new call site, so each Songs row that
 * scrolled in decoded its nine 144 px instrument icons on the main thread. There are only
 * thirteen such images (under 1 MB decoded), so they are decoded once and kept. Album art
 * never goes here: it uses the bounded Coil caches.
 */
object BundledBitmaps {
    private val cache = SparseArray<ImageBitmap>()

    /**
     * The decoded image, decoding it on first use.
     *
     * @param resources App resources.
     * @param id Drawable resource (a `drawable-nodpi` PNG).
     * @return Shared image.
     */
    @Synchronized
    fun get(resources: Resources, @DrawableRes id: Int): ImageBitmap =
        cache[id] ?: ImageBitmap.imageResource(resources, id).also { cache.put(id, it) }
}

/**
 * A painter for a bundled PNG from [BundledBitmaps] (drop-in for `painterResource` on
 * raster drawables that appear in list rows).
 *
 * @param id Drawable resource.
 * @return Painter drawing the shared image.
 */
@Composable
fun bundledPainter(@DrawableRes id: Int): Painter {
    val resources = LocalContext.current.resources
    return remember(id) { BitmapPainter(BundledBitmaps.get(resources, id)) }
}

// endregion
