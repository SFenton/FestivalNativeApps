package com.festivalscoretracker.android.ui.common

import androidx.compose.runtime.compositionLocalOf

/** Current authoritative generation, shared by page load gates without changing navigation. */
val LocalPublicationGeneration = compositionLocalOf<Int?> { null }
