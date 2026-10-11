package com.festivalscoretracker.android.settings

import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.ViewGroup
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.licenses.LicenseManifest
import com.festivalscoretracker.android.core.licenses.LicensedPackage
import com.festivalscoretracker.android.core.privacy.PrivacyPolicy
import com.festivalscoretracker.android.core.privacy.PrivacyPolicyBlock
import com.festivalscoretracker.android.core.privacy.PrivacyPolicySection
import com.festivalscoretracker.android.ui.settings.LicensesContent
import com.festivalscoretracker.android.ui.settings.PrivacyPolicyPane
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.FestivalAccessibility
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import kotlin.math.abs
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Issue #609: in list/detail Settings (landscape phones, tablets, unfolded folds) the Privacy
 * Policy and a package's license read inside one shared `GlassCard`, never straight on the
 * artwork: a frosted card by default and the opaque card with Reduce Transparency or Increase
 * Contrast, with every line of text inside the card.
 */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w900dp-h420dp-land-xhdpi")
class SettingsPaneCardSurfaceUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    // region Fixtures

    private val policy = PrivacyPolicy(
        schema = PrivacyPolicy.SCHEMA,
        title = "Privacy Policy",
        effectiveDateText = "Effective October 3, 2026",
        sections = listOf(
            PrivacyPolicySection("overview", "Overview", listOf(PrivacyPolicyBlock(PrivacyPolicyBlock.PARAGRAPH, text = "Overview text."))),
            PrivacyPolicySection("contact", "Contact", listOf(PrivacyPolicyBlock(PrivacyPolicyBlock.BULLETS, items = listOf("Email us.")))),
        ),
    )

    private val manifest = LicenseManifest(
        packages = listOf(LicensedPackage("androidx.activity", "activity-compose", "1.10.1", "Activity Compose", listOf("Apache-2.0"))),
        texts = mapOf("Apache-2.0" to "Apache License text"),
    )

    // endregion

    // region Privacy Policy

    @Test
    fun privacyPolicyReadsOnAFrostedCard() {
        showPolicy(FestivalAccessibility())
        assertTrue("frosted card over white", distance(fill(PRIVACY_CARD), BrandTokens.cardBackground.toArgb()) > 40)
        assertPolicyInsideTheCard()
    }

    @Test
    fun reduceTransparencyMakesThePolicyCardOpaque() {
        showPolicy(FestivalAccessibility(reduceTransparency = true))
        assertTrue("opaque card", distance(fill(PRIVACY_CARD), BrandTokens.cardBackground.toArgb()) <= 3)
        assertPolicyInsideTheCard()
    }

    @Test
    fun increaseContrastMakesThePolicyCardOpaque() {
        showPolicy(FestivalAccessibility(increaseContrast = true))
        assertTrue("opaque card", distance(fill(PRIVACY_CARD), BrandTokens.cardBackground.toArgb()) <= 3)
    }

    @Test
    fun unreadablePolicyStillSitsOnTheCard() {
        show(FestivalAccessibility()) { PrivacyPolicyPane(header = { Text("Privacy Policy") }, loadPolicy = { PrivacyPolicy(schema = PrivacyPolicy.SCHEMA) }) }
        waitFor("fst.privacy-policy.empty")
        assertInside("fst.privacy-policy.empty", PRIVACY_CARD)
    }

    // endregion

    // region Licenses

    @Test
    fun licenseTextReadsOnAFrostedCard() {
        showLicenses(FestivalAccessibility())
        assertTrue("frosted card", distance(fill(LICENSE_CARD), BrandTokens.cardBackground.toArgb()) > 40)
        assertInside("fst.licenses.text", LICENSE_CARD)
        assertInside(LICENSE_CARD, "fst.licenses.detail-pane")
    }

    @Test
    fun reduceTransparencyMakesTheLicenseCardOpaque() {
        showLicenses(FestivalAccessibility(reduceTransparency = true))
        assertTrue("opaque card", distance(fill(LICENSE_CARD), BrandTokens.cardBackground.toArgb()) <= 3)
        assertInside("fst.licenses.text", LICENSE_CARD)
    }

    // endregion

    // region Helpers

    /** A white backdrop makes translucency visible: a frosted card and the opaque card differ. */
    private fun show(accessibility: FestivalAccessibility, content: @Composable () -> Unit) {
        rule.setContent {
            FestivalTheme(appReduceMotion = true) {
                CompositionLocalProvider(LocalFestivalAccessibility provides accessibility) {
                    Box(Modifier.fillMaxSize().background(Color.White).padding(16.dp)) { content() }
                }
            }
        }
        rule.waitForIdle()
    }

    private fun showPolicy(accessibility: FestivalAccessibility) {
        show(accessibility) { PrivacyPolicyPane(header = { Text("Privacy Policy") }, loadPolicy = { policy }) }
        waitFor("fst.privacy-policy.content")
    }

    private fun showLicenses(accessibility: FestivalAccessibility) {
        show(accessibility) { LicensesContent(manifest, wide = true, hinge = null) }
        waitFor(LICENSE_CARD)
    }

    private fun assertPolicyInsideTheCard() {
        assertInside("fst.privacy-policy.content", PRIVACY_CARD)
        assertInside(PRIVACY_CARD, "fst.privacy-policy.pane")
        for (text in listOf("Effective October 3, 2026", "Overview", "Overview text.", "Contact")) {
            assertTrue("\"$text\" is in the card", rule.onAllNodes(hasText(text) and hasAnyAncestor(hasTestTag(PRIVACY_CARD)), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty())
        }
    }

    private fun waitFor(tag: String) = rule.waitUntil(10_000) { rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }

    private fun assertInside(inner: String, outer: String) {
        val a = bounds(inner)
        val b = bounds(outer)
        assertTrue("$inner $a inside $outer $b", a.left >= b.left - 1 && a.top >= b.top - 1 && a.right <= b.right + 1 && a.bottom <= b.bottom + 1)
    }

    /** The card colour just inside its top edge, clear of the border and the text. */
    private fun fill(tag: String): Int {
        val b = bounds(tag)
        return screen().getPixel(b.center.x.toInt(), (b.top + 8.dp.value * rule.activity.resources.displayMetrics.density).toInt())
    }

    private fun bounds(tag: String): Rect = rule.onAllNodesWithTag(tag, useUnmergedTree = true)[0].fetchSemanticsNode().boundsInRoot

    /** The rendered window, drawn in software (Robolectric's `captureToImage` never gets a frame). */
    private fun screen(): Bitmap {
        val view = rule.activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0)
        val whole = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
        view.draw(Canvas(whole))
        return whole
    }

    private fun distance(a: Int, b: Int): Int = maxOf(
        abs(android.graphics.Color.red(a) - android.graphics.Color.red(b)),
        abs(android.graphics.Color.green(a) - android.graphics.Color.green(b)),
        abs(android.graphics.Color.blue(a) - android.graphics.Color.blue(b)),
    )

    // endregion

    private companion object {
        const val PRIVACY_CARD = "fst.privacy-policy.card"
        const val LICENSE_CARD = "fst.licenses.detail-card"
    }
}
