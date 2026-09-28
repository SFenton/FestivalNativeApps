package com.festivalscoretracker.android.ui.theme

import android.app.UiModeManager
import android.content.Context
import android.os.Build
import android.provider.Settings
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

// region Brand tokens

/** Brand colors shared with Apple's `BrandTokens` (web design tokens). */
object BrandTokens {
    val accentBlue = Color(0xFF2D82E6)
    val accentPurple = Color(0xFF7C3AED)
    val appBackground = Color(0xFF1A0830)
    val cardBackground = Color(0xFF0B1220)
    val glassBorder = Color(0x14FFFFFF)
    val gold = Color(0xFFFFD700)
    val statusGreen = Color(0xFF2ECC71)
    val statusRed = Color(0xFFC62828)
    val surfaceFrosted = Color(0xC7121826)
    val surfaceMuted = Color(0xFF223047)
    val surfaceSubtle = Color(0xFF162133)
    val textDisabled = Color(0xFF607089)
    val textMuted = Color(0xFF8899AA)
    val textPrimary = Color(0xFFFFFFFF)
    val textSecondary = Color(0xFFD7DEE8)
}

// endregion

// region Accessibility

/**
 * Effective accessibility preferences: OS signals combined with the app's
 * additive overrides (an override can only make the app more accessible).
 *
 * @property increaseContrast Opaque surfaces and strong borders.
 * @property reduceMotion No decorative motion.
 */
@Immutable
data class FestivalAccessibility(val increaseContrast: Boolean = false, val reduceMotion: Boolean = false)

/** Current effective accessibility preferences. */
val LocalFestivalAccessibility = staticCompositionLocalOf { FestivalAccessibility() }

/**
 * Whether the OS requests reduced motion (animator duration scale 0).
 *
 * @param context Any context.
 * @return True when animations are off system-wide.
 */
fun systemReducesMotion(context: Context): Boolean =
    Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f

/**
 * Whether the OS requests higher contrast (Android 14+ contrast level).
 *
 * @param context Any context.
 * @return True for a positive system contrast level.
 */
fun systemIncreasesContrast(context: Context): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return false
    val manager = context.getSystemService(UiModeManager::class.java) ?: return false
    return manager.contrast > 0f
}

// endregion

// region Theme

private val festivalScheme = darkColorScheme(
    primary = BrandTokens.accentBlue,
    onPrimary = BrandTokens.textPrimary,
    secondary = BrandTokens.accentPurple,
    onSecondary = BrandTokens.textPrimary,
    tertiary = BrandTokens.gold,
    background = BrandTokens.appBackground,
    onBackground = BrandTokens.textPrimary,
    surface = BrandTokens.cardBackground,
    onSurface = BrandTokens.textPrimary,
    surfaceVariant = BrandTokens.surfaceMuted,
    onSurfaceVariant = BrandTokens.textSecondary,
    surfaceContainer = BrandTokens.surfaceSubtle,
    secondaryContainer = BrandTokens.accentPurple.copy(alpha = 0.45f),
    onSecondaryContainer = BrandTokens.textPrimary,
    outline = BrandTokens.textMuted,
    outlineVariant = BrandTokens.surfaceMuted,
    error = BrandTokens.statusRed,
)

/**
 * App theme: Material 3 dark scheme from brand tokens, with system chrome kept native.
 *
 * @param appIncreaseContrast In-app contrast override.
 * @param appReduceMotion In-app motion override.
 * @param content Themed content.
 */
@Composable
fun FestivalTheme(appIncreaseContrast: Boolean = false, appReduceMotion: Boolean = false, content: @Composable () -> Unit) {
    val context = LocalContext.current
    val accessibility = remember(appIncreaseContrast, appReduceMotion) {
        FestivalAccessibility(
            increaseContrast = appIncreaseContrast || systemIncreasesContrast(context),
            reduceMotion = appReduceMotion || systemReducesMotion(context),
        )
    }
    val scheme = if (accessibility.increaseContrast) {
        festivalScheme.copy(onSurfaceVariant = BrandTokens.textPrimary, outline = BrandTokens.textPrimary)
    } else {
        festivalScheme
    }
    CompositionLocalProvider(LocalFestivalAccessibility provides accessibility) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}

// endregion
