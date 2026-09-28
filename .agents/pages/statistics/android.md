# Statistics — Android notes

> **What:** how the Android Statistics tab renders the selected player's profile. **Read when:** changing `StatisticsScreen` or the follow-selection mode of `PlayerProfileViewModel`. Shared body: [player-profile/android.md](../player-profile/android.md).

- `StatisticsTab` (tab root: hamburger and avatar) and `StatisticsRoute` (pushed) render `PlayerProfileContent` with `PlayerProfileViewModel(accountId = null)`, always showing the selected player with Deselect (web `App.tsx` routes `/statistics` to `PlayerPage`).
- It mirrors `SelectedProfileStore` instead of reading again; Retry calls `store.retry()`.
- Per-entity reset: a switch re-targets the page and clears the rank and history cards; a deselect removes the tab (`FestivalTabPolicy`) and the page shows `fst.player.no-profile` until the shell moves to Songs. The tab does not restore nested history (`resetsPathOnLeave`).
- Root tag `fst.statistics`; everything inside uses `fst.player.*`.
