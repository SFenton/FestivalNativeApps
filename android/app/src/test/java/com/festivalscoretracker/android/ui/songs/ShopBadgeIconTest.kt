package com.festivalscoretracker.android.ui.songs

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.ShoppingBag
import com.festivalscoretracker.android.core.shop.ShopPulse
import org.junit.Assert.assertSame
import org.junit.Test

/** Issue #562: the Songs row Shop circle has no New-only sparkle; New uses the Shop bag like any offer. */
class ShopBadgeIconTest {
    @Test
    fun leavingTomorrowIsTheClockAndEveryOtherOfferIsTheBag() {
        assertSame(Icons.Filled.Schedule, shopBadgeIcon(ShopPulse.LeavingTomorrow))
        assertSame(Icons.Filled.ShoppingBag, shopBadgeIcon(ShopPulse.New))
        assertSame(Icons.Filled.ShoppingBag, shopBadgeIcon(ShopPulse.InShop))
    }
}
