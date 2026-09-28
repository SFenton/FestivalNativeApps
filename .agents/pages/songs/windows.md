# Songs — Windows notes

> **What:** what the Windows Songs page implements, native decisions and open gaps. **Read when:** changing `windows/Festival.App/Pages/SongsPage*` or `SongsViewModel`. Behavior: [spec.md](spec.md).

## Implemented

- Live keyless `GET /api/publication` + `/api/songs` through the shared gate; ETag reuse only within the observed publication. Catalogue shared with the background and Song Detail via `FestivalSession`.
- Grouped, virtualized `ListView` (phased row realization: text, then art), white Title Case group headers, `SemanticZoom` jump index. Title/Artist group by first character (A–Z or `#`, accent-folded), Year by year, Duration by the web buckets.
- Search: 250 ms debounce, Enter applies immediately; web normalization (NFKD, apostrophes, separators).
- Sort flyout: Title/Artist/Year/Duration + direction, draft/Reset/Cancel/Apply, persisted. Gold tint when non-default.
- Filter flyout (public data): single visible chart + 1–7 difficulty range; draft/Reset/Cancel/Apply, persisted, scoped to Settings-visible charts; no-results view offers Clear Filters.
- Loading / service-status (freeze countdown, Retry) / empty states. Row opens `/songs/:id` carrying the filtered chart.

## Native decisions

| Web / iPhone | Windows | Why |
|---|---|---|
| Filter only with a player/band | Filter always available (instrument + difficulty) | Public-data filters are useful without a profile on desktop; player filters join when profiles land |
| Right-edge scrubber | `SemanticZoom` jump list | Windows-native quick jump (Start, Mail, Photos) |
| Cancel on a changed draft confirms discard | Light-dismiss flyout discards | Fluent flyout convention |

## Open

Item Shop sort/filter and badges; selected-player chips/metadata and score filters; Quick Links; Year/Duration quick jump beyond SemanticZoom; UI automation and Narrator pass.
