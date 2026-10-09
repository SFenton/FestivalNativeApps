package com.festivalscoretracker.android.journeys

/**
 * Marks a connected test as part of the CI-stable phone set. CI's `android-device` check
 * (`.github/workflows/android-device.yml`) runs the whole instrumented suite, so this annotation no
 * longer selects what CI runs; it remains a convenient local subset
 * (`device.py test annotation:com.festivalscoretracker.android.journeys.DeviceCi`). Fold journeys
 * use [HalfOpenFoldJourney] (`android-fold`).
 */
@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.CLASS, AnnotationTarget.FUNCTION)
annotation class DeviceCi
