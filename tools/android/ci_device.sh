#!/usr/bin/env bash
# Runs one hosted Android device-test leg and preserves diagnostics on failure.

set -euo pipefail

leg="${1:?usage: ci_device.sh <phone|fold-half> <expect-fold>}"
expect_fold="${2:?usage: ci_device.sh <phone|fold-half> <expect-fold>}"
logcat="${GITHUB_WORKSPACE:-$PWD}/android-device-${leg}-logcat.txt"

dump_logcat() {
    adb logcat -d -v threadtime > "$logcat" || true
}
trap dump_logcat EXIT

if [[ "$expect_fold" == "true" ]]; then
    adb shell wm size 2076x2152
    adb shell wm density 390
    adb shell settings put global display_features 'fold-[1038,0,1038,2152]-half-opened'
    sleep 2
    adb shell wm size
    adb shell wm density
    adb shell settings get global display_features
fi

case "$leg" in
    phone)
        bash android/gradlew -p android :app:connectedDebugAndroidTest --no-daemon --stacktrace \
            "-Pandroid.testInstrumentationRunnerArguments.annotation=com.festivalscoretracker.android.journeys.DeviceCi" \
            "-Pandroid.testInstrumentationRunnerArguments.fst.expectFold=$expect_fold"
        ;;
    fold-half)
        bash android/gradlew -p android :app:connectedDebugAndroidTest --no-daemon --stacktrace \
            "-Pandroid.testInstrumentationRunnerArguments.class=com.festivalscoretracker.android.journeys.FoldableCiPreflightTest,com.festivalscoretracker.android.journeys.BandRankingsJourneyTest,com.festivalscoretracker.android.journeys.BandsSettingsJourneyTest,com.festivalscoretracker.android.journeys.ModalCloseJourneyTest,com.festivalscoretracker.android.journeys.ShellAccessibilityJourneyTest,com.festivalscoretracker.android.journeys.ShopFilterAccessibilityJourneyTest,com.festivalscoretracker.android.journeys.SongPathsDeviceTest" \
            "-Pandroid.testInstrumentationRunnerArguments.fst.expectFold=$expect_fold"
        ;;
    *)
        echo "Unknown Android device CI leg: $leg" >&2
        exit 2
        ;;
esac

if [[ "$expect_fold" == "true" ]]; then
    adb logcat -d -v threadtime -s FST_FOLD:I
fi
