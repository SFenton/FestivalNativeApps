package com.festivalscoretracker.android.journeys

/**
 * Opts a connected test into the `android-device` CI job (`.github/workflows/native.yml`), which
 * boots one emulator and runs every test carrying this annotation
 * (`-Pandroid.testInstrumentationRunnerArguments.annotation=…DeviceCi`). Put it on the
 * accessibility test that ships with a UI change, on the method or the whole class. The test
 * must run against fixtures only (`FakeTransport`, in-memory preferences) and pass on a plain
 * phone with no hinge.
 */
@Retention(AnnotationRetention.RUNTIME)
@Target(AnnotationTarget.CLASS, AnnotationTarget.FUNCTION)
annotation class DeviceCi
