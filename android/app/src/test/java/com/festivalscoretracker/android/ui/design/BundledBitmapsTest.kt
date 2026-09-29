package com.festivalscoretracker.android.ui.design

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.R
import com.festivalscoretracker.android.core.model.Instrument
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertSame
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.GraphicsMode

/** [BundledBitmaps]: each bundled PNG is decoded once and shared. */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class BundledBitmapsTest {
    private val resources = ApplicationProvider.getApplicationContext<android.content.Context>().resources

    @Test
    fun decodesOncePerDrawable() {
        val lead = BundledBitmaps.get(resources, instrumentIconRes(Instrument.entries.first()))
        assertSame(lead, BundledBitmaps.get(resources, instrumentIconRes(Instrument.entries.first())))
        assertEquals(144, lead.width)
        assertNotSame(lead, BundledBitmaps.get(resources, R.drawable.star_gold))
    }
}
