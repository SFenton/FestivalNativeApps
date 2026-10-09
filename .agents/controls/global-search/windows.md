# Global search — Windows notes

> **What:** the WinUI 3 design for the app-wide search entry point (title-bar `AutoSuggestBox`, compact-width button, Search results page), per window width, plus keyboard, Narrator and implementation plan. **Read when:** implementing or changing global search in `windows/` (lane `win-search`). Behavior and test IDs: [spec.md](spec.md). Shell chrome: [design/windows.md](../../design/windows.md).

## Decision

**A search box centred in the title bar (`TitleBar.Content` = `AutoSuggestBox`) with mixed suggestions, and a Search results page on submit.** At compact widths the box collapses to a magnifier button in the title bar that opens the same Search page with its field focused.

| Why | Evidence |
|---|---|
| Windows 11 guidance: "if global search … a searchbox should be added to the title bar, centered", with a 48 px (tall) title bar, which the shell already uses, and a responsive box. `TitleBar.Content` is that centre slot. File Explorer, Teams, Outlook and the WinUI Gallery all do this | [title bar design](https://learn.microsoft.com/windows/apps/design/basics/titlebar-design), [TitleBar control](https://learn.microsoft.com/windows/apps/design/controls/title-bar) (WinAppSDK 1.7+) |
| `AutoSuggestBox` is the WinUI search control: suggestions while typing, `QuerySubmitted` for a full search, built-in query icon and suggestion-list keyboarding | [AutoSuggestBox](https://learn.microsoft.com/windows/apps/design/controls/auto-suggest-box) |
| Suggestions-then-results-page is the WinUI Gallery pattern and keeps grouping, scope tabs and per-scope failures out of the suggestion popup, which is a flat list (guidance: a single-line "No results" item when nothing matches) | [AutoSuggestBox](https://learn.microsoft.com/windows/apps/design/controls/auto-suggest-box) |
| The shell already extends content into a WinUI `TitleBar` with the profile and bell in `RightHeader` (`windows/Festival.App/MainWindow.xaml:18-100`), so the box needs no new chrome | [design/windows.md](../../design/windows.md) |

Rejected:

| Alternative | Why not |
|---|---|
| `NavigationView.AutoSuggestBox` (pane search, like Settings; documented as app-level search) | Below 1008 epx the pane is a rail and the box becomes a button that opens the pane and focuses the box ([NavigationView](https://learn.microsoft.com/windows/apps/design/controls/navigationview)): two steps at the widths where search matters most, and the pane covers content. Settings uses it because it searches the pane's own items |
| Modal `ContentDialog` copying the web modal | A dialog blocks the window and is not how Windows apps search. Keep the web's shape (scopes, sections) on a page instead |
| `Flyout` from a title-bar button at every width | Makes search two steps even on wide windows, where Windows users expect a visible box |
| Suggestions only (no results page) | A flat popup can't show scope tabs, per-scope errors or band cards accessibly |
| Search inside each page header | Not global; conflicts with Songs' own filter box (`fst.songs.search`) |

## Layout by window width

Breakpoint is **window** width (the title bar spans the window), measured in `SizeChanged` of the root, not per page.

| Width (epx) | Presets | Title bar | Search |
|---|---|---|---|
| ≥ 1008 (wide, maximized, 1440 `wide`) | `wide`, `maximized`, `full-screen` | Back · pane toggle · icon + title · **box** (centred, `MinWidth` 320, `MaxWidth` 580 as in the WinUI Gallery) · bell · avatar · caption buttons | Box always visible |
| 720–1007 (medium, half of a 1440–2560 desktop) | `medium`, `snap-left/right` on this host (1280) | Title may collapse to the icon; box `MinWidth` 240 | Box visible |
| < 720 (compact, snapped on 1366 laptops, `compact` 500) | `compact`, `portrait-tablet` clamped | Box collapsed; **magnifier `Button`** before the bell (`fst.global-search.open`) | Button navigates to the Search page with the field focused |

Measured: at 720–1007 epx the box (`Width` = 36% of the window, clamped 240–580; 320 minimum from 1008) fits beside the title, bell, avatar and caption buttons; `TitleBar` hides the title itself when crowded. A 683-epx half (1366 × 768 laptop) and `compact` get the button. The breakpoint is `MainWindow.CompactSearchWidth`.

## Surfaces

### Title-bar box (medium and wide)

- `AutoSuggestBox` `QueryIcon="Find"`, `PlaceholderText="Search songs, players, or bands"` (web `search.placeholders.songsPlayersBands`; issue #320), `AutomationProperties.Name="Search songs, players and bands"`, `UpdateTextOnSelect="False"`. Its `AutomationId` is `fst.global-search.open` (the compact button carries the same ID; only one is ever visible). The Search page's own field is `fst.global-search.field`.
- Title-bar passthrough: `TitleBar.Content` is interactive by design; verify drag regions still work to either side of the box. `TitleBar` switches itself to a Compact visual state (hides the title, left-aligns content) when content fills the bar, but never collapses the box to an icon: the compact button below is ours. [title bar design](https://learn.microsoft.com/windows/apps/design/basics/titlebar-design), [TitleBar control](https://learn.microsoft.com/windows/apps/design/controls/title-bar) (WinAppSDK 1.7+)
- `TextChanged` with `Reason == UserInput` drives `GlobalSearchModel.Query` (250 ms debounce inside the model, not the view).
- Suggestion list (`ItemsSource` = a `List<GlobalSuggestion>` built by the model): up to **5 songs** (instant) then up to **5 players** (appended when the account search returns, so the highlighted index never moves), then up to **3 bands** (issue #320; appended when the band search returns: a people `FontIcon` E716, primary text the member names, secondary "Band · Duos", UIA name "Band, {members}, {size}"; three, not five, because band rows are the longest and the popup is a flat list), then a final **"View All Results for “{q}”"** item (`ViewAllCta.ResultsLabel`; never "See All", owner #321). While the next account search runs, earlier player rows whose names still contain the new text stay (`GlobalSearchResults.RetainMatching`; bands: `BandStillMatches`, any member name), so the list no longer collapses and regrows on every keystroke (operator batch 6.21). Progress is a `ProgressRing`; the "N songs, M players, B bands" count is spoken only (never shown); the scopes are the native `SelectorBar`. Each item: 32 px art or `PersonPicture`, primary text, secondary text ("Song · Artist" / "Player" / "Band · {size}"). UIA name "Song, {title} by {artist}" / "Player, {name}" / "Band, {members}, {size}".
- `SuggestionChosen` only updates the text for keyboard browsing; `QuerySubmitted` with `ChosenSuggestion != null` opens that result; with `null` (Enter on typed text or the query icon) opens the Search page. This is the documented pattern; filter only when the `TextChanged` reason is `UserInput`. [AutoSuggestBox](https://learn.microsoft.com/windows/apps/design/controls/auto-suggest-box)
- Escape clears the popup, then a second Escape returns focus to the previous element.

### Search page (`AppRoute.Search(query, scope)`)

- Pushed on the **current section's** `Frame` (Back returns to where the user was; re-invoking a section pops to its root as usual). Not a `NavigationView` item.
- **Results close Search, then push (spec "Navigation"; review of #355, 2026-10-06):** every result and title-bar suggestion (song, player, band card) goes through `MainWindow.OpenSearchRoute`. When the Search page is showing, it pushes the destination and then removes the Search page from the section's `Frame.BackStack` (and its route from the tracked route stack, `GlobalSearchResults.CloseSearchBelowTop`), so Back returns to the page Search was opened from and the query is not restored. When the result opens another section (the selected player's Statistics), the hidden section's Search page is popped without a transition. Band cards are the shared `Controls/BandCardView`: the Search page handles its `RouteRequested` event (→ `OpenSearchRoute`); Player Bands and the profile Bands preview leave it unset and keep the plain push. Before this, Windows pushed results over Search and Back reopened it, against the spec.
- Header: full-width `AutoSuggestBox` (same model; no suggestion popup on this page), then a `SelectorBar` **All · Songs · Players · Bands** (`fst.global-search.scope.*`; "All" is the web's no-chip state and has no ID suffix beyond `scope.all`).
- Body: one `ScrollViewer` (`fst.global-search.results`) with Songs, then Players, then Bands. In All each shown section starts with its title (`fst.global-search.section.{songs,players,bands}`: "Songs"/"Players"/"Bands", `FSTSectionHeaderStyle`, `HeadingLevel=Level2`, `Margin="0,0,0,4"`), bound to `GlobalSearchViewModel.ShowSectionTitles` (issue #348, web `SearchModal` `h3` per rendered target). A single scope has **no section title** (issue #299: the `SelectorBar` already names it). An empty category is omitted in All and never gets a title over nothing. The title fades with its rows when the section appears (`SearchPage.OnSectionShown` plays `FadeIn.Play` on it before re-staggering the list). and a non-scrolling `ListView` each (≤20 songs, ≤10 players, so no virtualization is needed and grouping stays AOT-simple), each on an `FSTRowsCardStyle` surface (4 epx inset, 12 epx row sides, hairlines between rows, a hover fill spanning the row; operator batch 6.2/6.4/6.5) so rows stay legible over the artwork background. Rows fade up with the shared `FadeIn.Stagger` (web: "rows fade up with a stagger"); `SearchPage` re-arms each list when `GlobalSearchViewModel.SectionShown` reports its section appearing (raised once per hidden→shown change), because the sections stay collapsed behind the one spinner until the slower player search settles, so without it live rows realized after the 1 s window and never faded (issue #260; checked by `search_journey.py --only fade-delayed-results`, see [load-transition](../../patterns/load-transition.md#guards-toolspattern_guardpy)). Rows: 44 px `SongArt` + title/artist; `PersonPicture` + name/"Player" ("Selected player · Statistics" for the selected one). Loading is one indeterminate 40 epx `ProgressRing` (`fst.global-search.loading`, Name "Searching") centred horizontally and vertically in the results cell below the `SelectorBar` (Windows has no bottom nav, so the cell runs to the window bottom); results stay hidden while it spins (`IsBusy`: All waits for Songs, Players **and** Bands; the Songs scope never waits for the network, Players never waits for Bands and Bands never waits for Players), so there is no inline Players progress. A players failure is the shared `ServiceStatusView` with `ShowsRetry="False"` (`fst.global-search.players-error`; no `fst.service-status.retry`, and its idle countdown line collapses so the card has no blank row; a scrape freeze still counts down and retries itself); an empty envelope hides the section in All and never renders an inline row (issue #99). When the shown scope(s) are empty (`HasEmptyState`), a centred `StackPanel` (`fst.global-search.empty`, MaxWidth 480) in its own `ScrollViewer` shows `EmptyTitle` (`SubtitleTextBlockStyle`, `HeadingLevel=Level2`, `.empty.title`), `EmptySubtitle` (`.empty.subtitle`), with no Retry (issue #299): Enter in the field re-runs the query (`SubmitCommand`). The under-two-characters hint (`fst.global-search.hint`) names the scope (`GlobalSearchResults.EnterQueryHintFor`), Bands included. Fluent check (`winui-design` layout-review): "Error — cause if known + a retry/repair affordance" is met by the error text plus the field's Enter, and "Loading — … not just a spinner with no context" by the ring's "Searching" name under the scope bar. Live check 2026-10-03: "The" in Players centres the block in the results pane (UIA bounds); All shows songs with no Players row.
- **Bands (issue #320):** `GlobalSearchViewModel` calls `FestivalApiClient.SearchBandsAsync` (`GET /api/bands/search?q=&page=1&pageSize=10`, keyless, no selected-profile header, the page validated whole by `BandSearchResponse.Validate`) together with the player search after the debounce, in every scope (web `useUnifiedSearch`); the `SelectorBar` only filters. The players-only pickers (`GlobalSearchViewModel.ForPlayers`: profile flyout, Find Rival) never request bands. Results are the canonical band card `Controls/BandCardView` (the player Bands list's card, port of web `PlayerBandCard`: member names, instrument icons, "N songs together", one Narrator stop), `AutomationId` `fst.global-search.result.band`, in an `ItemsRepeater` (`BandsList`) on the non-virtualizing `LeaderboardsCardGridLayout` (one column, 8 epx spacing): a virtualizing `StackLayout` nested in the results `ScrollViewer` prepared card 0 twice and faded it twice (`search_journey.py --only fade-delayed-results`). Invoking a card raises `BandCardView.RouteRequested`, which the page sends to `MainWindow.OpenSearchRoute`: it closes Search and pushes the band page (`GlobalSearchResults.BandRoute`: `AppRoute.Band` with `bandId`, members, `bandType`, `teamKey`) on the current section; Windows has no selected band, so a band never opens Statistics. States are the Players rules: the one ring, `ServiceStatusView` "Bands unavailable" without Retry (`fst.global-search.bands-error`), an empty envelope hides the section in All and in the Bands scope shows the centred "No bands found" / "Check the spelling or try a different band member's name." ([empty-error-states](../../patterns/empty-error-states.md) R4). The page field keeps one placeholder in every scope, like the web (whose placeholder follows the opener's targets, not the chip) and Android. The earlier `InfoBar` (`fst.global-search.bands-unavailable`) and its Band Rankings link are gone.
- `ServiceIssue` from the players read maps to `Controls/ServiceStatusView` inline in the Players section.
- The page field gets focus on `Loaded` at every width. Submitting from the title bar while the Search page is showing updates that page instead of pushing another.
- The page reuses the title-bar model's settled results for the same query (no second account search); a failed players read is never reused.

## Keyboard

| Keys | Action | Why |
|---|---|---|
| **Ctrl+E** | Focus the title-bar box (select all); compact → open the Search page | App-search key in Teams and Outlook; File Explorer maps both Ctrl+E and Ctrl+F to its box. Microsoft's accelerator table lists Ctrl+E only as "begin editing mode", so this is convention, not guidance [keyboard accelerators](https://learn.microsoft.com/windows/apps/design/input/keyboard-accelerators) |
| **Ctrl+F** | Page-local find where the page has one (Songs filter box, Rivals Find Rival); elsewhere falls back to Ctrl+E behaviour | Microsoft's table: Ctrl+F = find (F3 = find next). The WinUI Gallery binds Ctrl+F to its title-bar box because it has no page-local finds; we do (Songs filter), so page find wins and global is the fallback [keyboard accelerators](https://learn.microsoft.com/windows/apps/design/input/keyboard-accelerators) |
| Ctrl+K | Not bound | No Microsoft guidance recommends it for search (Office uses it for Insert Link) |
| ↓ / ↑, Enter | Built-in `AutoSuggestBox` suggestion navigation and submit | Platform default |
| Escape (title bar) | Closes the popup, then clears the text, then returns focus to where Ctrl+E found it | Handled in `PreviewKeyDown`: the inner `TextBox` swallows `KeyDown` |
| Escape (Search page field) | Clears the text, then goes Back | Same |
| Alt+Left / Back | From the Search page back to the previous page | Existing shell accelerators (`MainWindow.xaml.cs:67-68`) |

Ctrl+E / Ctrl+F are `KeyboardAccelerator`s on `RootGrid` (work from any page; `RootGrid.KeyboardAcceleratorPlacementMode = Hidden`, otherwise WinUI floats a bare "Ctrl+E" key tip over content); tooltips say "Search songs, players and bands (Ctrl+E)". Page-local Ctrl+F: pages implement `IPageFind.FocusFind()` (Songs filter box, Rivals Find Rival, the Search page field) in their own `*.Find.cs` partials; the shell falls back to Ctrl+E behaviour when it returns false.

## Narrator

- The box is an `Edit` with a name; suggestion list items expose names as above. The compact button, the box and its inner `TextBox` report UIA `AcceleratorKey` "Control+E" (`MainWindow.Accessibility.cs` `ExposeSearchAccelerator`; the accelerator itself lives on `RootGrid`, so WinUI exposes it on neither entry point, issue #234). After the model settles a query, raise `AutomationPeer.RaiseNotificationEvent(ActionCompleted, ImportantMostRecent, "{n} songs, {m} players, {b} bands", "fst.global-search.results")` from the box's peer (Search page: from the list); `AutomationProperties.LiveSetting` alone does not announce, the peer must raise the event. [RaiseNotificationEvent](https://learn.microsoft.com/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.automation.peers.automationpeer.raisenotificationevent)
- Headings (issues #299, #348): heading navigation lands on the page title, in All on each shown section title (Level 2, before that section's rows in Narrator order), and on the empty-state title. A single scope has no section heading. Band cards follow the player rows in tab order; there is no Retry button.
- Focus: Ctrl+E focus ring on the box; closing the Search page by Back restores focus to the previous page's last focused element (Frame navigation default); Escape from the box returns focus to the element that had it before Ctrl+E.
- High contrast: the box, `SelectorBar` and `ProgressRing` are system controls.

## Implementation plan (lane `win-search`)

| Area | Files (owned) |
|---|---|
| Core | new `Festival.Core/ViewModels/GlobalSearchViewModel.cs` (query, scope, 250 ms debounce, cancellation, per-scope state, suggestion list, announcement text), new `Festival.Core/Domain/GlobalSearchResults.cs` (grouping, limits, selected-profile → Statistics routing); reuse `Domain/SongSearch.cs` and `FestivalApiClient` `SearchPlayersAsync` |
| Routes | `Domain/AppRoute.cs` + `AppRouteParser.cs`: `AppRoute.Search(string Query, SearchScope Scope)` (`/search?q=&scope=` for deep links / `--route`) — coordinate with `win-shell` |
| App | `MainWindow.xaml` `TitleBar.Content` + compact button; `MainWindow.Search.cs` (accelerators, width breakpoint, suggestion handlers); new `Pages/SearchPage.xaml(.cs)` |
| Tests | `Festival.Core.Tests/GlobalSearchViewModelTests.cs` (debounce, cancel, late result dropped, <2 chars, empty → Enter re-runs, freeze, bands in every scope but never from the players-only pickers, suggestion ordering stable, announcement text), route parser round-trip; UIA journeys via `uiwin.py drive` at `compact`/`medium`/`wide`/`snap-left` |

Order: model + tests → title-bar box + suggestions → Search page + scopes → compact button + accelerators → Narrator notification → UIA journeys and screenshots at four presets. Coverage per [testing/windows.md](../../testing/windows.md).

## Implementation and evidence

| Area | Where |
|---|---|
| Engine | `Festival.Core/Domain/GlobalSearchResults.cs` (scopes, limits, song match, suggestion order, routing, announcement), `ViewModels/GlobalSearchViewModel.cs`; `AppRoute.Search(Text, Scope)` ↔ `/search?q=&scope=` |
| Shell | `MainWindow.Search.cs` (box, button, width breakpoint, accelerators, `OpenSearchRoute`: selected player → Statistics section; a result opened from the Search page removes it from the stack), two additive edits in `MainWindow.xaml(.cs)` |
| Page | `Pages/SearchPage.xaml(.cs)` |
| Unit tests | `Festival.Core.Tests/GlobalSearchTests.cs` |
| Journeys | `python tools/windows/search_journey.py [--axe]`: `journeys/search.json` at wide, medium (from a detail page; select a player, then its suggestion opens Statistics), compact (button, All hint, centred empty `fst.global-search.empty.title` without Retry, player → Back to Leaderboards with no Search field), snap-left (players 503 without Retry), 683×768 (song → Back to Songs, not Search) and `issue-299-hints-spinner-no-titles` (medium, pattern-only steps so it runs on a locked console: per-scope hints, the centred `fst.global-search.loading` ring via the fixture's 4 s delay for the account search `slow` with `assertaligned`/`assertlevel` against `fst.global-search.results`, results with `section.songs` and `section.players` titles read before their rows in All and gone in the Players scope (issue #348), Players 503 without Retry). The fixture logs request paths and the run fails unless both `/api/account/search` and `/api/bands/search` were requested (issue #320; the wide journey checks the All titles read Songs → Players → Bands and are gone in the Songs and Bands scopes (#348), opens a band card from the Bands scope and checks Back returns to Songs, not Search, `issue-299-hints-spinner-no-titles` covers "No bands found", band cards and a Bands 503 without Retry, and the fade journey checks `BandsList`); each journey uses an isolated settings file. `--axe` scans the Search page (`tools/windows/axe_scan.ps1`) |
| Last measured | Issue #348 (2026-10-07, Debug): 7/7 search journeys (All titles and Narrator order, none in single scopes), Axe.Windows 0 errors on the Search page, 2140 Core tests (logic 99.0%, UX 98.2%). Issue #320 (2026-10-06, Debug): 7/7 search journeys with fixture band search, Core tests and coverage gate passed. Issue #299 (2026-10-04, Debug, locked console): 6/6 search journeys, `kb-global-search`, Axe.Windows 0 errors on `search`, 1742 Core tests (logic 98.9%, UX 98.0%). Earlier: 5/5 journeys on Debug and NativeAOT Release (`--exe windows/.artifacts/app/Release-aot/FestivalScoreTracker.exe`); 0 band searches; Axe.Windows 0 errors; model/results 100% / ViewModel ≥95% lines |

## Validation (issue #234, 2026-10-04)

State matrix: `python tools/windows/a11y_matrix.py --pages tools/windows/journeys/a11y-search.json --fixture tools/windows/profile_fixture.py --scan --tabs 30 [--mode …] [--sizes …]`. It covers `search-closed`, `search-suggestions` (title-bar popup; medium and up), `search-open-hint`, `search-loading` (`rollover` is answered after 4 s; waits for `id=fst.global-search.loading`), `search-results-all/-songs/-players`, `search-empty`, `search-error` (503), `search-results-bands` (issue #320; replaced `search-bands-unavailable`) and `search-navigated`. Pattern and keyboard steps only, so it runs on a locked console. `tools/windows/tests/test_a11y.py` checks that every state page exists and parses.

| Configuration | Result |
|---|---|
| Compact, medium, wide, maximized, snapped (normal) | Pass at every size, Axe 0 errors. Tab walks: 6–9 distinct stops, none outside the window or repeated. On this 300%-scale host, `wide` is clamped to ~1270 epx and `snap-left` (640 epx) is compact (button + Search page). |
| Display 100% (wide, snapped) and 150% (medium, wide, maximized) | Pass, Axe 0. At 100%, snapped is 1920 epx: title-bar box and centred column. At 150%, the full nav pane is open. |
| High contrast (Desert; compact, medium) | Pass, Axe 0: system colours for the box, the `SelectorBar`, focus rings, the ring and the cards; artwork hidden. |
| Light and dark theme (medium) | Pass, Axe 0. The app stays dark under the system light theme (dark-only deviation, [platforms/windows.md](../../platforms/windows.md)). |
| Text 200% (compact, medium) | Pass, Axe 0. The title, field, scopes, rows, the service-status card and the then-current bands InfoBar wrap with no clipping; the title-bar box keeps its placeholder. |
| Keyboard | `a11y-keyboard.json` `kb-global-search` (Ctrl+E → type → Enter → Alt+Left) at compact/medium/wide, `kb-titlebar-order(-compact)` pass. Tab order on the page: scopes → rows → shell, with a visible focus rect on a keyboard-selected scope. |
| Suggestion popup (every mode) | Pass, Axe 0 since #534 (`search-suggestions` at medium in `windows-ui`). Before, WinUI's windowed suggestion popup reported 2 `BoundingRectangleCompletelyObscuresContainer` errors on its `PopupHost`/`InputSiteWindowClass` (open item 8); every `AutoSuggestBox` now sets `controls:PopupHosting.InWindow="True"`, which keeps the template's `SuggestionsPopup` in the window. |
| Live public service | `--live` screenshots of closed, hint, results (All, Songs, Players), empty, Bands and navigated at compact/medium/maximized/snapped, plus Desert, text 200% and 150%. |

Fixed: no entry point exposed Ctrl+E to UI Automation, so Narrator didn't announce it (navigation items already reported Ctrl+1…). The compact button's tooltip said "Search (Ctrl+E)" instead of the documented "Search songs and players (Ctrl+E)" (since issue #320 "Search songs, players and bands (Ctrl+E)").

The `winui-design` review (WinApp CLI 0.7.1) is aligned:
- `find-ui` shows the Gallery title-bar sample with an `AutoSuggestBox` in `TitleBar.Content`, and its suggestions are filtered on `UserInput` like `MainWindow.Search.cs`.
- "2–3 modes → SelectorBar" matches the scopes.
- "Error – cause + retry affordance" matches the service-status card.
- `find-api` confirms the AutoSuggestBox/TitleBar properties used.

Deliberate deviations:
- The title-bar box has no visible label (placeholder plus accessible name), following the Gallery/File Explorer title-bar convention. The Search page has a visible "Search" heading.
- The app is dark only.

PR #199 (issue #299) has since merged: the page has no section titles, one centred `fst.global-search.loading` ring and no Retry under the empty state. The #234 state matrix was re-run on the merged page (2026-10-04, normal mode, compact/medium/wide): every state loads, Axe 0 errors apart from the suggestion popup's framework errors, 1777 Core tests pass.

The motion and suggestion popup couldn't be captured as screen shots or recordings: the console was locked, and the popup is a separate window. The popup is asserted through UIA instead (`Player, Fixture Player 1`).

## Open

- The profile flyout ([profile-selection/windows.md](../profile-selection/windows.md)) and Rivals' Find Rival use `GlobalSearchViewModel.ForPlayers(session, excludeSelected)`: the same engine locked to the Players scope, with no catalogue matching or suggestions, plus the picker-only `PlayersHint`/`CanRetryPlayers`. Find Rival excludes the selected player.
- Fixed 2026-09-28 (`MainWindow.TitleBar.cs`): `TitleBar.RightHeader` used to sit right after the pane toggle below ~720 epx (and ~72 epx short of the caption buttons at every width). Cause: the WinUI `TitleBar` template sizes `RightPaddingColumn` from `AppWindow.TitleBar.RightInset`, which is physical pixels, without dividing by the scale (324 px reserved for 216 px of caption buttons at 150%), so the star content column collapsed. The shell rewrites that column to `RightInset / RasterizationScale` whenever the control or a DPI change sets it (a property-changed callback; no idle work). Content stays centred and draggable; only the 48-epx minimum drag gutter separates the avatar from Minimize.
- Narrator: counts are raised with `RaiseNotificationEvent` (title-bar box when focused; page field); an operator Narrator pass is still needed.
- Tablet posture needs real touch hardware (see [platforms/windows.md](../../platforms/windows.md)); `portrait-tablet` approximates it.
