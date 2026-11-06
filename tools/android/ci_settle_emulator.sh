#!/usr/bin/env bash
# Settle a freshly booted CI emulator before the instrumented suite (android-device, android-fold).
#
# Wakes and unlocks it without injecting keys, then waits until a normal window has held focus
# for SETTLE_SECONDS. A key injected right after boot (the emulator runner's own unlock key)
# can reach the launcher before it has a focused window; that input-dispatch ANR is continuous,
# so "Pixel Launcher isn't responding" kept returning over every test (#679, #692). Any app whose
# ANR dialog holds focus here is force-stopped (the system restarts its launcher); the app under
# test isn't installed yet. Never fails the job: the tests' ActiveWindow.root() still closes a
# foreign ANR dialog that appears later.
#
# Usage: ci_settle_emulator.sh [timeout seconds, default 180]
set -u

SETTLE_SECONDS=20
POLL_SECONDS=2
deadline=$((SECONDS + ${1:-180}))

adb shell svc power stayon true
adb shell wm dismiss-keyguard
adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS > /dev/null || true

focused_since=""
focus=""
while [ "$SECONDS" -lt "$deadline" ]; do
  focus=$(adb shell dumpsys window 2> /dev/null | grep -m 1 'mCurrentFocus=' | tr -d '\r' | sed 's/^ *//')
  case "$focus" in
    *"Application Not Responding: "*)
      package=$(printf '%s' "$focus" | sed -E 's/.*Application Not Responding: ([A-Za-z0-9_.]+).*/\1/')
      echo "ci_settle_emulator: $package isn't responding; force-stopping it (#692)"
      adb shell am force-stop "$package"
      focused_since="" ;;
    *"mCurrentFocus=Window{"*)
      [ -z "$focused_since" ] && focused_since=$SECONDS
      if [ $((SECONDS - focused_since)) -ge "$SETTLE_SECONDS" ]; then
        echo "ci_settle_emulator: settled on $focus"
        exit 0
      fi ;;
    *)
      focused_since="" ;;
  esac
  sleep "$POLL_SECONDS"
done
echo "ci_settle_emulator: warning: no window held focus for ${SETTLE_SECONDS}s (last: ${focus:-none})"
exit 0
