# Artwork background (`fst.shell.artwork-background`) — spec

> **What:** platform-neutral behavior of the animated album-art backdrop. **Read when:** touching backgrounds, motion or transitions on any platform. Platform notes: [ios.md](ios.md).

Source: `FortniteFestivalWeb/src/components/shell/AnimatedBackground.tsx:7-250`, `FortniteFestivalWeb/src/components/page/BackgroundImage.tsx:16-57`.

## Behavior

- Songs and Settings rotate at most **100 shuffled** album covers; Detail and Solo leaderboard show a **static, dimmed** song cover.
- Each image shows ~5,000 ms; switching takes a 1,000 ms crossfade; a slow 6,000 ms zoom/pan uses one of ten presets (scale ≤1.18, translation ≤18 logical units).
- Black dim layer at 0.7 alpha behind readable content.

## States

`no-art`, `animated`, `reduced-motion` (one static image), `save-data` (no images **and** no overlay), `not-visible` (timer/animation paused), plus static detail art. Animation follows system accessibility and the app's additive overrides.

## Native requirements (all platforms)

- Use platform data-saver, visibility and low-power signals. Never download 100 images at once: load one ahead; cache only in process; predecode to displayed size; measure scrolling/frame delivery.
- Artwork is decorative: hidden from accessibility, never takes taps. Never bundle third-party art; only original synthetic fixtures.
- Failed covers are logged and skipped without stopping a valid successor; never replace a failure with success-shaped imagery.
- Retry pacing: at most three immediate attempts, then wait for the five-second deadline before up to two more within a five-failure publication-pool budget, so three 404s cannot hide a valid fourth cover. Tests measure the deadline from when playback **starts** (before the first GET), allow a busy host to observe four or five requests after the legal dwell, and never assert "exactly three when polled".
