# Artwork background — Windows notes

> **What:** the WinUI composition backdrop, its policy and measured cost. **Read when:** changing `windows/Festival.App/Controls/ArtworkBackground.cs` or `ArtworkCarousel`/`ArtworkPlaybackPolicy`. Behavior: [spec.md](spec.md).

## Architecture

- One `ArtworkBackground` (a `Grid` hosting a child `ContainerVisual`) sits behind the section frames inside the `NavigationView` content area, so tab switches and pushes never restart it.
- Visual tree: two carousel `SpriteVisual` slots, one song-cover sprite, one black dim sprite (0.7, **only while a cover is drawn**: it fades with the crossfade or cover fade, or cuts when static, so no-art shows the brand surface undimmed like the web and iOS; issue #217). Slots **and the dim sprite** are oversized by a 24 px bleed so ≤18 px pans never show an edge and DPI rounding of the host size can never leave an undimmed row or column.
- Every 5 s a `DispatcherQueueTimer` loads the next cover (bounded byte cache → `LoadedImageSurface` decoded at ≤1024 px) and crossfades it in above the old slot. The old surface is disposed after the fade, but only while the new slot is still the front one: the batch completion arrives later, and a freeze plus resumed swap in between can reuse the old slot as the new front (issue #217 blanked the shown cover that way).
- Motion is `KeyFrameAnimation`s on the composition thread: opacity crossfade (1 s, stepped like the drift: 30 steps/s since issue #83) and zoom/pan drift (6 s, one of the web's ten `MOTION_PRESETS`, translation scaled like CSS `scale() translate()`, **30 steps/s**). The step easing lets the compositor skip frames where nothing changed, so the cost doesn't scale with the display refresh rate. `--drift-fps N` overrides (0 = continuous).
- Song Detail: `ShowSong` fades the static cover in (0.5 s, opacity only) and freezes the carousel (animations stopped at their current frame); returning starts the next crossfade and drift at once. Motion is stopped rather than `AnimationController.Pause`d, so an unseen window holds no running composition animation.

## Policy (`ArtworkPlaybackPolicy`)

| Input | Result |
|---|---|
| In-app Save Data / `--no-art` / a Windows contrast theme | Hidden: no art, no dim, surfaces released (contrast: content sits on the theme's window colour) |
| Window minimized or hidden, or shown but unseen (fully covered, cloaked on another virtual desktop, session locked, display off) | Paused: timer stopped, motion frozen at the current frame; resuming starts the next crossfade |
| Windows "Animation effects" off, in-app Reduce Motion or Disable Animated Artwork | Static single cover |
| A `ContentDialog` is open (first-run, What's New, confirmations; `MainWindow.ShowDialogAsync` sets `ModalOpen`) | Paused, like an unseen window: the dialog's smoke layer covers the backdrop. Hidden and Static still win. Closing the dialog resumes with an immediate crossfade (issue #83) |
| Otherwise | Animated (keeps running when focus moves to a game) |

Occlusion (`Services/OcclusionTracker.cs`, rules in Core `WindowOcclusion`) follows Chromium's native window occlusion tracker: out-of-context `SetWinEventHook`s (foreground, move/size end, minimize, show/hide, top-level location change, cloak/uncloak; own process skipped) plus the window's own activation, move, resize and Z-order changes schedule **one debounced (150 ms) Z-order walk** on the UI thread, so nothing runs while the desktop is idle. The walk collects windows above the app (`GW_HWNDPREV`) that are visible, not minimized, not cloaked, not click-through (`WS_EX_TRANSPARENT`, e.g. FPS overlays), not region-shaped and not translucent layered, and subtracts their DWM frames from the app's on-screen frame; only a fully covered frame counts (unknown shapes keep animating). A window subclass also pauses on `WTS_SESSION_LOCK` and console-display-off (`GUID_CONSOLE_DISPLAY_STATE`). Transitions are logged as repeatable `occlusion-<covered|cloaked|locked|display-off|visible>=<ms>` perf-log lines.

The host spans the whole window (`MainWindow` row span 2, behind the transparent title bar and pane); the composition root's `InsetClip` keeps the bleed and drift scale inside it. Covers that fail to load are logged and skipped: at most three immediate attempts per tick, five failures per pool.

## Last measured

1280×820 window at 150% on a 3840×2160 240 Hz display (RTX 5090), Release ReadyToRun, 30 s:

| State | App CPU (one core) | GPU 3D | DWM CPU (machine) |
|---|---|---|---|
| Continuous drift (every frame) | ~15% | 8.4% | 0.9% |
| 30-step drift + 60-step crossfade (default) | 4.6% | 1.0% | 0.3% |
| Static / no art / minimized | 0.1% | 0% | 0.15% |

Occlusion pause (2026-09-28, NativeAOT Release, Songs, same window; `perf.ps1 -Scenario animated|occluded|minimized -Aot`, sampling starts only after the app logs `occlusion-covered`; other lanes' apps were running on the desktop):

| State | App CPU (one core) | GPU 3D | DWM CPU (machine) |
|---|---|---|---|
| Animated, visible (4 runs) | 3.9–5.5% | 1.2–1.35% | 0.6–0.9% |
| Fully covered by an opaque window (7 runs) | 0.3–2.2% | 0.37–0.46% mean; **0.00 per second for the first 15–25 s**, then intermittent 0.5–2.6% bursts | 0.2–1.0% |
| Covered, Reduce Motion | 0.1% | 0.01% | 0.4% |
| Static (Reduce Motion), visible | 0.2% | 0.00% | 0.5–0.7% |
| Minimized | 0.2% | 0.00% | 0.6% |

The backdrop itself goes idle when covered (`backdrop-paused` logged, no swaps, GPU 0.00). The later bursts are **not** the backdrop: hiding its root visual while paused didn't change them, the occlusion hooks fired only 16 times in 45 s, and disabling `MarqueeText` didn't remove them. One burst began exactly when a `PrintWindow` capture ran. Open issue: identify them with an ETW/WPR trace (needs elevation), then decide whether XAML-side work should also stop while covered.

## Issue #83: dialogs and first run

2026-10-02, Release, same 1280×820 window at 150% on the 240 Hz display, `perf.ps1 -Seconds 30 -Warmup 20`, display on (no `occlusion-*` lines). Release launches show What's New unless `--whats-new off`.

| State | Before: app CPU (one core) / GPU 3D | After |
|---|---|---|
| Settings under the first-run dialog (`--first-run force`) | 10.1% / 3.2% | 2.2% / 0% |
| Songs under the first-run dialog | 11.7% / 3.2% | 3.4% / 0.36% |
| Settings under What's New | 9.8% / 3.4% | 1.7% / 0% |
| Settings, no dialog (`--whats-new off`) | 9.6% / 2.7% | 6.4–7.3% / 2.7% |
| Settings, Reduce Motion | 2.2% / 0% | unchanged |

Causes: the backdrop kept animating under dialogs, and the first-run demos ran Shop pulse rings and breathing fills on every slide, including off-screen ones, with the breathe as a cubic-bezier keyframe sampled at display refresh. The remaining visible-page cost is the 30-step drift and crossfade by design. UIA check: `invoke:id=CloseButton` on the first-run dialog logs `backdrop-animated` and `backdrop-swap-animated` right after the earlier `backdrop-paused`.

## Tests

`ArtworkCarousel` (shuffle, ≤100, cycling, failure budget, preset bounds) and `ArtworkPlaybackPolicy` (every input, including `ModalOpen`) and `WindowOcclusion` (coverage union, holes, fragment cap, which windows count) are unit-tested in Core, as is `ArtworkBackgroundStatus` (state names, dim only over art; `ArtworkBackgroundStatusTests`). The composition code is covered by the UIA state journeys below, screenshots and perf runs.

## UI Automation state (issue #217)

The backdrop is decorative: `AccessibilityView.Raw`, so Narrator and the UIA control view skip it, and Axe.Windows reports nothing for it. It still has a raw-view `FrameworkElementAutomationPeer` (a `Grid` has none by default) with AutomationId `fst.shell.artwork-background` and its state as **ItemStatus**:

| ItemStatus | When |
|---|---|
| `animated` | Covers rotate with crossfade and drift |
| `reduced-motion` | One still cover: Windows Animation effects off, in-app Reduce Motion or Disable Animated Artwork |
| `save-data` | No art and no dim: in-app Save Data, `--no-art` or a contrast theme (the contrast background replaces the brand surface) |
| `not-visible` | Frozen at the current frame: minimized, hidden, fully covered, locked, display off or under a dialog |
| `no-art` | Nothing drawn yet or nothing loadable (catalogue without art, every cover failed, song without art); also while paused before the first cover loads |
| `song-cover` | The static, dimmed song cover (Song Detail, Solo leaderboard) |

Journeys (`uiwin` `assertstatus:id=fst.shell.artwork-background|<status>[@secs]`): `tools/windows/journeys/artwork-background.json` (animated, Reduce Motion, Disable Animated Artwork, Save Data, dialog and minimized `not-visible` with resume, song cover), `artwork-background-system.json` (`ab-contrast` under `--mode hc-*`, `ab-system-static` under `--mode no-animations`) and `artwork-background-no-art.json` with `--fixture tools/windows/artwork_fixture.py` (every `/__fixture__/art/*` read is a 404).
## Validation (issue #217)

2026-10-03, Debug x64 on the 3840×2160 300% host. Fixture runs: `a11y_matrix.py --scan --tabs 30` with the three `artwork-background*.json` journeys; live runs: the public service without `--base-url` (Songs, 731 songs, and Song Detail for *Butter*), each asserting the backdrop's ItemStatus before the shot. Axe.Windows reported 0 errors in every fixture run.

| Configuration | Fixture (journeys) | Live public service | Finding |
|---|---|---|---|
| Compact, medium, wide | animated, song cover, no art (Songs and song), minimized `not-visible` → animated: PASS | Songs `animated`, Song Detail `song-cover` | Cover fills the window at every width; no-art showed near-black (fixed) |
| Maximized, snap-left | animated, song cover, minimized: PASS | Songs `animated` | Fills the work area; no letterboxing |
| Dark and light system theme | animated, song cover at C/M/W: PASS | `animated` | The backdrop and dim are theme-independent by design (brand surface); cards follow the app's dark theme |
| Desert, Night sky (contrast) | `save-data` at C/M/W: PASS | `save-data` | No art or dim; the system window colour shows, text keeps system contrast |
| Windows Animation effects off | `reduced-motion` at C/M/W: PASS | `reduced-motion` | One still cover, no drift or crossfade |
| In-app Reduce Motion, Disable Animated Artwork | `reduced-motion`: PASS | `reduced-motion` | Same still cover |
| In-app Save Data | `save-data`: PASS | `save-data` | Undimmed brand surface, no art requests |
| Dialog open (Settings reset) | `not-visible`, then `animated` after Esc: PASS | same | Freezes under the dialog and resumes; the cover no longer blanks after resume (fixed) |
| Minimized and restored | `not-visible` → `animated`: PASS | same | — |
| Text 200% | animated, song cover at C/M/W: PASS | `animated` | Backdrop unaffected; it has no text |
| Display 100%, 150% | animated, song cover at C/M/W: PASS | `animated` | Cover scales with the window, no blur seams |
| Keyboard | 30-press Tab walks in every run (5–8 stops) never land on the backdrop | — | Not focusable, no Narrator stop (`AccessibilityView.Raw`) |

`no-art` can't be reached against the live service (every catalogue song has art); it is covered by `artwork_fixture.py`, whose screenshots show the undimmed brand purple.
