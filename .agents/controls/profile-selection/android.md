# Profile selection — Android notes

> **What:** the Android profile sheet, selected-identity persistence and debug flags. **Read when:** changing `ui/profile/ProfileSheet.kt`, `ProfileSearchViewModel` or selection in `ShellViewModel`/`SelectedProfileStore`. Spec: [spec.md](spec.md).

## Sheet (`fst.profile.sheet`)

- Opened from the top-bar avatar (`fst.nav.profile`) and the rail's Profile item (`fst.nav.rail.profile`) **only while no profile is selected**; with a profile selected both open its page, Statistics (tab, or pushed where it is not a tab), like the drawer's profile row (issue #290, web `getProfileClickDestination`; `core/shell/ProfileChipPolicy.kt`, `ProfileChipPolicyTest`, `ProfileUiTest`, `RailProfileChipUiTest`). Empty-state "Select Player" buttons (Rivals, Suggestions, Notifications) also open it. The shared `FestivalModalSheet` titled "Profiles" with the standard Close icon button (`fst.profile.close`); Deselect confirms with the shared `FestivalAlertDialog`.
- Selected summary (`fst.profile.selected`): avatar, name, **View Profile** (`fst.profile.view-selected`) and **Deselect** (`fst.profile.deselect`, confirmed by `fst.profile.deselect-confirm`). Since issue #290 no shell entry opens the sheet with a profile selected (switch from a player page's Switch to This Profile, deselect from the drawer); the summary stays for `FST_DEBUG_SHEET=profile` and is still covered by the states tests.
- "Find a Profile": a `SingleChoiceSegmentedButtonRow` Players/Bands (`fst.profile.scope.{players,bands}`) and a native M3 `DockedSearchBar` + `SearchBarDefaults.InputField` on a neutral container (no custom purple fill; `fst.profile.search`, clear button). Bands disables the field and explains that choosing a band as the profile isn't available in the app yet and that Search finds bands (`fst.profile.bands-unavailable`); no band request is made here ([spec](spec.md), issue #320).
- Search: 250 ms debounce, 2-character minimum, centered hint text with no container (`fst.profile.hint`), results as `ListItem`s with initials (`fst.profile.result.<accountId>`), Retry after an error or an empty envelope (`fst.profile.retry`). IME Search opens the first result.
- A result **views** the player: the sheet dismisses, then `PlayerRoute(id, name)` is pushed on the current tab. Selecting happens on the player page.

## Session

- Only `SelectedPlayer(accountId, displayName)` persists (DataStore `fst.profile.*`; survives cold starts, `ProfileUiTest.selectionPersistsAcrossColdStart`). Account IDs follow the Apple/Windows rule `[A-Za-z0-9_-]{1,128}`.
- Scores are process-only in `SelectedProfileStore` ([player-profile/android.md](../../pages/player-profile/android.md)).
- Debug: `FST_DEBUG_PROFILE=<accountId>:<name>` selects in memory only, `FST_DEBUG_ANONYMOUS=1` ignores the stored player, `FST_DEBUG_SHEET=profile` opens the sheet.

## Validation (issue #133, 2026-10-04)

Emulator API 37, debug build, live public service (keyless; no selected-profile headers; player search only, band search never called), public player SFentonX. Dark scheme only by repo rule: with the system light theme the app stays dark.

| Configuration | Result |
|---|---|
| FST_Phone portrait, font 1.0 and 2.0; system light and dark | OK: anonymous hint, debounced results, Bands explanation, viewed page, Select, selected summary, Deselect confirm. At 2.0 the title, scopes, field and rows grow without clipping. |
| FST_Phone landscape, font 1.0 and 2.0 | OK. At 2.0 the sheet opens partially expanded (title and "Find a Profile" visible); the rest is in its scroll container and the 48 dp drag handle expands it. |
| FST_Tablet portrait ⇄ landscape, font 1.0 and 2.0 | OK; results and the typed query survive rotation and font-scale changes. |
| FST_Resizable phone / foldable / tablet / desktop | OK; centred sheet (640 dp max) at medium and expanded widths. |
| FST_Book_Fold folded / unfolded | OK. Right after a fold switch the emulator is briefly busy (uiautomator can't dump); allow ~10 s before checking. |
| FST_Book_Fold half-open (separating vertical hinge at x=1038 px) | OK: the sheet sits in the start pane (`festivalSheetHingeSide`) after unfolded→half, folded→half and a cold launch at half. One drive caught the hinge still reported flat (sheet centred) right after the angle change; three reruns and `ProfileSelectionDeviceTest` at `--posture half` kept it off the hinge. |
| FST_Passport_Fold folded / half / unfolded | OK. |
| FST_TriFold folded / partial / unfolded | OK; flat hinges, so the sheet stays centred. |

- **Fixed:** a viewed player whose scores were republished (publication changed) or whose Select failed said "Reload this page before selecting" with no way to reload (the page has no pull-to-refresh). The identity area now has a 48 dp **Reload** text button (`fst.player.reload`, `PlayerProfileUiState.offersReload`) ([player-profile/android.md](../../pages/player-profile/android.md)). The sheet's inline search-error Retry carries `fst.profile.retry` as listed above.
- Accessibility:
  - `ProfileSelectionDeviceTest` (ATF on every step, reading order, hinge) passes on FST_Phone and FST_Book_Fold half-open. Asserted order: "Profiles" title → Players → hint; "Find a Profile" → result rows; selected: "Selected Profile" → name, View Profile → Deselect; the confirm reads its title before Cancel. Close and the drag handle follow the shared sheet rule ([android-accessibility](../../testing/android-accessibility.md#reading-order-talkback-verified)).
  - Touch targets: Close, clear, scopes, result rows, View Profile, Deselect, Select and Reload are at least 48 dp (M3 icon/text buttons lay out at 40 dp with 48 dp touch bounds).
  - Reduced motion: device runs use animator scale 0; the sheet opens and closes without animation.
- Material 3 deviations, deliberate: dark scheme only (brand); a bottom sheet rather than a side sheet on expanded widths (web/Apple parity, centred 640 dp max); the brand search container colour; the sheet kept beside a separating hinge ("Never place interactive content or critical information across the hinge area").
- States → tests (Robolectric `ProfileSelectionSheetStatesUiTest` / `ProfileSelectionPageStatesUiTest` in `ProfileSelectionStatesUiTest.kt`):

| States | Tests |
|---|---|
| anonymous | `anonymousShowsTheHintAndPlayersTarget` |
| debouncing, loading, results | `debounceThenLoadingThenResultsOpenTheViewedPlayer` |
| empty-envelope | `emptyEnvelopeOffersRetry` |
| http-error | `httpErrorShowsInlineStatusAndRetrySearchesAgain` |
| band-blocked | `bandsTargetIsBlockedWithoutARequest` |
| selected-player, deselect-confirm | `selectedPlayerViewsAndDeselectConfirms` |
| large-text | `largeTextKeepsTargetsAndLabels` |
| viewed | `viewedPlayerOffersSelectWithoutSelecting` |
| syncing | `syncingProfileCannotBeSelectedAndRetryReads` |
| selected-syncing-retry | `selectedSyncingProfileRetriesOnStatistics` |
| unpinned-profile | `unpinnedProfileIsPreviewedButNotSelectable` |
| switch-confirm | `switchConfirmCancelKeepsTheSelectedPlayer` |
| publication-changed | `publicationChangePausesSelectionUntilReload` (Reload re-reads; `ProfileViewModelsTest.reloadIsOfferedOnlyForAViewedPausedOrFailedSelection`) |
| profile-reload | `selectedProfileReloadsOnANewPublication` |
