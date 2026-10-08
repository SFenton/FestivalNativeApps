package com.festivalscoretracker.android.journeys

import android.os.SystemClock
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowInfoTracker
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Verifies that the CI foldable leg exposes the real half-open hinge to WindowManager. */
@RunWith(AndroidJUnit4::class)
class FoldableCiPreflightTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private fun foldingFeatures(): List<FoldingFeature> = runBlocking {
        withTimeoutOrNull(5_000) {
            WindowInfoTracker.getOrCreate(rule.activity).windowLayoutInfo(rule.activity).first()
        }?.displayFeatures.orEmpty().filterIsInstance<FoldingFeature>()
    }

    @Test
    fun halfOpenedFoldLegReportsASeparatingHinge() {
        val expectsFold = InstrumentationRegistry.getArguments().getString("fst.expectFold") == "true"
        assumeTrue("fold verification runs only on the fold-half CI leg", expectsFold)

        var observed = emptyList<FoldingFeature>()
        var hinge: FoldingFeature? = null
        val deadline = SystemClock.uptimeMillis() + 30_000
        while (SystemClock.uptimeMillis() < deadline && hinge == null) {
            observed = foldingFeatures()
            hinge = observed.firstOrNull {
                it.isSeparating &&
                    it.state == FoldingFeature.State.HALF_OPENED &&
                    it.bounds.width() > 0 &&
                    it.bounds.height() > 0
            }
            if (hinge == null) SystemClock.sleep(500)
        }
        Log.i(FOLD_TAG, "half-open hinge=$hinge allFeatures=$observed")
        assertNotNull("No separating half-open FoldingFeature: $observed", hinge)
        val confirmedHinge = hinge ?: throw AssertionError("No separating half-open FoldingFeature: $observed")
        assertTrue(
            "half-open hinge has empty bounds: $confirmedHinge",
            confirmedHinge.bounds.width() > 0 && confirmedHinge.bounds.height() > 0,
        )
    }

    private companion object {
        const val FOLD_TAG = "FST_FOLD"
    }
}
