# Installed PWA reference: Android (Chrome on the FST AVDs)

> **What:** how the web app behaves when installed from Chrome on the FST phone, foldables, tri-fold and tablet emulators (standalone chrome, navigation per size/posture, measured animations, dialogs, scroll, launch), plus the lab tool. **Read when:** porting any Android surface, or re-capturing the PWA reference. Baseline expectations for the native app: [android-gaps.md](android-gaps.md).

Captures live outside the repo in `C:\Users\sfent\workspace\showcase\pwa\android\<AVD>[-<posture>]\` (physical-display PNGs + `.json` sidecars with API level, `wm size`/density, posture, device state and top activity; ≤2 MB 540p clips; `*.anims.json`; `*.log.json`); raw `screenrecord` files in `~/.fst-tools/pwa-raw/android/`. Media is never committed. Safety is as on [Windows](windows.md): no typing into global/profile search, no player/band pages, and the [service-safety](../../platforms/service-safety.md) endpoints blocked through `Network.setBlockedURLs`.

## Lab: `tools/android/pwa.py`

| Command | Effect |
|---|---|
| `setup --avd A [--force]` | Chrome first run, then install. Idempotent: skips when the home screens already show the **FST** icon |
| `launch --avd A [--posture P] [--reset-storage] [--route /x] [--record clip.mp4] [--shot x.png]` | Opens the app from its home-screen icon; `--reset-storage` is a cold start (HOME, `am kill`, icon) plus cleared web storage |
| `drive --avd A [--posture P] [--reset-storage] --steps …\|--steps-file f [--out-dir D] [--record clip.mp4] [--log f.json]` | Shared journey steps ([windows.md](windows.md#lab-toolswindowspwapy)) with touch input, plus `shot:` (physical display, includes system bars), `back`, `home`, `posture:`, `rotate:`, `relaunch`, `record:start:`/`record:stop` |
| `motion raw.mp4 [--crop]` | Frame-difference bursts, as on Windows |

Every command holds the `emulator` lock (≤300 s, `device.py` helpers) and boots the AVD if needed. Holds run with system animations at 1× and restore 0 afterwards.

| Step / gotcha | Detail |
|---|---|
| Chrome first run (Chrome 149) | *Manage* link at the end of the footer → usage/crash switch **off** → *Done*; **Stay signed out**; notifications **No thanks**. Nothing else is accepted |
| Install | ⋮ (`id/menu_button`; its description changes to "Update available…" when Chrome is stale) → **Add to Home screen** → **Install** → launcher **Add to home screen**. The `google_apis` images cannot mint a WebAPK (no signed-in Play Store), so Chrome pins a shortcut (`ACTION_START_WEBAPP`, `webapp_display_mode=3` standalone); no `org.chromium.webapk.*` package exists |
| Launch surface | `com.android.chrome/org.chromium.chrome.browser.webapps.WebappActivity`: standalone, no URL bar |
| Icon placement | The pinned icon lands on the next free home page; `find_icon` pages right from HOME |
| Reduced motion | Chrome reports `prefers-reduced-motion: reduce` when `animator_duration_scale` is 0 — the FST AVDs' default. PWA captures must run at 1× |
| Cold start | `am kill` after HOME, not `am force-stop` (leaves Chrome "stopped") |
| DevTools | `adb forward tcp:9444 localabstract:chrome_devtools_remote`; the webapp page is a normal page target of Chrome |
