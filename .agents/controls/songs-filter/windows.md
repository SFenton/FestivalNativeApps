# Songs Filter — Windows notes

> **What:** the Windows Filter flyout. **Read when:** changing `SongFilterDraft` or the flyout in `SongsPage.xaml`. Rules: [spec.md](spec.md).

- Light-dismiss `Flyout` (scrolls, max 640 epx tall): Instrument, Lowest/Highest Difficulty, Item Shop (In Item Shop, Leaving Tomorrow; disabled but kept and clearable while Shop is hidden), and with a player **Player Scores**: four global `ToggleSwitch`es over visible charts plus a **Per Instrument** expander grid (No Score / Score / No FC / FC per chart).
- Live semantics (operator 2026-09-28): opening loads the applied filters, then every valid change applies at once (an inverted difficulty range waits until it is valid); Reset clears and applies; there is no Cancel or Apply.
- Persistence: `AppSettings.SongFilter`, `ShopFilter`, `PlayerScoreFilter` (typed lists of charts; duplicates/unknown values make it invalid → blocking Reset view). Applying removes hidden-chart checks; deselecting the player clears `PlayerScoreFilter` only.
- IDs: `fst.songs.filter{,.form,.title,.instrument,.min-difficulty,.max-difficulty,.in-shop,.leaving,.reset}`, `fst.songs.filter.score-sections`, `fst.songs.filter.score.global.*`, `fst.songs.filter.score.instrument`, `fst.songs.score-filter-hidden`, `fst.songs.filter-invalid`, `fst.songs.filter-reset-invalid`.
