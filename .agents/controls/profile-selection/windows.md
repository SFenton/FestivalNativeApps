# Profile selection — Windows notes

> **What:** the Windows title-bar profile flyout, selected-identity persistence and debug launch flags. **Read when:** changing the flyout in `windows/Festival.App/MainWindow.xaml*`, the profile members of `ShellViewModel` or `FestivalSession.Profile.cs`. Spec: [spec.md](spec.md).

## Flyout (`fst.profile.sheet`)

- The `PersonPicture` button at the right of the title bar (`fst.shell.profile`) opens a light-dismiss `Flyout` (Fluent account-picker pattern, not a modal `ContentDialog`).
- Selected player summary (`fst.profile.selected`): avatar, name, **View Profile** (`fst.profile.view-selected`) and **Deselect** (`fst.profile.deselect`, confirmed by a `ContentDialog` after the flyout closes).
- "Find a Profile": `SelectorBar` Players/Bands (`fst.profile.scope.{players,bands}`). Bands keeps the box visible but disabled, with the explanation that band search can change stored data (blocked; see [service-safety](../../platforms/service-safety.md)).
- Search: `ShellViewModel.ProfileSearch` is the global-search engine in players-only mode (`GlobalSearchViewModel.ForPlayers`): 250 ms debounce, 2-character minimum ("Enter at least two characters to search."), "Searching…" during debounce and read, scrape-freeze/failure message, `ListView` results with avatars (`fst.profile.results`), a plain centred hint with no container (`fst.profile.hint`). The field is a native `AutoSuggestBox` with the search glyph (`fst.profile.search`, no custom fill; its inner text box is named "Find Player", so keyboard journeys assert focus by name), **Retry** after an error or an empty envelope (`fst.profile.retry`). Enter opens the first result. Closing the flyout stops a pending search (`Deactivate`); reopening resumes it. The Bands target stops the search and returning to Players re-runs the kept text.
- A result **views** the player (`AppRoute.Player(id, name)` pushed on the current section); selecting happens on the player page. **View Profile** also pushes the selected player on the current section.
- Narrator: a settled search speaks "N players", "No players found." or the failure text through `ProfileSearchBox` while the flyout is open (`GlobalSearchResults.PlayersAnnouncement`, raised by `GlobalSearchViewModel.Announce` in players-only mode; the hint's `LiveSetting` alone did not announce). Result rows are `ListViewItem`s named after the player (`fst.profile.result.<accountId>`, set in `ContainerContentChanging`: the item is a record, so the container would otherwise read its type name). The list is named "Players".
- UI Automation: the panels `fst.profile.sheet`/`fst.profile.selected` have no automation peer; journeys find the summary by its "Selected Profile" heading. The empty hint `TextBlock` stays in the tree with an empty name and a zero rect.

## Player page identity (viewed player)

- `PlayerProfileViewModel.IdentityAction` decides between **Select Profile** / **Switch to This Profile** (`fst.player.select`, confirmed by a `ContentDialog`: primary "Switch Profile", Cancel default) and a notice (`fst.player.identity-notice`): syncing (202), unpinned read ("These scores have no verified publication. Selection is paused.") and changed publication ("Published scores changed. Reload this page before selecting.").
- The view model re-evaluates the action when the session's `ObservedPublicationId` changes (issue #226), so a newer publication observed anywhere in the app swaps Select for the "changed" notice at once instead of failing on click.

## Design decisions (winui-design)

- Account picker in a light-dismiss `Flyout` ("Contextual action → Flyout"); switch and deselect use a `ContentDialog` with a verb-labelled primary and Cancel as the default ("Destructive action fired without confirmation → ContentDialog with verb-labelled primary").
- Loading, empty and error states each show text in the flyout, and Retry appears for errors and empty envelopes (skill state coverage: Loading/Empty/Error with retry). Only theme brushes are used, so contrast themes repaint from system colours with no `Opacity` on system brushes.
- **Deviation:** the skill says "Placeholder text used as the only field label → Always provide a visible label". The `AutoSuggestBox` keeps its placeholder ("Find Player" / "Find Band", also its UIA name) under the visible **Find a Profile** heading and the Players/Bands `SelectorBar`, which label it visually; a separate header would repeat the heading in a 340 epx flyout.
- The flyout keeps a fixed 340 epx content width. At 200% text and in compact windows the name, buttons and band explanation wrap inside it (validated below).

## Fixture states (`tools/windows/profile_fixture.py`)

| State | Journey page | How the fixture reaches it |
|---|---|---|
| `anonymous`, `debouncing`, `loading`, `results`, `empty-envelope`, `http-error` | `profile-<state>` in `journeys/profile-selection.json` | Search `Fixture`; any `ro…` query waits 4 s; `zzz` returns an empty envelope; `busy` → 503, `blocked` → 403 |
| `viewed`, `syncing`, `selected-syncing-retry`, `selected-player`, `view-selected` | same file | `/player/fixture-player-2`; `/player/fixture-syncing` answers 202 |
| `switch-confirm`, `deselect-confirm` | same file | `ContentDialog` with Cancel as the default button |
| `band-blocked`, `publication-changed`, `reload` | same file | Bands target; `/player/fixture-rollover` reports a newer publication, then Back and View Profile reload the selected player |
| `unpinned-profile` | `journeys/profile-selection-unpinned.json` | `FST_PROFILE_FIXTURE_UNPINNED=1` drops the publication headers |
| `large-text` | any page with `--mode text-200` | Windows text scaling 200% |
| keyboard | `journeys/profile-selection-keyboard.json` | Enter opens the first result, arrows move in results, Bands target, Esc cancels Deselect |

## Validation (issue #226, 2026-10-04)

The checks used the winui-design and winui-code-review skills (no findings on the change), `a11y_matrix.py --scan --tabs 12` with the fixture above and the live public service (SFentonX, no profile headers). Axe 0 errors everywhere apart from the framework `PopupHost` item in [windows-accessibility](../../testing/windows-accessibility.md#open-issues) (item 8).

| Configuration | Result |
|---|---|
| Medium, every page (17 states + reload, unpinned, 4 keyboard) | Pass; Axe 0 except `reload` (PopupHost, after View Profile closes the flyout). The re-run after merging master also saw the PopupHost item on `viewed` and `view-selected`; the pre-merge build matched, so it is host timing, not a regression. `unpinned` needs `FST_PROFILE_FIXTURE_UNPINNED=1` in the matrix's environment |
| Compact, wide, maximized, snap-left, snap-right | 7 pages × 5 sizes pass, Axe 0; the flyout stays 340 epx and inside the window at 500 epx |
| Text 200% (compact) | All 17 pages and 4 keyboard pages pass; names, buttons and the band explanation wrap. Axe: PopupHost only, on `viewed`, `view-selected` and `reload` |
| Desert, Night sky | 7 and 4 pages pass, Axe 0; flyout, results, avatars and dialogs repaint from system colours |
| Light, dark theme | 7 and 4 pages pass, Axe 0; identical renders (the app is dark-only, [design/windows.md](../../design/windows.md)) |
| Display 100%, 150% | 2 and 4 pages pass, Axe 0 |
| Keyboard only | Enter on the profile button opens the flyout with focus in search; Enter opens the first result; Tab moves into results and Down to the next; Shift+Tab and Right reach Bands; Esc closes and returns focus to the profile button; Deselect's dialog focuses Cancel and Esc dismisses it. Focus rectangles are visible in the dark and contrast captures |
| Live service | Searching `SFentonX` lists SFentonX and LucasFentonio; viewing and selecting work at compact, medium, wide, maximized, snap-left, text 200% and display 150%; Bands shows the blocked explanation. A capture on the locked lane console did not apply the contrast theme, so contrast evidence is from the fixture runs |

Fixed: Narrator did not announce settled search results; a newer publication observed elsewhere left a stale **Select** on an open player page; result rows read the record type name in UIA.

## Session

- Only `SelectedPlayer(accountId, displayName)` persists (`settings.json`); scores are process-only in `FestivalSession.SelectedProfile`/`SelectedScoreIndex`, cleared on switch/deselect (`OnSettingsChanged`) and on superseded or failed reads, and reloaded when the publication advances (`IsSelectedProfileCurrent`).
- `ShellViewModel` starts `LoadSelectedProfileAsync()` at launch for a restored player and whenever the account changes; Songs and Suggestions observe `SelectedProfileStatus` (`None/Loading/Available/Syncing/Failed`).

## Debug launch flags (Debug environment variable in parentheses)

| Flag | Effect |
|---|---|
| `--profile accountId:Name` (`FST_DEBUG_PROFILE`) | Select in memory only; settings are not written |
| `--anonymous` (`FST_DEBUG_ANONYMOUS=1`) | No player, in memory only |
| `--settings-path file` (`FST_SETTINGS_PATH`) | Use an isolated settings file so automation never touches the operator's settings |
