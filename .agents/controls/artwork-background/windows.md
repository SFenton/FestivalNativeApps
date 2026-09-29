# Artwork background — Windows notes

> **What:** the WinUI composition backdrop, its policy and measured cost. **Read when:** changing `windows/Festival.App/Controls/ArtworkBackground.cs` or `ArtworkCarousel`/`ArtworkPlaybackPolicy`. Behavior: [spec.md](spec.md).

## Architecture

- One `ArtworkBackground` (a `Grid` hosting a child `ContainerVisual`) sits behind the section frames inside the `NavigationView` content area, so tab switches and pushes never restart it.
- Visual tree: two carousel `SpriteVisual` slots, one song-cover sprite, one black dim sprite (0.7). Slots **and the dim sprite** are oversized by a 24 px bleed so ≤18 px pans never show an edge and DPI rounding of the host size can never leave an undimmed row or column.
- Every 5 s a `DispatcherQueueTimer` loads the next cover (bounded byte cache → `LoadedImageSurface` decoded at ≤1024 px) and crossfades it in above the old slot. The old surface is disposed after the fade.
- Motion is `KeyFrameAnimation`s on the composition thread: opacity crossfade (1 s, 60 steps/s) and zoom/pan drift (6 s, one of the web's ten `MOTION_PRESETS`, translation scaled like CSS `scale() translate()`, **30 steps/s**). The step easing lets the compositor skip frames where nothing changed, so the cost doesn't scale with the display refresh rate. `--drift-fps N` overrides (0 = continuous).
- Song Detail: `ShowSong` fades the static cover in (0.5 s, opacity only) and freezes the carousel (animations stopped at their current frame); returning starts the next crossfade and drift at once. Motion is stopped rather than `AnimationController.Pause`d, so an unseen window holds no running composition animation.

## Policy (`ArtworkPlaybackPolicy`)

| Input | Result |
|---|---|
| In-app Save Data / `--no-art` | Hidden: no art, no dim, surfaces released |
| Window minimized or hidden, or shown but unseen (fully covered, cloaked on another virtual desktop, session locked, display off) | Paused: timer stopped, motion frozen at the current frame; resuming starts the next crossfade |
| Windows "Animation effects" off, in-app Reduce Motion or Disable Animated Artwork | Static single cover |
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

## Tests

`ArtworkCarousel` (shuffle, ≤100, cycling, failure budget, preset bounds) and `ArtworkPlaybackPolicy` (every input) and `WindowOcclusion` (coverage union, holes, fragment cap, which windows count) are unit-tested in Core. The composition code itself is covered only by screenshots and perf runs.
