# Stat tile grid

> **What:** the grid of stat tiles (value over an uppercase label, web `StatBox`) on the player profile (Statistics overview and per-instrument tiles), Band Detail (Summary and Statistics) and the Statistics first-run demos: columns, which tiles span two slots, tile height, order and text wrapping. **Read when:** adding a stat tile or a grid of them, changing tile text, padding or styles, or touching how the grid reacts to narrow windows and large text.

Status: **current**, 2026-10-08. Provenance: #591 (owner-approved variant, Android; split from #573). Apple AP3 `StatGridColumns` set the column rule earlier.

## Intent

Every tile in a stat grid is the same height, and a tile's text doesn't wrap just because one slot is too narrow for it. The owner (#591, about Profile and Band): "Noticing that FULL COMBOS tile, the title can wrap around to two lines. If that's the case, then that card should take up "two" card slots, so it still has the same height as other cards. (We might want to make this a general pattern)".

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/components/player/StatBox.tsx` (`StatBox`) | One tile: value (`Font.xl`, bold, `wordBreak: break-word`) over an uppercase, wide-tracked label (`Font.xs`); a chevron when it links. |
| `FortniteFestivalWeb/src/pages/player/sections/OverallSummarySection.tsx` (`buildOverallSummaryItems`) | Profile overview tiles in web order (Songs Played, Full Combos, Gold Stars, Avg Accuracy, Best Song Rank), in the `autoFitDetailCards` grid. |
| `FortniteFestivalWeb/src/pages/band/BandPage.tsx` (`BandPage`) | Band Summary and Statistics tiles, the same `StatBox` in the same grid. |

The web's grid (`GridTemplate.autoFitDetailCards`) keeps one tile per cell and lets the text wrap, so a wrapped tile makes its row taller. The two-slot span is the owner's native variant (#591); the web keeps wrapping.

## Rules

1. **R1. Span when one slot would wrap.** A tile whose widest text (value or label, measured on one line in the style it is drawn, inside the tile's horizontal padding) is wider than one slot takes two slots. A one-column grid never spans. A tile never takes more than two slots for its own text; text that doesn't fit two slots (accessibility font sizes, very long labels) wraps onto more lines, and the tile grows with it. Tiles never truncate or ellipsize their value or label.
2. **R2. Source order is reading order.** Tiles are placed row by row in the web's order, never reordered to fill holes (TalkBack and keyboard order follow the visual order). When a tile doesn't fit the slots left in its row, it starts the next row and the row's last tile widens to the row's end, so no row before the last has an empty slot. The last row keeps its trailing empty slots, like the web grid.
3. **R3. One height.** Every tile in a grid takes the tallest tile's height at its placed width (not per row), so a spanned tile is as tall as its neighbours and a tile that still wraps (R1) raises the whole grid evenly.
4. **R4. Columns.** Columns come from the grid's existing width rule: profile `StatGridColumns` (140 dp minimum tile, 8 dp spacing, 2–4 columns, wider tiles at ≥ 130% font so a narrow grid can drop to one column) and Band `BandLayout.statColumns`. Spanning never changes the column count; slots are equal and the gap is 8 dp both ways.
5. **R5. One component per platform.** Consumers pass their tiles in web order, the column rule, the texts each tile draws (with their styles) and the tile's horizontal padding. They never write their own row chunking, intrinsic-height rows, span measurement or packing.
6. **R6. Centred past the chevron.** A centred tile with a trailing chevron (profile and first-run demo tiles) pads both sides by the chevron's clearance, so its value and label are centred on the whole card, not on the space left of the chevron, at every text size (#651). Constants: Apple `chevronInset` (22 pt, scaled with the footnote chevron), Android `STAT_TILE_INSET` (28 dp a side), Windows `StatTileInsets.LinkedInset` (28 epx; the 12 epx chevron glyph keeps its size at every Windows text size). Band Detail's left-aligned tiles are not centred and keep their own padding.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Span and packing rules (R1, R2) | — (known debt) | `android/app/src/main/java/com/festivalscoretracker/android/core/profile/StatTileSpans.kt` `StatTileSpans` | — (known debt) |
| Grid (R3–R5) | `apple/Sources/FestivalUI/Features/Profile/PlayerStatGrid.swift` `StatTileGridLayout` | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/StatTileGrid.kt` `StatTileGrid` | `windows/Festival.App/Controls/PlayerStatTileView.cs` `PlayerStatTileView` (in a `UniformGridLayout`) |
| Chevron inset (R6) | `apple/Sources/FestivalUI/Features/Profile/PlayerStatGrid.swift` `chevronInset` | `android/app/src/main/java/com/festivalscoretracker/android/ui/profile/ProfileStatGrid.kt` `STAT_TILE_INSET` | `windows/Festival.Core/Domain/StatTileInsets.cs` `StatTileInsets` |

Windows consumers: `Controls/PlayerProfileView.xaml` (Statistics and Player Profile overview and per-instrument grids, `fst.player.stat.<scope>.<id>`; the value and label are raw `….value` / `….label`) and `Controls/FirstRunDemo.Slides.cs` (Statistics demos). Tests: `Festival.Core.Tests/StatTileInsetsTests.cs`, journey `tools/windows/journeys/a11y-stat-tile-centre.json` (linked tiles' value and label centred on the card at compact, medium and wide sizes, normal and `text-225`; button role, 40 epx target, reading order, Axe).

Android consumers: `ui/profile/ProfileStatGrid.kt` `StatGrid` (overview `fst.player.tile.overview.<id>` and per-instrument `fst.player.tile.<instrument>.<id>`; `statTileTexts` lists the drawn value and uppercase label, `STAT_TILE_INSET` the padding), `ui/bands/BandDetailScreen.kt` `StatGrid` (`fst.band.stat.<id>`, Summary and Statistics) and `ui/firstrun/FirstRunDemos.kt` `StatTilesDemo` (Statistics drill-down, overview and instrument-breakdown slides, `maxRows` to fit the stage). Tests: `core/profile/StatTileSpansTest.kt` (span threshold, one-column grids, packing, widening, last row), Robolectric `ui/profile/StatTileGridUiTest.kt` (a wrapping Full Combos value spans two slots at 360 dp and keeps the one-line grid's height, fitting tiles stay one slot at 411 dp, a wide tile beside others at 760 dp, a label too long for two slots wraps at 2× and stays two slots) and `bands/BandsUiTest.bandStatTilesShareTheGridHeightAndSpanWholeSlots`, connected `journeys/StatTileGridAccessibilityJourneyTest` (Statistics at font scale 1.0 and 2.0: one tile height, whole-slot widths, reading order, 48 dp targets, unclipped tiles, ATF).

Owner-approved variant (#591, Android: Profile Statistics, Band Detail and the Statistics first-run demos): R1's two-slot span replaces the web's wrap-in-one-cell. Apple and Windows keep the web behavior (one tile per cell, wrapped text, per-row height) until their own sessions adopt R1–R3; they are listed as known debt, not as a rule they break today.

Agent decisions (#591, 2026-10-08; the owner may override with `/choose`):

- **What "title" means.** The owner's FULL COMBOS example wraps on its value ("1,234 (45.6%)") at default size on a phone as well as its label at large text, so R1 measures both, not only the label.
- **Order over density.** Options weighed: (a) CSS-style dense backfill (moves a later tile into an earlier hole: rejected, it breaks the web order and TalkBack's reading order); (b) leave the hole before a wide tile (rejected: it looks like a missing tile); (c) widen the row's last tile to the row end (chosen; no holes before the last row and order unchanged). A widened tile can therefore cover more than two slots in a three- or four-column grid; that is filling, not R1's span.
- **Grid-wide height.** The owner asked for "the same height as other cards"; per-row heights (the earlier Android rule and Apple's) would still let one wrapped row stand out, so R3 uses the grid's tallest tile.
- **Band tiles keep their look.** Band Detail's tiles stay `GlassCard`s, left-aligned, with their own padding; only their grid is shared. Their labels used to ellipsize on narrow panes (`oneLineUnlessLarge`); R1 now wraps them instead.

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Apple `StatTileGridLayout` sizes each row to its tallest tile and never spans | R1–R3 | Apple session: port `StatTileSpans` (pure) into `StatTileGridLayout` |
| Windows `UniformGridLayout` stat cards never span | R1, R2 | Windows session: a span-aware layout for `PlayerStatTileView` |
| Android Band Detail tiles are `GlassCard`s, not the profile/web `StatBox` tile | look only | Band Detail parity pass |

## Guards (`tools/pattern_guard.py`)

- `stat-tile-grid/android-row-chunking`
