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
    adb shell wm size 2208x1840
    adb shell wm density 420
    adb shell settings put global display_features 'fold-[1104,0,1104,1840]-half-opened'
    sleep 2
    adb shell wm size
    adb shell wm density
    adb shell settings get global display_features
fi

bash android/gradlew -p android :app:connectedDebugAndroidTest --no-daemon --stacktrace \
    "-Pandroid.testInstrumentationRunnerArguments.fst.expectFold=$expect_fold"

if [[ "$expect_fold" == "true" ]]; then
    adb logcat -d -v threadtime -s FST_FOLD:I
fi
