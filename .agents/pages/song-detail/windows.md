# Song Detail — Windows notes

> **What:** what the Windows Song Detail page implements and its open gaps. **Read when:** changing `windows/Festival.App/Pages/SongDetailPage*` or `SongDetailViewModel`. Behavior: [spec.md](spec.md).

## Implemented

- Route `AppRoute.SongDetail(songId, instrument?)`, resolved against the current catalogue (missing → not-found status).
- Header: 128 px art, title (heading 1), `artist · year · duration`. The shared background switches to that song's static dimmed cover and pauses the carousel.
- Intensity card for **every charted** chart (hidden ones included): icon, label and branded meter in a responsive `UniformGridLayout`.
- Leaderboards: one card per **visible** charted instrument, loaded lazily when realized (`GET /api/leaderboard/{song}/{instrument}?top=10&offset=0`), with loading, empty, inline error/Retry and rows (rank, name, score, accuracy). "View Full Leaderboard" pushes `AppRoute.SongLeaderboard` (placeholder page for now).

## Open

Full 25-row leaderboard page, Paths, Shop badge, selected-player spotlight/history, band previews, FC/stars styling of rows, per-row player navigation, scrolling to the initial instrument.
