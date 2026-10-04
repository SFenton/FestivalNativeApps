# Instrument status chips — Windows notes

> **What:** Windows rendering, states, tests and validation of the selected-player chips on Songs rows. **Read when:** changing `SongRowVisuals.Chip`, `SongInstrumentBadge` or `SongInstrumentStatusPolicy`, or the Songs row trailing layout. Rules: [spec.md](spec.md).

## Implementation

- Shown only via `SongInstrumentStatusPolicy.ShowsChips` (selected player, publication-matched available scores, Show Instrument Icons on, no chart filter); one per Settings-visible chart in service order. **Deliberate difference from the shared spec:** with Filter Invalid Scores on, Windows keeps the chips and derives them from the resolved (valid-substituted) scores, like the web `SongsPage` ([songs/windows.md](../../pages/songs/windows.md)); a chart whose only score is invalid with no valid fallback reads "no score".
- `SongRowVisuals.Chip`: 30 epx circle, status fill + ring from the `FSTStatus*` brushes in `Themes/Styles.xaml` (gold FC, green scored, red no score, amber inconsistent FC, muted not charted) around the 21 epx instrument icon (keys variant for Lead/Pro Lead on `Keyboard` songs). Ring weight and opacity come from `SongInstrumentBadge.Ring(contrast)` (Core, unit-tested): 1.5 epx and 45% opacity for not charted normally.
- Layout: inline at the row's trailing edge from a 760 epx list width, otherwise wrapped under the title (`FlowPanel`); the 1100 epx split view's 560 epx list always wraps. `SongsPage.OnListSizeChanged` rebuilds the realized rows' trailing content in place (`RefreshTrailing`, no scroll reset) whenever the **list** crosses a band: the page's own `SizeChanged` fires before the list is re-measured, so before 2026-10 a wide → compact resize kept chips inline and squeezed the title out of the card (issue #227).
- Contrast themes: `ContrastTheme.Changed` also calls `RefreshTrailing`, so chips follow a live theme switch (brushes are resolved at build time, not via `{ThemeResource}`).

## Design decisions (winui-design review, issue #227)

- High contrast uses only `SystemColor*` brushes, never opacity ("Only `SystemColor*Brush` resources are allowed inside an HC dictionary. Never set `Opacity` on them." — `winui-design` `references/theme-accessibility.md`). Each status differs by fill *and* ring weight, not hue alone: FC = Highlight fill + HighlightText ring; scored = Window fill + 3 epx WindowText ring; inconsistent FC = Window fill + 3 epx **Highlight** ring (was WindowText, identical to scored — fixed in #227); no score = 2 epx GrayText ring; not charted = no ring, full opacity.
- The icon art (white disc, black glyph PNG) stays as drawn in every theme: it is legible on every fill above. Deviation from Foreground-tinted Fluent icons, matching the product's instrument art on every platform.
- The app is dark-only by design (`App.xaml` `RequestedTheme="Dark"`; a system Light theme renders the same as Dark), as recorded in [songs/windows.md](../../pages/songs/windows.md).
- Windows has no band selection, so `band-blocked` holds by construction (chips only ever derive from a player's score index).

## Accessibility

- Chips are `AccessibilityView.Raw` with a tooltip: Narrator does not stop on them; the row's `ListViewItem` name speaks every visible chart and status ("Lead, full combo, Bass, scored, …"). The icon `Image` carries `fst.songs.instrument-status.<songId>.<ServiceId>` (e.g. `fst.songs.instrument-status.fixture-pulse.Solo_Guitar`) and name = the chip's announcement, so UIA tests address a chip with `raw=` without adding Narrator stops.

## States and tests

Fixture `tools/windows/instrument_status_fixture.py` (two songs, players `fixture-player-1`, a 6 s `fixture-chips-slow`, 202/403 players); journey pages `tools/windows/journeys/instrument-status.json`, run through the accessibility matrix:

```
python tools/windows/a11y_matrix.py --out out/chips --pages tools/windows/journeys/instrument-status.json --fixture tools/windows/instrument_status_fixture.py --scan --tabs 12 [--mode hc-night-sky] [--sizes compact,medium,wide]
```

| Spec state | Page | Assertion |
| --- | --- | --- |
| full-combo, scored, no-score, not-charted, inconsistent-zero-fc | `chips-states` | each chip's ID + name ("Lead, full combo", "Bass, scored", "Drums, no score", "Pro Lead, not charted", "Tap Vocals, score missing despite a reported full combo") |
| loading | `chips-loading` | slow player: row reads "Loading scores" with no chips, then chips appear |
| syncing / failed | `chips-syncing` / `chips-failed` | 202 → "Scores syncing", 403 → "Scores unavailable", no chips |
| available-empty | `chips-empty` | player with no scores: charted chips "no score", Pro Lead "not charted", no pause notice |
| anonymous | `chips-anonymous` | no player: no chips, no status suffix |
| instrument-hidden | `chips-instrument-hidden` | only Lead + Vocals chips |
| chart-filtered | `chips-chart-filtered` | Bass filter: metadata, no chips |
| icons-off | `chips-icons-off` | metadata row name, no chips |
| invalid-filter-paused | `chips-filter-damaged` | unsupported saved filter: `fst.songs.filter-invalid` pause + reset, no chips |
| Filter Invalid Scores | `chips-invalid-scores` | Pro Lead over leeway → valid fallback full combo |
| keyboard-variant, keyboard focus | `chips-keyboard` | Keyboard song's Lead chip; Down/Up moves focus between rows |
| compact, wide, resize | `chips-resize` | compact chip below the title (`assertbelow`), medium (900 epx at any scale) level with the row (`assertlevel`), compact again below, wide (split view from a 1100 epx page, so layout depends on display scale) aligned, medium level again |
| band-blocked | — | by construction (no band selection on Windows) |

Unit tests: `SongsListTests.Chips_TestIdAndRingWeightPerStatus`; tool tests `tools/windows/tests/test_instrument_status_fixture.py`.

## Validation (issue #227, 2026-10)

Fixture runs on a 3840×2160 display at 300% scale (compact/medium/wide presets = 500/900/1280 epx windows; 1440 epx wide at 100%), console locked (UIA patterns, posted keys, PrintWindow captures), Axe.Windows scan on every page/size. Live checks used the keyless public origin with SFentonX (`FST_DEBUG_PROFILE`).

| Configuration | Result |
| --- | --- |
| Compact, medium, wide (all 13 pages) | Pass, Axe 0; Tab walk 8–10 stops, no repeats or escapes. Found and fixed: wide → compact kept chips inline (resize page fails without `OnListSizeChanged`: "831.5 vs 834.5 px are not below") |
| Maximized, snap left, snap right (`chips-states`, `chips-keyboard`) | Pass, Axe 0 |
| High contrast Night sky, Desert, Aquatic (`chips-states`, `chips-keyboard`, `chips-resize`) | Pass, Axe 0. Found and fixed: inconsistent FC matched scored. Live switch to Night sky and back re-renders chips (`RefreshTrailing`) |
| Light / dark app theme | Pass, Axe 0 (dark-only app; identical rendering) |
| Display scale 100%, 150% | Pass, Axe 0. At 100% the wide preset (1440 epx) opens the split view, where chips wrap by design; `chips-resize` asserts inline layout at the medium preset |
| Text 200% | Pass, Axe 0; titles wrap, chips keep 30 epx (icons, not text) |
| Keyboard | Pass: Down/Up move row focus with a visible focus rectangle; chips are not Tab stops |
| Narrator / UIA | Row name speaks song, Shop state and every chart status once; chip `Image`s are Raw (no extra stops), with ID + name for tests |
| Live service (SFentonX) | Wide inline, medium inline, compact wrap after resize, snap left, maximized, Night sky live switch, text 200% compact/wide: all correct |
