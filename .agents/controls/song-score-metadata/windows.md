# Selected-player score metadata — Windows notes

> **What:** Windows metadata pills on Songs rows (icons off or one chart filtered). **Read when:** changing `SongMetadataPolicy` or `SongRowVisuals.Pill`. Rules: [spec.md](spec.md).

- Fields and order: web `DEFAULT_METADATA_ORDER` unless Settings' **Enable Visual Order** is on, then `SongRowVisualOrder`; Last Played is always last (native deviation, as on iPhone). Each field honors its Settings toggle; an FC with Percentage hidden still shows `FC`.
- Pills: Score (bold), accuracy (red→green tint at 25% alpha, at least 3.75 em wide; a full combo is `MetadataPills.FullCombo`: the bold italic `100%` alone in the Top 1% skewed gold outline, web `AccuracyDisplay` `fcBadge`, issue #644), percentile and season from the shared `Controls/MetadataPills` (pattern [metadata-pills](../../patterns/metadata-pills.md), issue #606: Top 1% skewed gold outline, Top 5% gold outline, else neutral; season `textSecondary` on `surfaceSubtle`, inverted when current, its ring the fill colour so it reads the full 24 epx), stars (24-epx circles, gold when 6), Intensity (`DifficultyMeter` scaled to 24 epx in a `Viewbox`), game difficulty (E/M/H/X on the difficulty pill brushes, dark text on Easy/Hard), Last Played date.
- Placement is one page-wide decision (`SongMetadataLayout`, web `resolveCompactRowMode`): every row puts all its pills inline beside the title when the list column fits the widest value of every enabled field (pills measured detached at the current text size and contrast, plus 114 epx row chrome and a 180-epx title), otherwise the first pill stays top-right and the rest wrap right-aligned under the title. A 32-epx hysteresis stops a resize on the threshold from flapping. The decision re-runs on list resize, text-scale change, Settings toggles and a contrast switch. With all fields on at 100% text the threshold is a ~864-epx list, so pills sit inline in windows about 1,200–1,420 epx wide (page below the 1,100-epx split-view breakpoint). Compact, medium and snapped halves wrap, and so does split view (list fixed at 560 epx), which a maximized or `wide`-preset window reaches on a 100% or 150% display.
- A non-Lead chart shows its icon first and is spoken ("Bass chart"). Zero score = `No score`.
- Test IDs: `fst.songs.metadata.<field>.<songId>` (`score`, `percentage`, `percentile`, `stars`, `season`, `intensity`, `difficulty`, `lastplayed`), `fst.songs.metadata.chart.<songId>` for the chart icon and `fst.songs.metadata.state.<songId>` for `No score`, `Loading scores`, `Scores syncing` and `Scores unavailable`.
- Accessibility: each pill is a `MetadataPill` (one raw-view UIA element with the spoken name; its peer hides the inner text, so nothing is read twice; Image for stars and intensity, Text otherwise). Narrator reads the pills once, through the row's ListViewItem name. Every pill, star row and meter has the 24-epx `MetadataPillStyle.Height` minimum (metadata-pills R7, issue #644) and the text pills grow with text size, so 200% text never clips them. Difficulty letters keep dark text on the Easy/Hard brushes by design (web parity).

## Validation (issue #228, 2026-10-04)

Fixture: `tools/windows/song_metadata_fixture.py` (designed player `fixture-meta` on the mock service, plus a slow twin and the large catalogue). Journeys: `tools/windows/journeys/song-score-metadata.json` via `a11y_matrix.py --scan`, asserting each state by UIA name and placement (`assertlevel:`/`assertbelow:`). Run `metadata-large-text` only with `--mode text-200` (`--only metadata-large-text`): at 100% text a 1340-epx window is inline by design, so its `assertbelow:` fails, and the 100%-text placement pages (`metadata-inline`, `-wrapped`, `-resize`) likewise fail at 200%.

| Configuration | Result |
|---|---|
| Compact, medium | Pass. Wrapped: score top-right, the other pills on a right-aligned row under the title. |
| Wide (1340 epx, below split view) | Pass. Inline after the fix. Before it, the threshold was a 1,100-epx page: the same width that turns on split view, so pills never went inline. |
| Maximized | Pass. On this 3840 × 2160 display at 300% (1280 epx) maximized is inline. At 100% and 150% display scale, maximized and the 1440-epx `wide` preset are in split view and wrap (`metadata-split`). |
| Snap left, snap right | Pass. Wrapped. |
| Resize: inline, medium, inline, compact, split view, inline | Pass after the fix. Leaving split view had used a stale 560-epx list width until the next page resize. |
| Light, dark, Desert, Night sky, app contrast | Pass, 0 Axe errors. The contrast themes draw pills with system colours. The app keeps its dark brand surface under the Windows light theme (app-wide). |
| Text 200% | Pass after the fix. Pills had a fixed 22-epx height and clipped; now they grow. Wide wraps, and compact flows the pills onto a second line. Stars and the intensity meter keep their icon size. |
| Display 100%, 150% | Pass, 0 Axe errors. |
| Keyboard | Pass. Rows follow title order, pills add no Tab stops, and the focus visual is on the row. |

States covered: anonymous, loading, syncing, failed, no score, score primary, score hidden (accuracy primary), FC and FC-only, graded and missing accuracy, Top 1% (gold fill), Top 3% (top-five gold outline) and ordinary percentile, five gold stars and star counts, current and old season, intensity, game difficulty, Last Played last, Bass chart named, filtered chart, invalid saved filter paused then reset, Shop row. Band-blocked does not apply on Windows: Songs never shows band metadata.

Design review (`winui-design`, `winui-code-review`):
- Fluent responsive layout says to reflow content at breakpoints and to size text containers so they never clip when text scales. The pills therefore use a minimum height and a measured, page-wide reflow, not fixed heights or a fixed width.
- Pills are display-only, so they are not focusable and have no Tab stop. Narrator reads them once, through the row's name.
- Deliberate deviations, kept for web parity: the pills' fixed font sizes (they follow the system text scale), dark letters on the Easy and Hard difficulty brushes, and icon-sized stars and intensity meters at large text.

## Validation (issue #644)

The owner reported that the Windows full combo read "100% FC", the current-season pill looked shorter than its neighbours, and the stars and meter were smaller than the chips. All of these are fixed:
- The current-season ring is no longer #162133 inside the 24-epx bounds; it uses the fill colour.
- The meter scales to 24 epx.
- Star circles are 24 epx.
- The full combo is `MetadataPills.FullCombo`.

`tools/windows/journeys/a11y-songs-metadata-chips.json` (`windows-ui` runs `songs-metadata-chips` at medium and wide and `songs-metadata-chips-text-225`, scanned) asserts each field's 24-epx size, that accuracy, Top %, season and difficulty share one height (`assertheight`, also at 225% text, where an unoutlined pill pads by the 2-epx outline width so all four grow alike), levels, the season ring paint and the rows' spoken order. `metadata-states` passes in normal, `text-200` and `hc-desert`, and `metadata-wrapped` passes at compact, medium and snap-left.

Because the 24-epx stars and meter are wider, a seven-field compact row now wraps onto two right-aligned lines under the score, like the web phone's 3+3. The wrapped placement pages therefore assert the first wrapped pair, not the last pill. `a11y-difficulty-meter` probes are scaled ×1.2.