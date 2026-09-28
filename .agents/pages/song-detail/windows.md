# Song Detail — Windows notes

> **What:** what the Windows Song Detail page implements and its open gaps. **Read when:** changing `windows/Festival.App/Pages/SongDetailPage*`, `SongDetailViewModel` or `SongPathsView*`. Behavior: [spec.md](spec.md).

## Implemented

- Route `AppRoute.SongDetail(songId, instrument?)`, resolved against the current catalogue (missing → not-found status).
- Header: 128 px art, title (heading 1), `artist · year · duration`, effective Item Shop badge (`fst.song-detail.shop-badge`), **Paths** (accent) and **Item Shop** (official link via `Launcher`, validated `https://www.fortnite.com/item-shop/jam-tracks/…` only) actions. A failed Shop read shows a warning `InfoBar` (`fst.song-detail.shop-error`); hidden Shop shows neither.
- Intensity card for **every charted** chart (hidden ones included).
- Leaderboards: Band Leaderboards links (Duos/Trios/Quads → `AppRoute.SongBandLeaderboard`), then one card per **visible** charted instrument, loaded lazily when realized (`?top=10`, plus `leeway` when Filter Invalid Scores is on). With a selected player each card shows a gold "Your score: …" summary (score · accuracy · FC · Top N% · rank, or an explicit state that follows the profile load), highlights the player's own row, and links **View {chart} Score History** (`AppRoute.PlayerHistory`).
- Paths: modal `ContentDialog` (focus contained and restored) sized to the window; see [chopt-paths/windows.md](../../controls/chopt-paths/windows.md).

## Open

Selected-player spotlight rank outside the top 10; band preview cards; FC/stars styling of preview rows; scrolling to the initial instrument; Quick Links.
