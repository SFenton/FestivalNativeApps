# Difficulty meter — Windows notes

> **What:** WinUI 3 implementation, design decisions and validation results. **Read when:** changing the meter or its brushes on Windows. Spec: [spec.md](spec.md).

## Implementation

- `windows/Festival.App/Controls/DifficultyMeter.cs` is a `Grid` holding a 62×20 `Canvas` of seven `Polygon`s (vertices from `Festival.Core/Domain/DifficultyScale.cs` `BarPolygon`) and a "Difficulty unavailable" `TextBlock` (`CaptionTextBlockStyle`, `FSTDeemphasisTextBrush`). Both children are `AccessibilityView.Raw`.
- `DifficultyScale.State(raw)` returns a `DifficultyMeterState` (filled bar count, automation ID, accessible name, state name `one`…`seven`/`invalid`), which is unit-tested in Core. The control only applies it: it shows bars or text, sets the fills, the name and the automation ID. It sets the ID on **every** update, so a recycled meter goes back from `fst.songs.difficulty-unavailable` to `fst.songs.difficulty-meter`.
- UI Automation: one element with class `DifficultyMeter`, control type `Image` ("Difficulty N of 7"), or `Text` ("Difficulty unavailable") when the level is unavailable. It has no children and isn't a tab stop.
- Brushes: `FSTMeterFilledBrush`/`FSTMeterEmptyBrush` (`Themes/Styles.xaml`). The Default dictionary uses white and #666666. The `HighContrast` dictionary uses WindowText and GrayText. Under a contrast theme, unfilled bars are 1-epx GrayText **outlines** with no fill, so filled and unfilled differ by shape. Desert's WindowText #3D3D3D and GrayText #676767 are only about 1.8:1 apart. The control never sets `Opacity`.
- Fills are set from code, so `{ThemeResource}` doesn't update them. The meter subscribes to `ContrastTheme.Changed`, which wraps one shared `UISettings.ColorValuesChanged`. It subscribes on `Loaded`, unsubscribes on `Unloaded`, and re-applies the state on its dispatcher.
- Used in: Song Details Intensity cells (`SongDetailPage.xaml`; the cell is named "{Instrument}, Difficulty N of 7"), Songs instrument-filter toggles and the Intensity metadata pill (both Raw inside a named parent), and the Songs row trailing meter when an instrument is filtered.

## Design decisions (winui-design)

- `winapp find-ui "rating or level meter"` returns only `RatingControl`, which is an interactive 5-star input. The spec requires the branded 7-bar parallelogram meter, so the meter stays custom and read-only (a deliberate deviation from "prefer system controls").
- `theme-accessibility.md`: system-colour brushes under high contrast must not get `Opacity`. The old unavailable state drew seven empty bars at 40% opacity; it now shows the spec's text.
- `theme-accessibility.md`: inline brush assignments don't follow `{ThemeResource}` on a contrast switch, hence the `ColorValuesChanged` re-apply.
- Dark-only app theme: the light system theme still renders dark (see [design/windows.md](../../design/windows.md)).

## States and reachability

| State | Reached by | Evidence |
|---|---|---|
| `one`…`seven` | Song Details / Songs with raw 0…6 | `tools/windows/journeys/difficulty-meter.json` (UIA names `{Instrument}, Difficulty N of 7` for 1–7; 99 sentinel draws no meter) + Core `DifficultyMeterState_LevelStates` |
| `invalid` | Not reachable from the UI: `SongDifficulty.ChartedValue` drops absent, negative, non-finite and 99 levels, and JSON can't carry NaN | Core `DifficultyMeterState_InvalidShowsTextNotBars`, `DifficultyMeterState_RecycledMeterReturnsToMeterId` |

Run: `python tools/windows/ui_journey.py tools/windows/journeys/difficulty-meter.json --large-catalogue` (`fixture-song-6` gives seven bars).

## Validation (issue #216, 2026-10-03)

| Configuration | Result |
|---|---|
| Compact / medium / wide, maximized, snap-left (live service, "Notorious Thugs" + "Go Go Power Rangers": all seven levels) | Correct geometry and fills at every size; the Intensity grid wraps the cells (page layout, issue #195) |
| Fixture `a11y_matrix.py --scan --tabs 12` song-detail C/M/W | Axe 0, 12 tab stops, meter not a stop |
| High contrast Desert, Night sky, Aquatic | Axe 0. Before the fix, Desert's filled and empty bars were only ~1.8:1 apart; now empty bars are GrayText outlines |
| Live contrast switch (Desert on/off with the app open) | Bars recolour both ways (before the fix they kept the old brushes until you navigated away) |
| Light / dark system theme | Axe 0; the app stays dark (deliberate) |
| Text 200% | Axe 0; the meter is a fixed 62×20 graphic, and the page grid (`TextScaleLayout`) reflows to one column without clipping |
| Display 100% / 150% | Axe 0; crisp vector polygons |
| Keyboard | The meter isn't focusable; the Song Details tab order is unchanged (12 stops) |

The console was locked during this pass, so Narrator itself wasn't run. Reading order was checked from the UIA tree: the group "Lead, Difficulty 7 of 7" > Image "Difficulty 7 of 7" (`fst.songs.difficulty-meter`).
