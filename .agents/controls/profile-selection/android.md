# Profile selection — Android notes

> **What:** the Android profile sheet, selected-identity persistence and debug flags. **Read when:** changing `ui/profile/ProfileSheet.kt`, `ProfileSearchViewModel` or selection in `ShellViewModel`/`SelectedProfileStore`. Spec: [spec.md](spec.md).

## Sheet (`fst.profile.sheet`)

- Opened from the top-bar avatar (`fst.nav.profile`) and the rail's Profile item (`fst.nav.rail.profile`) **only while no profile is selected**; with a profile selected both open its page, Statistics (tab, or pushed where it is not a tab), like the drawer's profile row (issue #290, web `getProfileClickDestination`; `core/shell/ProfileChipPolicy.kt`, `ProfileChipPolicyTest`, `ProfileUiTest`, `RailProfileChipUiTest`). Empty-state "Select Player" buttons (Rivals, Suggestions, Notifications) also open it. The shared `FestivalModalSheet` titled "Profiles" with the standard Close icon button (`fst.profile.close`); Deselect confirms with the shared `FestivalAlertDialog`.
- Selected summary (`fst.profile.selected`): avatar, name, **View Profile** (`fst.profile.view-selected`) and **Deselect** (`fst.profile.deselect`, confirmed by `fst.profile.deselect-confirm`). Since issue #290 no shell entry opens the sheet with a profile selected (switch from a player page's Switch to This Profile, deselect from the drawer); the summary stays for `FST_DEBUG_SHEET=profile` and is still covered by the states tests.
- "Find a Profile" (issue #600, [search-scopes](../../patterns/search-scopes.md)): a `SingleChoiceSegmentedButtonRow` **All · Players · Bands** (`fst.profile.scope`, segments `fst.profile.scope.{all,players,bands}`) that starts on All every time the sheet opens, like the web `SearchModal` with targets `players|bands`, then a native M3 `DockedSearchBar` + `SearchBarDefaults.InputField` on a neutral container (no custom purple fill; `fst.profile.search`, placeholder "Search players or bands", spoken "Search players and bands", clear button `fst.profile.clear`).
- Search: the sheet runs global search's engine narrowed to players and bands (`GlobalSearchViewModel(targets = SearchScope.profileTargets)`, keyed `profile-search` in `FestivalApp`; Find Rival keeps the players-only `ProfileSearchViewModel`). All searches players and bands together; Players or Bands sends only that kind's request. 250 ms debounce, 2-character minimum with a centred hint (`fst.profile.hint`, "…to search for players or bands." in All), a spinner during the debounce and read (`fst.profile.loading`), the shared `FestivalEmptyState` "No results found" (`fst.profile.empty`) and the inline per-kind failure (`fst.profile.players-error` / `fst.profile.bands-error`). There is no Retry button, as in global search: IME Search re-runs a failed or empty search. TalkBack hears the settled count ("2 players, 1 band") through the shared `SearchAnnouncement` (`fst.profile.status`).
- Results are global search's own rows (`searchResultItems` with `ProfileSheetTags.results`, no artwork): players `fst.profile.result.<accountId>`, bands `fst.profile.band.<bandId>`. All titles each kind ("Players", "Bands", `fst.profile.section.{players,bands}`, [section-headers](../../patterns/section-headers.md) R9); a single scope has no titles.
- A player result **views** the player: the sheet dismisses, then `PlayerRoute(id, name)` is pushed on the current tab (the selected player opens Statistics). Selecting happens on the player page. A band result opens its Band page (`BandRoute`), as global search does: Android can't select a band as the profile yet. Closing the sheet clears the query and the next open starts on All.

## Session

- Only `SelectedPlayer(accountId, displayName)` persists (DataStore `fst.profile.*`; survives cold starts, `ProfileUiTest.selectionPersistsAcrossColdStart`). Account IDs follow the Apple/Windows rule `[A-Za-z0-9_-]{1,128}`.
- Scores are process-only in `SelectedProfileStore` ([player-profile/android.md](../../pages/player-profile/android.md)).
- Debug: `FST_DEBUG_PROFILE=<accountId>:<name>` selects in memory only, `FST_DEBUG_ANONYMOUS=1` ignores the stored player, `FST_DEBUG_SHEET=profile` opens the sheet.

## Validation (issue #133, 2026-10-04)

Emulator API 37, debug build, live public service (keyless; no selected-profile headers; player search only, band search never called; superseded for the sheet by issue #600), public player SFentonX. Dark scheme only by repo rule: with the system light theme the app stays dark.

| Configuration | Result |
|---|---|
| FST_Phone portrait, font 1.0 and 2.0; system light and dark | OK: anonymous hint, debounced results, Bands explanation, viewed page, Select, selected summary, Deselect confirm. At 2.0 the title, scopes, field and rows grow without clipping. |
| FST_Phone landscape, font 1.0 and 2.0 | OK. The sheet opens fully expanded (`modal-shell` R13, #586; it used to open at half height below "Find a Profile"); the rest is in its scroll container. |
| FST_Tablet portrait ⇄ landscape, font 1.0 and 2.0 | OK; results and the typed query survive rotation and font-scale changes. |
| FST_Resizable phone / foldable / tablet / desktop | OK; centred sheet (640 dp max) at medium and expanded widths. |
| FST_Book_Fold folded / unfolded | OK. Right after a fold switch the emulator is briefly busy (uiautomator can't dump); allow ~10 s before checking. |
| FST_Book_Fold half-open (separating vertical hinge at x=1038 px) | OK: the sheet sits in the start pane (`festivalSheetHingeSide`) after unfolded→half, folded→half and a cold launch at half. One drive caught the hinge still reported flat (sheet centred) right after the angle change; three reruns and `ProfileSelectionDeviceTest` at `--posture half` kept it off the hinge. |
| FST_Passport_Fold folded / half / unfolded | OK. |
| FST_TriFold folded / partial / unfolded | OK; flat hinges, so the sheet stays centred. |

- Issue #600 changed the sheet's search; the rows below are its #133 validation. The Bands-explanation and Retry notes no longer apply.
- **Fixed:** a viewed player whose scores were republished (publication changed) or whose Select failed said "Reload this page before selecting" with no way to reload (the page has no pull-to-refresh). The identity area now has a 48 dp **Reload** text button (`fst.player.reload`, `PlayerProfileUiState.offersReload`) ([player-profile/android.md](../../pages/player-profile/android.md)).
- Accessibility:
  - `ProfileSelectionDeviceTest` (ATF on every step, reading order, hinge) passes on FST_Phone and FST_Book_Fold half-open (#133; issue #600's version on FST_Phone, with `publishTalkBackTree()` so it reads TalkBack's order). Asserted order (issue #600): "Profiles" title → All → Players → Bands → "Search players and bands" → hint; results: player rows before band rows; Bands scope: Bands → hint, then the field before the band row, and a band opens `fst.band.screen`; "Find a Profile" → result rows; selected: "Selected Profile" → name, View Profile → Deselect; the confirm reads its title before Cancel. Close and the drag handle follow the shared sheet rule ([android-accessibility](../../testing/android-accessibility.md#reading-order-talkback-verified)).
  - Touch targets: Close, clear, the three scope segments, player and band rows, View Profile, Deselect, Select and Reload are at least 48 dp (M3 icon/text buttons lay out at 40 dp with 48 dp touch bounds).
  - Reduced motion: device runs use animator scale 0; the sheet opens and closes without animation.
- Material 3 deviations, deliberate: dark scheme only (brand); a bottom sheet rather than a side sheet on expanded widths (web/Apple parity, centred 640 dp max); the brand search container colour; the sheet kept beside a separating hinge ("Never place interactive content or critical information across the hinge area").
- States → tests (Robolectric `ProfileSelectionSheetStatesUiTest` / `ProfileSelectionPageStatesUiTest` in `ProfileSelectionStatesUiTest.kt`):

| States | Tests |
|---|---|
| anonymous | `anonymousShowsTheHintAndAllScope` |
| debouncing, loading, results | `debounceThenLoadingThenResultsOpenTheViewedPlayer` |
| empty-envelope | `emptyEnvelopeShowsTheEmptyStateAndSearchRunsAgain` |
| http-error | `httpErrorShowsInlineStatusAndSearchRunsAgain` |
| band-blocked | `bandsScopeSearchesBandsAndOpensTheBandPage` (issue #600: the contract state name predates band search; Bands now searches and a band opens its page) |
| selected-player, deselect-confirm | `selectedPlayerViewsAndDeselectConfirms` |
| large-text | `largeTextKeepsTargetsAndLabels` |
| viewed | `viewedPlayerOffersSelectWithoutSelecting` |
| syncing | `syncingProfileCannotBeSelectedAndRetryReads` |
| selected-syncing-retry | `selectedSyncingProfileRetriesOnStatistics` |
| unpinned-profile | `unpinnedProfileIsPreviewedButNotSelectable` |
| switch-confirm | `switchConfirmCancelKeepsTheSelectedPlayer` |
| publication-changed | `publicationChangePausesSelectionUntilReload` (Reload re-reads; `ProfileViewModelsTest.reloadIsOfferedOnlyForAViewedPausedOrFailedSelection`) |
| profile-reload | `selectedProfileReloadsOnANewPublication` |
