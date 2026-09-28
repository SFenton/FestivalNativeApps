# Installed PWA reference: Windows (Edge app)

> **What:** how the web app behaves when installed as an Edge app on Windows (window chrome, navigation per window size, animations with measured durations, dialogs, scroll, first paint), plus the lab tool that reproduces it. **Read when:** porting any Windows surface, or re-capturing the PWA reference. Gaps vs the native app: [windows-gaps.md](windows-gaps.md).

Captures live outside the repo in `C:\Users\sfent\workspace\showcase\pwa\windows\<preset>\` (screenshots + `.json` sidecars, ≤2 MB 540p H.264 clips, `*.anims.json`, `*.log.json`); full-frame-rate raw clips for frame stepping in `~/.fst-tools/pwa-raw/windows/`. Media is never committed. Production is read-only here: journeys never type into global/profile search (band search is blocked) and never open player or band pages, and every attached page blocks the [service-safety](../../platforms/service-safety.md) endpoints with `Network.setBlockedURLs`.

## Lab: `tools/windows/pwa.py`

| Command | Effect |
|---|---|
| `start` / `stop` | Isolated Edge (`~/.fst-tools/pwa-edge` profile, DevTools port 9377, no windows, no sync/sign-in) |
| `install [--force]` | Opens the site in a tab and drives Edge's own UI through `uiwin.py`: address-bar **App available → Install**, then **Don't allow** on the *App installed* flyout (no pins, no auto-start) |
| `uninstall` | Stops Edge and deletes the isolated profile |
| `launch [--fresh] [--reset-storage] [--preset P] [--route /x] [--record clip.mp4] [--shot x.png]` | `msedge --app-id=<id>` exactly like the Start-menu shortcut; `--reset-storage` clears local/session storage so first-run carousels return; with `--fresh --record` the clip starts before the window exists (splash) |
| `resize <preset\|WxH>` / `window` | `Browser.setWindowBounds` in DIPs on the **secondary monitor**, same presets as `uiwin.py` |
| `shot out.png [--content]` | Window incl. title bar via gdigrab (window raised topmost for the grab), or page pixels only |
| `drive --steps …\|--steps-file f [--out-dir D] [--record clip.mp4] [--fps N] [--log f.json]` | Shared journey steps (below) |
| `motion raw.mp4 [--crop w:h:x:y]` | Frame-difference bursts (mean luma delta > 0.04 between consecutive frames) |
| `contact DIR out.png [--glob]` | Contact sheet for review |

Steps (shared with Android, `tools/android/cdp.py`): `click|tap|hover|waitfor|scrollto:<sel>[@s]` with `css=`, `text=`, `contains=`, `aria=`, `testid=` or `x,y`; `scroll:<dy>`; `key:alt+left`; `type:`; `route:/path` (sets `location.hash`, an in-app transition); `nav:` (full load); `anims:start` / `anims:stop:<json>` (DevTools `Animation` domain: type, property/name, duration, delay, easing, node); `timing:<json>`; `cshot:`; `eval:`; plus `shot:`, `resize:`, `back` (Alt+Left), `record:start:<mp4>`/`record:stop`. A leading `?` makes a step optional. Journeys: `tools/android/pwa_journeys/*.steps` (`pages`, `pages-settled`, `nav`, `songs`, `search`, `song-detail`, `leaderboards`, `shop-settings`).

| Gotcha | Detail |
|---|---|
| No `PWA.install` in Edge | Edge 155 lists the DevTools `PWA` domain but answers "wasn't found" for `PWA.install`/`PWA.launch`/`getOsAppState`, on browser and page sessions; install therefore goes through the real UI |
| Occlusion | gdigrab grabs screen pixels. Other lanes centre their native windows on the primary monitor, which bled into the first clips, so the lab uses the last non-primary monitor (`FST_PWA_MONITOR` overrides) and raises the window topmost only while grabbing |
| ffmpeg | The operator's `workspace/ffmpeg` build is `--disable-avdevice` without libx264 (no gdigrab, no H.264). The lab uses the BtbN GPL 8.1 build in `~/.fst-tools/ffmpeg/` (`FST_FFMPEG` overrides) |
| gdigrab rate | Asking 60 fps yields ~38 fps delivered at 755×1191 px; durations below one frame (~26 ms) are not resolvable from video — use `anims:` timings |
| Hash routes | The site uses `HashRouter` (`FortniteFestivalWeb/src/App.tsx:266`): deep links are `/#/songs/…` |
| Paths from Git Bash | Write step paths as `C:/…`; MSYS does not convert paths inside `--steps` |

## Installed-app window chrome

| Aspect | Observed (Edge 155 Beta, `display: standalone`) |
|---|---|
| Title bar | Edge-drawn, filled with the manifest `theme_color` `#1A0830`; app icon, text `Festival Score Tracker - <document.title>` (e.g. "… - Songs \| Festival Score Tracker"), then **⋯** (app menu), minimize/maximize/close. No back button and no URL; while loading the title briefly shows the origin (`compact/launch.mp4`) |
| Launch | Win11 open animation, then a theme-coloured window with the web loader spinner for ~0.7 s, then content (`compact/launch.mp4`, `wide/launch.mp4`). Measured: window target 0.23–0.42 s after `--app-id`; first paint 112–120 ms, FCP 0.5–1.2 s, LCP 0.5–1.8 s after navigation start (`*/launch.json`; varies with the live API) |
| Window placement | Reopens at the last closed bounds (the launch clip shows the previous size before the preset applies) |
| Back | No title-bar back; Alt+Left and the in-page **‹ Back** link go back through hash history |
| Install flyout | *App installed* offers taskbar/Start/desktop pins and **Auto-start on device login**; the lab declines all |

## Layout per window size

The installed app always uses the **mobile shell**: `useIsMobileChrome()` is true whenever `IS_PWA` (`FortniteFestivalWeb/src/hooks/ui/useIsMobile.ts:14-17`), whatever the width. Every preset (`compact` 500×800 … `maximized` 2560×1392 epx) shows hamburger + page title + profile/search icons at the top, a bottom tab bar (anonymous: Songs, Leaderboards, Settings) and the floating FAB dock (Search pill, Sort, Quick Links / pink menu). There is no pinned sidebar even at 2560 epx.

| Preset | Content |
|---|---|
| compact / snap halves / portrait-tablet | Single column; Song Detail intensity grid 3×3 icons without labels; leaderboards one instrument per card |
| medium (900) | Single column, wider rows |
| wide (1440) / full-screen / maximized | Content column capped (~1360 px at maximized, centred); leaderboards two cards per row; Song Detail shows instrument leaderboards two per row (`wide/song-detail.png`, `maximized/leaderboards.png`) |

## Navigation

| Surface | Behaviour (measured) |
|---|---|
| Bottom tabs | Tap switches route; tab label/icon colour transition 150 ms `ease` (`compact/nav.anims.json`). No slide: content re-enters with the row stagger below |
| Drawer (hamburger) | Anonymous items: Songs, Leaderboards, Item Shop; bottom: Select Profile, Settings (`compact/nav-drawer.png`). Slides from the left: `transform` + scrim `opacity` 250 ms `ease` (`wide/nav.anims.json`; `Sidebar.tsx:19,129-134`); frame-stepped, most movement lands in ~4 frames (~120 ms, `compact/nav.mp4`). **Escape does not close it** (no key handler; `compact/nav-drawer-after-escape.png`); scrim tap or navigation does |
| Route change | Background art crossfades 1000 ms `ease`; list rows `fadeInUp` 400 ms ease-out (opacity 0→1, translateY 12→0 px) staggered 125 ms per row; Song Detail sections 300 ms staggered 60 ms (`*.anims.json`; `FortniteFestivalWeb/src/styles/animations.css:18-21`, `hooks/ui/useStagger.ts`). DevTools reports these keyframe easings as `linear`; the source sets `ease-out` |
| Anonymous player routes | `/rivals`, `/rivals/all`, `/statistics`, `/suggestions`, `/compete` redirect to Songs; `/bands` (no id) shows **Band not found** (`compact/*.png`) |

## Background

`AnimatedBackground` cycles album art: 5 s per image, 1 s opacity crossfade, and a 6 s linear Web Animation per image choosing one of 10 zoom/pan presets (scale 1.0↔1.12 or 1.18 with ±14–18 px pans) (`FortniteFestivalWeb/src/components/shell/AnimatedBackground.tsx:7-37`). Measured: `WebAnimation` 6000 ms linear + `opacity` 1000 ms `ease` on every page (`*.anims.json`). A new route immediately swaps to that page's art. `reducedMotion` stays false in the installed app (`launch.json`).

## Dialogs and sheets

| Surface | Behaviour |
|---|---|
| First-run carousels | Per page, on first visit (Songs, Song Detail, Leaderboards, Player History, Shop …), plus **What's New** after the first launch (`compact/*-first-visit.png`). Slide change: card content 200 ms fades, title/description `fadeInUp` 400 ms at 300/375/500 ms delays; demo rows animate on a 6 s loop (`compact/fre-carousel.anims.json`, `fre-carousel.mp4`) |
| Sort / Quick Links | Bottom sheet over a dimmed page: `transform` + `opacity` 300 ms `ease`; frame-stepped open ≈ 280 ms, close ≈ 180 ms (`compact/songs.mp4`). Escape closes |
| Global search / profile sheet | Same sheet pattern at 250 ms; tabs Songs / Players / Bands; "Enter at least two characters" (`compact/search-open.png`, `profile-sheet.png`) |
| Paths modal | Opens from **View Paths**; it needed two Escapes. `PathsModal.tsx:240-247` ignores Escape while its *Some Instruments Unavailable* alert (OK / Don't show again) is up, which Android captured on open (`android/FST_Phone/song-detail-paths.png`) |
| FAB search | Pill expands (`width`/`flex-basis` 360 ms `ease`) into a local Songs filter with a **Clear Search** ✕; the filter persists across routes until cleared (`compact/songs-search.png`) |

## Scroll

- Songs: letter section headers scroll with the list (not sticky); the top bar stays; a 2500 px wheel gesture keeps moving ~2.1 s (`compact/songs.mp4`).
- Song Detail: the song header (art, title, artist · year · length) stays pinned while intensity and leaderboards scroll under it (`compact/song-detail-scrolled.png`).
- Leaderboards/Song leaderboard: fixed paginator « ‹ n / N › » above the tab bar (`compact/song-leaderboard-page2.png`, `full-rankings-page2.png`).
- Album art and row images fade in at 300 ms `ease`; Item Shop songs pulse (2 s loop) in the Songs list.

## Last measured

| Item | Value |
|---|---|
| Captures | 222 PWA screenshots over 8 presets, 15 clips (compact + wide journeys, launch, resize); 48 native screenshots |
| Environment | 2026-09-28, Edge 155.0.4283.18 Beta, Windows 11 25H2 (26220), 150 % scale, live production data |
