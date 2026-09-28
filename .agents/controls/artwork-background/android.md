# Artwork background — Android notes

> **What:** Compose implementation of the shared backdrop. **Read when:** touching the Android background or motion. Spec: [spec.md](spec.md).

- `BackgroundController` (app-scoped) loads the catalogue independently of Songs, picks ≤100 distinct shuffled covers once per publication, and keeps a focus stack for Song Detail's static cover. `ArtworkBackground` is hosted once under the shell.
- Motion: index changes every 5 s (one small recomposition), 1 s `Crossfade`, zoom/pan (10 presets, scale ≤ 1.18, ≤ 18 dp) read in `graphicsLayer` only; next cover pre-enqueued; failed covers skipped within a five-failure budget. Still when paused (lifecycle < RESUMED), reduced motion or `FST_DEBUG_STILL_BACKGROUND=1`; nothing on data saver.
- Images: Coil 3 with a bounded memory cache (20%), **no disk cache**; never bundled.
- Open: frame-time measurement (Macrobenchmark/JankStats), exact web retry pacing, publication-change cache clear.
