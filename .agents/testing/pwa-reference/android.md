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

## Standalone chrome and launch

| Aspect | Observed (Chrome 149, API 37, `FST_Phone` 1080×2424 @ 420, viewport 411×845 CSS px, DPR 2.625) |
|---|---|
| System bars | Status bar tinted with `theme_color` `#1A0830`, light icons. The gesture-navigation area below the web bottom tab bar is **light/white** (not themed), so a white strip with a dark handle sits under the app (`FST_Phone/*.png`) |
| No browser UI | No URL bar in `WebappActivity`; while a page is outside scope or loading, Chrome shows a thin top bar with ✕ and the origin (`FST_Phone/launch.mp4`) |
| Splash | Chrome's WebApp splash: theme-colour background, centred FST icon, "Festival Score Tracker" at the bottom (~6.5 s on the software-rendered emulator), then the web loader spinner, then content (`FST_Phone/launch.mp4`). Launch → `WebappActivity` on top 7.0 s; DOMContentLoaded 2.0 s, first paint 3.2 s (`FST_Phone/launch.json`; emulator timings, not device timings) |
| Orientation | Manifest `orientation: portrait` locks the app: rotating the phone to 90° keeps the portrait layout (`FST_Phone/rotate-landscape.png`, `rotate.mp4`) |
| Keyboard | Focusing the FAB Songs search raises the soft keyboard over the bottom bar; the dock rides above it (`FST_Phone/songs-search.png`) |
| Back | System Back walks the hash history like the in-page **‹ Back** link. Pagination adds no entries: two Backs from song leaderboard page 2 land on Songs (Songs → Detail → Leaderboard; `FST_Phone/song-detail-back.png`) |

## Layout and navigation (phone)

Same mobile shell as every other platform ([windows.md](windows.md#layout-per-window-size)): top bar (hamburger, title, profile, search), bottom tabs (anonymous: Songs, Leaderboards, Settings), FAB dock. Differences seen on the phone:

| Surface | Phone behaviour |
|---|---|
| Item Shop | List rows (art, title, artist · year, cart icon, chevron), not the art grid Windows shows at ≥500 epx (`FST_Phone/shop.png` vs `windows/compact/shop.png`) |
| Song Detail | Intensity grid two columns; leaderboard cards single column; header pins while scrolling; song-leaderboard title marquees when truncated (`FST_Phone/song-leaderboard-page2.png`) |
| Drawer | **Does not open from a touch tap.** Trace: `pointerdown → touchstart → pointerup → mousedown → click`; the tap's compatibility `mousedown` reaches `Sidebar`'s document outside-click listener and closes the drawer it just opened (`FortniteFestivalWeb/src/components/shell/desktop/Sidebar.tsx:111-118`, `usePressAction.ts:69-84`). Reproduced with DevTools touch and `adb input tap` on the emulator; confirm on hardware (TODO(orchestrator)) |
| Global search / profile sheet | Bottom sheets as on Windows; profile sheet placeholder "Search players or bands…" with Players/Bands tabs (`FST_Phone/search-open.png`, `profile-sheet.png`) |
| Paths | Opens with a *Some Instruments Unavailable — Karaoke is not available for path visualization yet* alert (OK / Don't show again) over the chart (`FST_Phone/song-detail-paths.png`) |

## Foldables, tri-fold and tablet

The web app has no fold or posture logic: it only reacts to the new viewport width. Evidence: `FST_Book_Fold-{unfolded,folded,half}/`, `FST_Passport_Fold-{unfolded,folded,half}/`, `*-postures/` (stills per posture + `posture-change.mp4`), `FST_Tablet/`.

| Device / posture | Viewport | Behaviour |
|---|---|---|
| Book Fold unfolded (2076×2152 @ 390, fold x=1038) | ~851×883 CSS px | Same single-column mobile shell stretched across the hinge: rows, cards and the FAB dock straddle the fold; no two-pane, no hinge avoidance. Leaderboards one card per row; Item Shop becomes a 3-column art grid |
| Book Fold half-open | same as unfolded | Identical to unfolded (no tabletop/book layout) |
| Book Fold / Passport folded (cover) | phone widths | Phone layout; status bar tinted `#1A0830` again |
| Passport unfolded (2208×1840 @ 420, fold x=1104) | ~841×701 CSS px | As Book Fold; landscape proportions show only ~5 song rows above the dock |
| Large screens (unfolded, tablet) | — | Status bar **not** tinted (light bar with dark icons); the Pixel launcher's taskbar tutorial covers apps until dismissed (the lab completes it) |
| Posture change | — | The page reflows in place and keeps its route (`*-postures/postures.log.json`); `screenrecord` follows one physical display, so `posture-change.mp4` shows the cover display and `posture-inner.mp4` the inner one |

Measured animations are identical to Windows (same CSS): background 6 s pan/zoom + 1 s crossfade, rows `fadeInUp` 400 ms / 125 ms stagger, Song Detail and Settings sections 300 ms, sheets 250–300 ms, bottom-tab colour 150 ms, shop pulse 2 s (`FST_Phone/*.anims.json`). `prefers-reduced-motion` is false only because the lab runs at 1× system animation scale.
