# Installed PWA reference: Apple devices

> **What:** how the real festivalscoretracker.com PWA looks and moves when installed to the Home Screen on the Apple simulators, measured from recordings, plus the tool that reproduces it. **Read when:** matching a native Apple screen, transition or chrome to the web app; re-capturing the reference. Gaps against our app: [apple-gaps.md](apple-gaps.md).

Captured 2026-09-28 against production (web 0.1.133). Media lives in `~/FestivalShowcase/pwa/<device>/` and is never committed (real player names, third-party art). Clip paths below are relative to that folder. Durations come from `python3 tools/pwa_ios.py motion <clip> --fps 30` (frame-difference runs) and frame-stepping (`frames`); the recorder is variable-frame-rate, so ±33 ms.

## Tooling

| Command (`python3 tools/pwa_ios.py …`) | Does |
|---|---|
| `install --device iphone\|ipad\|duo [--label X] [--url U]` | Safari → Share → Add to Home Screen ("Open as Web App" on). Idempotent (`stopIfExists`). iPhone goes through the More (…) menu; iPad through the Share popover's **View More** (never swipe: it dismisses the popover) |
| `drive --target springboard --steps "home; launchIcon:FST; …" [--record x.mp4]` | Runs `apple/Apps/iOSUITests/PWADriverTests.swift` against Safari / SpringBoard / `com.apple.webapp` under the shared sim lock (same cached build as `ios_sim.py drive`). Extra verbs: `launchIcon`, `tapIfExists`, `tapContains`, `waitText`, `scroll:down,0.6`, `drag`, `edgeBack`, `clearType`, `mark:clip:<name>` / `mark:end` |
| `cut <raw.mp4> --out-dir D` | Splits a recorded run at its `clip:` marks and `avconvert`s each clip (PresetMediumQuality, ~0.3–2 MB) |
| `motion <clip>` / `frames <clip> --fps 30` | Transition start/end/duration from frame differences; exact-time PNG frames (`tools/visual/video_frames.swift`) |
| `open`, `shot`, `compress` | Open a URL in Mobile Safari; screenshot now; trim/re-encode |
| `fixture-web` | Vite dev server of the web source against `tools/mock_service.py` through a GET-only proxy that strips selected-profile headers and synthesizes `/api/service-info` |
| `mac-install`, `mac-record` | Safari File → Add to Dock via System Events; `screencapture -v` |

Rules learned the hard way:

- **Taps on web content must be on screen.** An element 7 000 pt below the viewport still "exists"; XCUITest taps its clamped centre, which hit a leaderboard row and opened a production player page (a blocked `…/stats` read; see [service-safety](../../platforms/service-safety.md)). `PWADriverTests` now refuses off-screen taps. Never script taps on production pages whose rows link to players or bands.
- The web app's own accessibility labels drive scripts: `Open navigation`, `Select Profile`, `Search`, `Sort Songs`, `Quick Links` (the purple FAB), tab `Songs`/`Leaderboards`/`Settings`, `Back`, `Close`, `Dismiss`, `Forward one entry`, `Next page`.
- Web-app processes restart at `start_url` (`/` → `/songs`) between driver runs; each script starts from Songs.
- iPhone Duo: the 27.1 web app answers each accessibility query in tens of seconds, so only launch-level scripts fit a 5-minute lock hold. `XCUIScreen` screenshots compose both panels; take Duo stills from the `--display outer` recording (`frames`). A pre-existing "FST" clip on the Duo points at a LAN dev server; ours is "FST PWA".
- Fixture origin: installs and runs (as "FST Fix", `http://127.0.0.1:14175`), but it is Vite dev mode (TanStack devtools button, no album art, so no animated background, black strip under the tab bar) and **Select Profile does not open** there. Selected-profile states therefore still come from source and the Playwright harness ([web-reference.md](../web-reference.md)). TODO(orchestrator): a production-mode fixture build (`vite build` + `preview`) would remove the dev-mode artifacts.
- macOS: the responsible app has neither Accessibility nor Screen Recording permission (`screencapture` → "could not create image from display"), so `mac-install`/`mac-record` stop with instructions. Manual route: Safari → open the site → File → Add to Dock… → Add; the web app lands in `~/Applications`. No macOS captures yet.

## Capture index

| Device | Stills | Clips | Highlights |
|---|---|---|---|
| iPhone 17 Pro, 26.5 (`ios/`) | 39 | 31 | full anonymous tour, landscape, Paths, local search |
| iPad Pro 11, 26.5 (`ipad/`) | 17 | 12 | first launch, carousel, sheets, landscape |
| iPhone Duo folded outer, 27.1 (`duo-folded/`) | 4 | 2 | first launch (slow), carousel |
| Native iPhone for comparison (`native-ios/`) | 16 | 8 | same states via `ios_sim.py drive --record` |

Pages covered (production, anonymous): Songs, Song Detail, Leaderboards, Full Rankings, Settings, Item Shop, home redirect. Not covered: Song Leaderboard (its only link on Song Detail sits beside player rows; capture it by URL next time), and every selected-profile page (Statistics, Suggestions, Rivals, Compete, Player History/Bands, notifications) plus Player Profile and Band pages, whose reads are blocked in production.

## First launch and loading

