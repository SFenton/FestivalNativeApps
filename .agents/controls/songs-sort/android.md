# Songs Sort — Android notes

> **What:** the Android Sort sheet and Shop ordering. **Read when:** changing `SortSheet`, `SongSortDraft` or `SongCatalogSort`. Behavior: [spec.md](spec.md).

- Modes Title, Artist, Year, Duration, Item Shop (hidden while Hide Item Shop is on) + Ascending/Descending segmented buttons; a draft with Reset/Cancel/Apply (Apply enabled only when changed), persisted in `fst.songs.sort` / `fst.songs.sortAscending`.
- Ties: title, then song ID; Item Shop ties title → artist → year → ID; descending reverses everything.
- A saved Item Shop sort without a validated same-publication feed (loading, failed, hidden or mismatched) shows Title order in the saved direction with a notice.
- IDs: `fst.songs.sort{,.open,.mode,.direction,.ascending,.descending,.reset,.cancel,.apply,.discard}`, `fst.songs.sort.<mode>`, `fst.songs.shop-section.*`.
