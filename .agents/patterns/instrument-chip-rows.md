# Instrument chip rows

> **What:** how a Songs row's instrument status chips break onto more than one line when the row is narrow: the fewest balanced rows, each centred, in service order, never clipped. Used by Songs rows and the First Run Songs icons demo (and Apple Suggestions cards). **Read when:** you lay out a row of instrument status chips, or change how chips wrap at a narrow width or a large text size.

Status: **current**, 2026-10-14. Provenance: #645 (split from #637).

## Intent

Nine instrument chips read as one tidy block on a narrow screen instead of a long line that squeezes the title, runs off the card or leaves one chip stranded on a line of its own (owner, #645: "If app is narrow enough, instrument icons don't go multi-row like they do on web").

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/pages/songs/layoutMode.ts` (`resolveInstrumentChipRows`) | Row count 1, 2 or 3 from the row's container width minus its padding (`SONG_ROW_HORIZONTAL_PADDING`), the chip size (`InstrumentSize.chip`, 34 px) and gap (`Gap.sm`): the fewest rows whose `ceil(count / rows)` chips fit. Four chips or fewer never wrap. A 16 px hysteresis (`INSTRUMENT_ROW_HYSTERESIS`) keeps a resize from bouncing between counts. |
| `FortniteFestivalWeb/src/pages/songs/layoutMode.ts` (`splitInstrumentRows`) | Splits the chips in order into that many rows, earlier rows taking the remainder (9 over 2 rows → 5 + 4). |
| `FortniteFestivalWeb/src/pages/songs/components/SongRow.tsx` (`SongRow`) | Mobile layout: the chip rows sit under the art and title across the card (`mobileChipRowWrapper`), each row centred (`Justify.center`, `mobileInstrumentRows`). Chips never shrink (`flexShrink: 0`). |
| `FortniteFestivalWeb/src/pages/songs/firstRun/demo/SongIconsDemo.tsx` (`SongIconsDemo`) | The First Run Songs icons demo uses the same two helpers. |

## Rules

1. **R1. Fewest balanced rows.** When the chips don't fit on one line, use the fewest rows that fit every chip at its full size, and even them out in order, earlier rows taking the extra chip: nine chips read 5 + 4, never 7 + 2; seven chips at three per line read 3 + 2 + 2. Greedy filling (as many as fit, the rest below) is not this pattern.
2. **R2. Centred across the row.** Each line is centred horizontally in the chip area. In the narrow layout the chip area runs the full card width under the art and title (web `mobileChipRowWrapper`); inline at the trailing edge on wide rows, the chips stay one line.
3. **R3. Measured, not a breakpoint.** The row count comes from the chip area's actual width, chip width and gap at layout time, so split views, window resizes and text size changes re-flow the chips. A native layout that measures its own width needs no hysteresis (R6).
4. **R4. Never clip, overlap or shrink.** Chips keep their size and spacing at every width and text size; lines never overlap and the card grows to hold them. There is no cap on the number of lines (R6).
5. **R5. One reading order.** Chips keep the service's chart order, line by line, left to right. The row's accessible name speaks every chart and status in that order; chips are never separate screen-reader or Tab stops.
6. **R6. Native divergences from the web.** Natives keep R1's balancing and R2's centring but drop the web's three-row cap, its "four chips never wrap" rule and its 16 px hysteresis. **Agent decision (#645, 2026-10-14): option A below; owner may override with `/choose`.**
7. **R7. Not this pattern.** Songs metadata pills keep greedy, trailing-aligned wrapping (web `metadataWrap`, [metadata-pills](metadata-pills.md)); instrument pickers and the Song Detail instrument cards are separate controls.

## Decision record: row cap, four-chip rule and hysteresis (#645)

**Question.** The web caps the chips at three rows, never wraps four chips and damps the row count with 16 px of hysteresis. Should native rows copy those limits?

**Evidence.**

- **Web** (`SFenton/FortniteFestivalLeaderboardScraper`, `layoutMode.ts` above): past three rows the chips keep `flexShrink: 0` and overflow the card. The hysteresis exists because `SongRow` measures its container with a `ResizeObserver`, and its row count changes the row's own height.
- **Owner acceptance (#645):** "No icon is clipped or overlapped at any width or text size."
- **Fluent** (`winui-design` `references/layout-review.md`): "Pick the lightest change that preserves the task" (should); **Reflow**: "Sequence can wrap or change columns"; "Breakpoints are app-window effective pixels … The window can be `<640` epx on a 4K monitor." `winui-design` `SKILL.md`: "clipped content is a worse failure than a slightly-wide window."
- **Native precedent:** Apple `SongChipRows` and Android `ChipGrid` already balance with no row cap, no four-chip rule and no hysteresis.

| Option | What you'd see | Guidance (strength) | Web / pattern precedent | Trade-offs |
|---|---|---|---|---|
| **A. Balanced, centred, no cap, no hysteresis** | At any width the chips form even, centred lines; a very narrow window adds a fourth or fifth line. | Fluent reflow (should) and no clipping: met. Owner acceptance: met. | Web balancing and centring. Apple and Android already behave this way. | A window narrower than any phone shows more than three lines (the card grows taller). |
| B. Copy the web limits | Same as A down to three lines, then chips run past the card's edge. | Owner acceptance: fails (clipped chips). Fluent clipping guidance: fails. | Literal web copy. No native precedent. | Clipping at narrow Windows widths and large text. |
| C. Three lines, then shrink chips | Three lines, smaller chips below a width. | Owner acceptance: fails (chips change size; small targets for the tooltip). | No web or native precedent. | A second chip size and more states to test. |

**Chose A.** The owner's acceptance rules out clipping (B) and Fluent's lightest change is to reflow, not resize (C). The four-chip rule only matters below about 140 epx, where a single line of four would clip; letting it wrap there keeps R4. Hysteresis only damps the web's observer feedback; native layouts measure the chip area from its own width (R3), so there is no loop to damp.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Balanced, centred lines (R1–R4) | `apple/Sources/FestivalUI/Features/Songs/SongInstrumentStatusChips.swift` `SongChipRows` | `android/app/src/main/java/com/festivalscoretracker/android/ui/songs/SongRow.kt` `ChipGrid` (drawn by `StatusChips`) | `windows/Festival.Core/Domain/InstrumentChipRows.cs` `InstrumentChipRows` (split), laid out by `windows/Festival.App/Controls/FlowPanel.cs` `FlowPanel` (`BalanceLines`, `LineAlignment = Center`) |

Consumers:

- Apple: `SongInstrumentStatusChips` on Songs rows (`SongRowView`), Suggestions cards (`SuggestionCategoryCardView`) and the First Run Songs demo (`FirstRunNativeSongsDemos`).
- Android: `StatusChips` on Songs rows (`SongRow`) and the First Run demo (`FirstRunRotatingDemos`).
- Windows: Songs rows (`Pages/SongsPage.xaml.cs` `BuildTrailing` puts compact-layout chips in `SongRowCard.Secondary` with `BalanceLines` and centred lines, and `SetWrapped(fullWidth: true)` runs that line under the art). The First Run Songs icons demo (`Controls/FirstRunDemo.Slides.cs` `BuildSongList`) shows four chips, which fit one line at every demo width. The Item Shop list's `SongRowCard`s show no chips. Metadata pills in the same `Secondary` slot turn `BalanceLines` off and align right (R7).
- Windows tests: `InstrumentChipRowsTests` (balanced split, rounding tolerance, never more chips per line than fit); UIA `tools/windows/journeys/a11y-songs-chip-rows.json`, run by `windows-ui` as `songs-chip-rows` and `songs-chip-rows-text-225` (`tools/windows/ui_ci.py`, checked by `test_ui_ci.test_songs_chip_rows_run_at_default_and_largest_text`): at a 360 epx window, 5 + 4 lines (`assertlevel`, `assertbelow`), each centred on the row within 4 epx (`assertmidline`), lines apart, 21-epx chip icons and the row's spoken order, at 100% and 150–225% text; back at the compact preset, one centred line below the title.

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Android `ChipGrid` puts `ceil(count / rows)` chips on every line but the last, so seven chips at three per line read 3 + 3 + 1 (only below about 148 dp of chip area) | R1 | Android lane |

## Guards (`tools/pattern_guard.py`)

None yet.
