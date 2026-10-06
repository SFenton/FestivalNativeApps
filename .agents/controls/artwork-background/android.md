# Artwork background — Android notes

> **What:** Compose implementation of the shared backdrop. **Read when:** touching the Android background or motion. Spec: [spec.md](spec.md).

- `BackgroundController` (app-scoped) loads the catalogue independently of Songs, picks ≤100 distinct shuffled covers once per publication, and keeps a focus stack for Song Detail's static cover. `ArtworkBackground` is hosted once under the shell.
- Motion: index changes every 5 s (one small recomposition), 1 s crossfade, zoom/pan read in `graphicsLayer` only with the web's ten `MOTION_PRESETS` (from→to: zoom in 1→1.12, zoom out 1.12→1, pans ±18 at 1.18, diagonals ±14 at 1.18), drawn like CSS `scale() translate()` (visible offset = lerped offset × scale). Preset chosen by URL hash (web: random) so screenshots are reproducible. Next cover pre-enqueued (one ahead). Still when paused (lifecycle < RESUMED), reduced motion, Disable Animated Artwork or `FST_DEBUG_STILL_BACKGROUND=1`; a still or song cover is drawn untransformed. Nothing (no art, no dim) on Data Saver.
- **Live system signals (issue #124):** the animator scale is followed by a `Settings.Global` ContentObserver (`rememberSystemReducesMotion` in `FestivalTheme`), Data Saver by the `ACTION_RESTRICT_BACKGROUND_CHANGED` broadcast (`RECEIVER_NOT_EXPORTED` receives it on API 37) plus a re-read on each lifecycle change. Before, both were read once at launch: Remove animations mid-session kept the carousel cutting every 5 s (`MotionDurationScale` only made the tweens instant), and Data Saver changes needed a restart.
- **Dim:** only the art is dimmed, with a `ColorFilter.tint(0.3 grey, Modulate)` on the image (= black 0.7 over opaque art). The brand surface (`colorScheme.background` = `BrandTokens.appBackground`) is never dimmed, so no-art, save-data and failed covers show the plain brand colour. White text stays ≥ 8:1 over pure-white art.
- **Load, then crossfade (issue #124):** `SteppedCrossfade` waits for the incoming cover's `onSuccess` before fading, and only a cover that has drawn becomes the outgoing layer. Before, a slow or failed successor faded in empty and then dropped the outgoing cover, so on a slow network the backdrop blinked to the bare brand colour mid-rotation (seen on `FST_TriFold` folded at 20 s).
- **Failures:** `CoverFailurePacer` — at most 3 attempts per 5 s deadline (two immediate skips, then wait), 5 failures per pool, then rotation and preloading stop (Windows `ArtworkCarousel.IsExhausted`). Each failure is logged under logcat `FST_ART`. A single-cover pool never skips.
- **Test hooks:** root tag `fst.shell.artwork-background` with `clearAndSetSemantics` (no text, role, action or children for TalkBack) plus test-only keys `ArtworkBackgroundStateKey` (`BackgroundState.id`: `no-art`, `animated`, `reduced-motion`, `save-data`, `not-visible`, plus `covered` and `song`; precedence save-data > no-art > not-visible > song > reduced-motion > covered > animated) and `ArtworkBackgroundCoverKey` (front URL or empty). Custom keys are not exported to accessibility services.
- **30 fps (issue #83):** the zoom/pan and crossfade run their `Animatable`s inside `withContext(SteppedFrameClock(...))`, which waits for the next 1/30 s grid point before asking the composition clock for a frame. Compose's own `Crossfade`/`rememberInfiniteTransition` ask every vsync (942 frames in 15 s on a 60 Hz emulator, ~2× that on 120 Hz phones); the stepped clock gives ~30 frames/s regardless of refresh rate, and both layers share grid frames. `MotionDurationScale` (animator scale) still applies. `SteppedFrameClockTest` measures 125 vs ~30 frames for a 1 s tween on a 125 Hz fake display.
- **Covered by a modal (issue #83):** `FestivalModalSheet`, `FestivalModalDialog` and `FestivalAlertDialog` register with `ModalCoverage.shared` while composed (first-run, What's New, sort/filter sheets, alerts), and `BackgroundPolicy.mode(covered = true)` returns Still: no cover rotation, drift frozen at its current frame. Closing resumes the drift at its original speed (`remainingZoomMs`). The scrim already dims the backdrop, so the frozen frame is not noticeable. The feedback form (its own `Dialog`, modal-shell R6) wraps it in `CoversBackdrop` too (#186; before, the backdrop kept drifting behind the full-screen form). The page's own loops (marquee, Shop pulse, status pulse) hold the same way through `coveredByModal()` ([modal-shell](../../patterns/modal-shell.md) R9).
- Images: Coil 3 with a bounded memory cache (20%), **no disk cache**; never bundled.
- **Deliberate deviations:** in-app Reduce Transparency keeps the art (the Android setting reads "Use opaque cards over the artwork background", like Windows; Apple hides it). The app is dark-only by brand, so system light/dark look the same. Material 3 maps "Default background" to `surface`; the repo's theme puts the brand page colour on `background` (cards on `surface`).
- **Tests:** `ArtworkBackgroundUiTest` (Robolectric: every state, live animator scale and Data Saver, failure pacing, a failed successor keeping the previous cover, art-only dim by pixel, hidden semantics; advance `mainClock` to a target time — it rounds each step up to 16 ms frames) and `ArtworkBackgroundDeviceTest` (connected, ATF; live animator scale/Data Saver via shell, not-visible via `ActivityScenario.moveToState(STARTED)`, read through `ViewRootForTest` because the rule finds no hierarchy while covered, advancing `mainClock` so the paused composition recomposes).

## Validated configurations (issue #124)

| Configuration | Finding |
|---|---|
| `FST_Phone` portrait, dark, font 1.0 | Animated: cover-to-cover crossfades every 5 s with no brand-only frames (frame scan of a 14 s recording); art full-bleed behind the bars and FAB. |
| `FST_Phone` live animator scale 0 → 1 | Before: kept rotating (frames 5 s apart differ). After: frozen frame (pixel diff 0.0), resumes at scale 1 without a restart. |
| `FST_Phone` live Data Saver on → off | Before: art stayed until restart. After: undimmed brand `#1A0830` at once; art returns when turned off. |
| `FST_Phone` light theme, font 2.0, landscape | Dark-only by brand, so light looks the same; at font 2.0 text grows over full-bleed art without clipping; landscape fills the width under the navigation bar. TalkBack tree has no backdrop node. |
| `FST_Tablet` portrait/landscape, light + font 2.0, Songs | Art fills the window behind the rail and Songs list in both orientations. |
| `FST_Resizable` phone, foldable, tablet, desktop | Bottom bar → rail → drawer layouts; art always spans the whole window, never clipped to a pane. |
| `FST_Book_Fold` folded, unfolded, unfolded font 2.0 | Layout adapts; first cover after a cold launch arrives with the live catalogue (no art yet at 9 s, same as baseline). |
| `FST_Passport_Fold` folded, unfolded, unfolded landscape | Art spans across the hinge in every posture. |
| `FST_TriFold` folded, partial, unfolded, landscape, font 2.0 | Art spans all panels. `am start` defaults to display 2 on this AVD, so launch with `--display 0` for screenshots. 40 s live recording after the load-then-crossfade fix: no brand-only frames once art shows. |
| Connected `ArtworkBackgroundDeviceTest` | Passes on `FST_Phone` and `FST_TriFold` (API 37), including ATF checks. |

Cold launch against the live service takes 12–20 s on the emulator before the first cover (catalogue and first cover download); the brand surface shows meanwhile. This matches the pre-#124 baseline.

## Validated configurations (issue #186: idle work behind modals)

Live service, debug or `benchmark` build. Frame counts from `tools/android/frame_stats.py --animations-on` (15 s idle unless noted).

| Configuration | Finding |
|---|---|
| `FST_Phone` Settings idle | ~31 fps (155 frames / 5 s, 33 ms gaps) with the backdrop animating; 0 at animator scale 0 and with the still backdrop. A live scrape adds Service Info's every-vsync spinner (live progress, kept). |
| `FST_Phone` first-run tour over Leaderboards | Before: 837 frames (clipped-name marquee kept scrolling under the tour). After: 0; names resume scrolling after the tour closes. |
| `FST_Phone` first-run tour over Songs | Before: 812 + 80 frames (Shop pulse/breathe plus the tour). After: 141, the visible slide's own demo only. |
| `FST_Phone` Suggestions scroll (SFentonX) | 508 frames, UI > 8.33 ms 12.8% (before 17%); covers reused from Coil's memory cache. |
| `FST_Phone` font 2.0 portrait/landscape | Tour lays out side by side in landscape; its text column scrolls at font 2.0 instead of clipping. |
| `FST_Tablet` landscape + font 2.0, `FST_Resizable` phone/foldable/tablet | Tour is a centered dialog on medium+ widths over the rail; page behind holds still. |
| `FST_Book_Fold`, `FST_Passport_Fold`, `FST_TriFold` folded/unfolded | Folded: phone-width tour over the bottom-bar page. Unfolded: rail plus two leaderboard columns; the tour is centered across the flat fold (`dialogHingeArea` avoids only separating hinges). A posture change recreates the activity without a crash. |
| Feedback form | Live `/api/features` has `feedback: false`, so it was checked in Robolectric only (`FeedbackUiTest.openFormCoversTheBackdropUntilItCloses`). |
| Connected tests (`FST_Phone`) | `ArtworkBackgroundDeviceTest` 1, `FirstRunJourneyTest` 4, `FeedbackFormJourneyTest` 2, `ModalCloseJourneyTest` 11, `SuggestionsAccessibilityJourneyTest` 1, `ServiceStatusDeviceTest` 5, `LeaderboardsDeviceJourneyTest` 2: all pass. |

- Open: power measurement of the 30 fps clock (frame time measured in #186), Macrobenchmark/JankStats, publication-change cache clear.
