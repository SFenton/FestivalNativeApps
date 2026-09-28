# Artwork background — Windows notes

> **What:** the WinUI composition backdrop, its policy and measured cost. **Read when:** changing `windows/Festival.App/Controls/ArtworkBackground.cs` or `ArtworkCarousel`/`ArtworkPlaybackPolicy`. Behavior: [spec.md](spec.md).

## Architecture

- One `ArtworkBackground` (a `Grid` hosting a child `ContainerVisual`) sits behind the section frames inside the `NavigationView` content area, so tab switches and pushes never restart it.
- Visual tree: two carousel `SpriteVisual` slots, one song-cover sprite, one black dim sprite (0.7). Slots are oversized by a 24 px bleed so ≤18 px pans never show an edge.
- Every 5 s a `DispatcherQueueTimer` loads the next cover (bounded byte cache → `LoadedImageSurface` decoded at ≤1024 px) and crossfades it in above the old slot. The old surface is disposed after the fade.
- Motion is `KeyFrameAnimation`s on the composition thread: opacity crossfade (1 s, 60 steps/s) and zoom/pan drift (6 s, one of ten presets, **30 steps/s**). The step easing lets the compositor skip frames where nothing changed, so the cost doesn't scale with the display refresh rate. `--drift-fps N` overrides (0 = continuous).
- Song Detail: `ShowSong` fades the static cover in (0.5 s, opacity only) and pauses carousel animations with `AnimationController.Pause`; returning resumes them from the same position.

## Policy (`ArtworkPlaybackPolicy`)

| Input | Result |
|---|---|
| In-app Save Data / `--no-art` | Hidden: no art, no dim, surfaces released |
| Window minimized or hidden | Paused: timer stopped, animations paused |
| Windows "Animation effects" off, in-app Reduce Motion or Disable Animated Artwork | Static single cover |
| Otherwise | Animated (keeps running when focus moves to a game) |

Full occlusion by other windows is not detected yet (`WindowOccluded` is always false). Covers that fail to load are logged and skipped: at most three immediate attempts per tick, five failures per pool.

## Last measured

1280×820 window at 150% on a 3840×2160 240 Hz display (RTX 5090), Release ReadyToRun, 30 s:

| State | App CPU (one core) | GPU 3D | DWM CPU (machine) |
|---|---|---|---|
| Continuous drift (every frame) | ~15% | 8.4% | 0.9% |
| 30-step drift + 60-step crossfade (default) | 4.6% | 1.0% | 0.3% |
| Static / no art / minimized | 0.1% | 0% | 0.15% |

## Tests

`ArtworkCarousel` (shuffle, ≤100, cycling, failure budget, preset bounds) and `ArtworkPlaybackPolicy` (every input) are unit-tested in Core. The composition code itself is covered only by screenshots and perf runs.
