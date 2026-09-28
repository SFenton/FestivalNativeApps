# Instrument status chips — Android notes

> **What:** Android rendering of the selected-player per-chart status chips on Songs rows. **Read when:** changing `StatusChips` in `ui/songs/SongRow.kt` or `SongInstrumentStatusPolicy`. Behavior: [spec.md](spec.md).

- `SongInstrumentStatusPolicy.showsChips`: selected player, publication-matched available scores, Show Instrument Icons on, no single-chart filter, Filter Invalid Scores off, ≥1 visible chart.
- Chip: 34 dp circle, 2 dp stroke, the chart's icon at 70% (keys variant for Lead/Pro Lead on `Keyboard` songs). Colors from `contracts/fluent-tokens.json` (`SongsTokens.chip`): gold/`goldStroke` FC, green scored, red no score, amber inconsistent FC, muted/disabled not charted. No corner glyph (color-only native deviation).
- Layout: `FlowRow` with a balanced per-row count (Apple `SongChipRows` rule), centered; test tags `fst.songs.instrument-status.<songId>` and `fst.songs.chip.<wireId>.<Status>`.
- Accessibility: chips are not separate nodes; the row's single description lists "Lead, full combo, …" in chart order.
