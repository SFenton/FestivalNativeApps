# Songs Filter — Android notes

> **What:** the Android Filter sheet, its draft model and persistence. **Read when:** changing `FilterSheet`, `SongFilterDraft`, `SongPlayerScoreFilter` or `SongsPreferences`. Behavior: [spec.md](spec.md).

- Available only with a selected player (web mobile dock); gold icon when any saved filter is set.
- `SongFilterDraft`: instrument, 1–7 difficulty range (invalid range disables Apply), Shop toggles, global and per-chart score/FC checks; Reset clears the draft only; Cancel/swipe with changes confirms discard.
- Semantics: AND within a chart, OR across active charts; uncharted parts never match; an available empty index still allows Missing Scores (spec correctness fix).
- Persistence: public filters in `fst.songs.filters` (invalid → defaults), player filter in `fst.songs.playerScoreFilters` (typed JSON, ≤ 4 KB, unknown/duplicate charts → corrupt → list blocked until Reset). Deselection clears only the player filter.
- IDs: `fst.songs.filter{,.open,.form,.title,.reset,.cancel,.apply,.discard,.in-shop,.leaving,.difficulty,.instrument.*}`, `fst.songs.filter.score-sections`, `fst.songs.filter.score.{global,instrument,chart}.*`, `fst.songs.score-filter-hidden`, `fst.songs.filter-{invalid,reset-invalid}`.
