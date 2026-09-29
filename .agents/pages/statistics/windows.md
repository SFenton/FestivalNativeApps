# Statistics — Windows notes

> **What:** how the Windows Statistics section renders the selected player's profile. **Read when:** changing `windows/Festival.App/Pages/StatisticsPage*` or the follow-selection mode of `PlayerProfileViewModel`. Shared page: [player-profile/windows.md](../player-profile/windows.md).

- `AppSection.Statistics` root page is `StatisticsPage`, hosting the same `PlayerProfileView` as `/player/:id` with `PlayerProfileViewModel(session, accountId: null)` (`FollowsSelection`). It is always the "This Is Me" state (web `App.tsx` routes `/statistics` to `PlayerPage` for the tracked player).
- It mirrors the session's selected-player read (`FestivalSession.SelectedProfile`/`SelectedProfileStatus`) instead of reading again; Retry forces `LoadSelectedProfileAsync(force: true)`.
- Per-entity reset: a switch re-targets the page to the new account and reloads; a deselect removes the section (the shell falls back to Songs) and the page shows `fst.player.no-profile` for the brief interval before that.
- The section frame keeps the page alive across section switches (`FrameHost` swaps frames without navigating), so the view model keeps following the selection while hidden.
- Root automation ID `fst.statistics`; everything inside uses the `fst.player.*` IDs. Layout, stat links and motion: [player-profile/windows.md](../player-profile/windows.md) (Statistics is always the selected player, so every link opens at once).
