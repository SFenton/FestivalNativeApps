# Profile selection — Windows notes

> **What:** the Windows title-bar profile flyout, selected-identity persistence and debug launch flags. **Read when:** changing the flyout in `windows/Festival.App/MainWindow.xaml*`, the profile members of `ShellViewModel` or `FestivalSession.Profile.cs`. Spec: [spec.md](spec.md).

## Flyout (`fst.profile.sheet`)

- The `PersonPicture` button at the right of the title bar (`fst.shell.profile`) opens a light-dismiss `Flyout` (Fluent account-picker pattern, not a modal `ContentDialog`).
- Selected player summary (`fst.profile.selected`): avatar, name, **View Profile** (`fst.profile.view-selected`) and **Deselect** (`fst.profile.deselect`, confirmed by a `ContentDialog` after the flyout closes).
- "Find a Profile": `SelectorBar` Players/Bands (`fst.profile.scope.{players,bands}`). Bands keeps the box visible but disabled, with the explanation that band search can change stored data (blocked; see [service-safety](../../platforms/service-safety.md)).
- Search: `ShellViewModel.ProfileSearch` is the global-search engine in players-only mode (`GlobalSearchViewModel.ForPlayers`): 250 ms debounce, 2-character minimum ("Enter at least two characters to search."), "Searching…" during debounce and read, scrape-freeze/failure message, `ListView` results with avatars (`fst.profile.results`), a plain centred hint with no container (`fst.profile.hint`). The field is a native `AutoSuggestBox` with the search glyph (`fst.profile.search`, no custom fill; its inner text box is named "Find Player", so keyboard journeys assert focus by name), **Retry** after an error or an empty envelope (`fst.profile.retry`). Enter opens the first result. Closing the flyout stops a pending search (`Deactivate`); reopening resumes it. The Bands target stops the search and returning to Players re-runs the kept text.
- A result **views** the player (`AppRoute.Player(id, name)` pushed on the current section); selecting happens on the player page.

## Session

- Only `SelectedPlayer(accountId, displayName)` persists (`settings.json`); scores are process-only in `FestivalSession.SelectedProfile`/`SelectedScoreIndex`, cleared on switch/deselect (`OnSettingsChanged`) and on superseded or failed reads, and reloaded when the publication advances (`IsSelectedProfileCurrent`).
- `ShellViewModel` starts `LoadSelectedProfileAsync()` at launch for a restored player and whenever the account changes; Songs and Suggestions observe `SelectedProfileStatus` (`None/Loading/Available/Syncing/Failed`).

## Debug launch flags (Debug environment variable in parentheses)

| Flag | Effect |
|---|---|
| `--profile accountId:Name` (`FST_DEBUG_PROFILE`) | Select in memory only; settings are not written |
| `--anonymous` (`FST_DEBUG_ANONYMOUS=1`) | No player, in memory only |
| `--settings-path file` (`FST_SETTINGS_PATH`) | Use an isolated settings file so automation never touches the operator's settings |
