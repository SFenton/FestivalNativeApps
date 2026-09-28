package com.festivalscoretracker.android.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// region Semantic content tokens

/** Fluent-inspired semantic dark aliases for native content, not system navigation chrome. */
object FestivalTokens {
    val canvas = Color(0xFF111318)
    val surface = Color(0xFF20232A)
    val raised = Color(0xFF2B2F38)
    val text = Color(0xFFF5F5F7)
    val secondaryText = Color(0xFFC4C8D0)
    val accent = Color(0xFF9ED1FF)
    val accentStrong = Color(0xFF70B8FF)
    val outline = Color(0xFF626975)
}

private val darkScheme = darkColorScheme(
    primary = FestivalTokens.accent,
    onPrimary = FestivalTokens.canvas,
    background = FestivalTokens.canvas,
    onBackground = FestivalTokens.text,
    surface = FestivalTokens.surface,
    onSurface = FestivalTokens.text,
    surfaceVariant = FestivalTokens.raised,
    onSurfaceVariant = FestivalTokens.secondaryText,
    outline = FestivalTokens.outline,
)

private val contrastScheme = darkScheme.copy(
    primary = Color.White,
    outline = Color.White,
    onSurfaceVariant = Color.White,
)

/** Applies semantic dark content colors while retaining platform-native window chrome. */
@Composable
fun FestivalTheme(extraContrast: Boolean = false, content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = if (extraContrast) contrastScheme else darkScheme, content = content)
}

// endregion
