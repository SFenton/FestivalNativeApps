# Profile selection — Android notes

> **What:** the Android profile sheet, selected-identity persistence and debug flags. **Read when:** changing `ui/profile/ProfileSheet.kt`, `ProfileSearchViewModel` or selection in `ShellViewModel`/`SelectedProfileStore`. Spec: [spec.md](spec.md).

## Sheet (`fst.profile.sheet`)

- Opened from the top-bar avatar (`fst.nav.profile`) on every tab root; the shared `FestivalModalSheet` titled "Profiles" with the standard Close icon button (`fst.profile.close`); Deselect confirms with the shared `FestivalAlertDialog`.
- Selected summary (`fst.profile.selected`): avatar, name, **View Profile** (`fst.profile.view-selected`) and **Deselect** (`fst.profile.deselect`, confirmed by `fst.profile.deselect-confirm`).
- "Find a Profile": a `SingleChoiceSegmentedButtonRow` Players/Bands (`fst.profile.scope.{players,bands}`) and a native M3 `DockedSearchBar` + `SearchBarDefaults.InputField` on a neutral container (no custom purple fill; `fst.profile.search`, clear button). Bands disables the field and explains that band search can change stored data (`fst.profile.bands-unavailable`); no band request is made ([service-safety](../../platforms/service-safety.md)).
- Search: 250 ms debounce, 2-character minimum, centered hint text with no container (`fst.profile.hint`), results as `ListItem`s with initials (`fst.profile.result.<accountId>`), Retry after an error or an empty envelope (`fst.profile.retry`). IME Search opens the first result.
- A result **views** the player: the sheet dismisses, then `PlayerRoute(id, name)` is pushed on the current tab. Selecting happens on the player page.

## Session

- Only `SelectedPlayer(accountId, displayName)` persists (DataStore `fst.profile.*`; survives cold starts, `ProfileUiTest.selectionPersistsAcrossColdStart`). Account IDs follow the Apple/Windows rule `[A-Za-z0-9_-]{1,128}`.
- Scores are process-only in `SelectedProfileStore` ([player-profile/android.md](../../pages/player-profile/android.md)).
- Debug: `FST_DEBUG_PROFILE=<accountId>:<name>` selects in memory only, `FST_DEBUG_ANONYMOUS=1` ignores the stored player, `FST_DEBUG_SHEET=profile` opens the sheet.