| Observation | Clip |
|---|---|
| Icon zoom 0.25 s to black, then a **white** WebKit page ~1.2 s (manifest `background_color` is black but is not used), then a purple splash with a small ring spinner, then content 3.1–3.9 s after the tap | `ios/first-launch-splash.mp4`, `ios/first-launch-1s.png` |
| iPad shows the same white page at 1.5 s | `ipad/first-launch.mp4`, `ipad/first-launch-splash.png` |
| Duo 27.1: white page for ~75 s before first paint (simulator network/JS start; treat as an outlier) | `duo-folded/first-launch-tap-white.mp4`, `first-paint-carousel.mp4` |
| First paint of Songs shows the full list at once; the animated background art is behind it from the first frame | `ios/first-launch-5s.png` |
| On first launch the Songs **first-run carousel** (6 slides, live demo rows, pulsing highlight) opens as a centred card, then a **What's New · 0.1.133** changelog card with a full-width Dismiss | `ios/changelog-dismiss.mp4`, `ipad/first-run-carousel.mp4` |
| Song Detail has its own 5-slide carousel on first visit (Top Scores, Optimal Paths…) | `ios/song-detail-fre.mp4` |

## Navigation and transitions

| Transition | Measured | Clip |
|---|---|---|
| Tab switch (bottom bar) | **Hard cut** in one frame, new background artwork cuts in with it; no cross-fade, no slide | `ios/tab-songs-to-leaderboards.mp4`, `tab-settings.mp4` |
| Push (song row → Song Detail) | Row press highlight ~200 ms, cut to an empty page with header art, content fades in over ~300 ms (≈500 ms total); no horizontal slide | `ios/song-detail-push.mp4` |
| Pop | Header `‹ Back` only; a leading-edge swipe does **nothing** in the standalone web app (it scrolled content instead) | `ios/song-detail-edge-back.mp4` |
| Full rankings push / back | Same cut + fade; back restores the previous scroll position | `ios/full-rankings-push.mp4`, `full-rankings-back.mp4` |
| Pagination | `Next page` swaps rows in place (~100 ms), page label `2 / 34,757` | `ios/full-rankings-scroll-paginate.mp4` |
| Drawer | Slides from the leading edge in ~170–230 ms over a dim; ~56% width; closes the same way; current route row filled purple | `ios/drawer-open-close.mp4`, `drawer-item-shop.mp4` |
| Rotation | Layout reflows to landscape (manifest `orientation: any`); phone keeps the portrait layout full-width | `ios/rotate-landscape.mp4`, `ipad/rotate-landscape.mp4` |

## Sheets and modals

| Surface | Presentation | Clip |
|---|---|---|
| Sort Songs | Dim ~100 ms, then a bottom sheet rises (~330 ms total); radio list, direction arrows, red Reset, Apply; X to close (~230 ms) | `ios/songs-sort.mp4` |
| Quick Links (purple FAB) | Bottom sheet with a letter list, current letter as a purple pill (~300 ms in, ~200 ms out) | `ios/songs-quicklinks.mp4` |
| Global search (header magnifier) | Sheet titled "Search", field on top, empty hint centred, scope chips **Songs / Players / Bands at the bottom** (~170–200 ms) | `ios/global-search.mp4` |
| Select Profile | Same Search sheet with Players / Bands only | `ios/profile-sheet.mp4` |
| Paths | Sheet with the path image, instrument/difficulty/format pickers at the bottom, plus an "Some Instruments Unavailable" alert (OK / Don't show again) on first open | `ios/paths-modal.mp4` |
| iPad | Search/Profile become a centred floating dialog (~50% width); Sort stays a large bottom panel | `ipad/global-search.mp4`, `ipad/songs-sort.png` |

## Shell, scroll and header

| Observation | Clip |
|---|---|
| Header: hamburger, page title (no large title), `Select Profile` (person+) and `Search`; detail pages swap the hamburger for `‹ Back`. The header never collapses | `ios/songs-top.png`, `song-detail-top.png` |
| Bottom dock above the tab bar: Search pill · Sort button · purple Quick Links FAB (Songs); FAB alone on Leaderboards/Settings; Song Detail adds floating **View Paths** (and **Item Shop** when the song is in the shop) | `ios/songs-top.png`, `song-detail-2.png` |
| Songs search pill turns into an inline field above the keyboard with the iOS form accessory bar; filters locally (section headers remain) | `ios/songs-search-type.mp4` |
| Scrolling rows fade out under the header (gradient mask); section header `#`, `A`… scroll with rows; no section index scrubber | `ios/songs-scroll.mp4` |
| Song Detail keeps a pinned compact song header (art + marquee title) while the cards scroll | `ios/song-detail-scroll.mp4` |
| Shop-state outlines on song rows (green = in shop, gold = new, red = leaving) pulse | `ios/songs-top.png` |
| Background: slow continuous drift of blurred, darkened album art (always moving at low amplitude); a new artwork set per page, cut in on navigation | `ios/tab-settings.mp4` (idle 4–9 s) |

## Standalone chrome and safe areas

| Observation | Evidence |
|---|---|
| No Safari UI; status bar is `black-translucent`: background art runs under the status bar, header starts below it | `ios/songs-top.png` |
| Tab bar is a flat full-width bar with icons + labels, extending through the home-indicator area | `ios/songs-top.png` |
| Landscape phone: header content inset from the Dynamic Island side; about two rows of content between header and dock | `ios/songs-landscape.png` |
| iPad portrait and landscape keep the phone layout (single column, bottom tab bar); Song Detail rows gain season/instrument badges | `ipad/song-detail-top.png`, `ipad/songs-landscape.png` |
| Duo folded outer display gets the phone layout; status bar sits right of the camera cutout | `duo-folded/first-paint.png` |
