package com.festivalscoretracker.android.firstrun

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoFit
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.firstrun.DEMO_CONTENT_TAG
import com.festivalscoretracker.android.ui.firstrun.FIRST_RUN_DEMO_IDS
import com.festivalscoretracker.android.ui.firstrun.FirstRunDemo
import com.festivalscoretracker.android.ui.firstrun.FirstRunDemoCatalog
import com.festivalscoretracker.android.ui.firstrun.LocalFirstRunDemoCatalog
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * Every First Run demo, built from the app's real rows and controls (issue #380), fits the
 * carousel's 220 dp demo frame at phone width: the frame doesn't clip, so a taller demo would run
 * into the slide title. Row demos fit by showing fewer whole rows; fixed demos may scale down a
 * little, never so far that their text becomes unreadable.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w360dp-h800dp")
class FirstRunDemoFitUiTest {
    @get:Rule
    val rule = createComposeRule()

    private val songs = (1..8).map { Fixtures.song("song$it", "Demo Song $it", artist = "Epic Games").copy(albumArt = "a$it.jpg") }

    @Test
    fun everyDemoFitsTheFrameAtPhoneWidth() {
        var id by mutableStateOf(FIRST_RUN_DEMO_IDS.first())
        rule.setContent {
            FestivalTheme {
                CompositionLocalProvider(LocalFirstRunDemoCatalog provides FirstRunDemoCatalog(songs, shopSongIds = songs.map { it.songId }, artworkUrl = { it })) {
                    Box(Modifier.width(328.dp).wrapContentHeight(Alignment.Top, unbounded = true).testTag("host")) { FirstRunDemo(id, active = false) }
                }
            }
        }
        val tooTall = FIRST_RUN_DEMO_IDS.mapNotNull { demo ->
            id = demo
            rule.waitForIdle()
            val height = rule.onNodeWithTag("host", useUnmergedTree = true).fetchSemanticsNode().size.height / rule.density.density
            val natural = rule.onNodeWithTag(DEMO_CONTENT_TAG, useUnmergedTree = true).fetchSemanticsNode().size.height / rule.density.density
            val scale = FirstRunDemoFit.scale(natural, FirstRunDemoFit.FRAME_DP)
            if (height > FirstRunDemoFit.FRAME_DP + 1f || scale < MIN_SCALE) "$demo: ${height}dp, natural ${natural}dp" else null
        }
        assertTrue("Demos taller than ${FirstRunDemoFit.FRAME_DP}dp or scaled below $MIN_SCALE: $tooTall", tooTall.isEmpty())
    }

    private companion object {
        /** Smallest scale a fixed-structure demo may take at phone width. */
        const val MIN_SCALE = 0.8f
    }
}
