# Global search — Windows notes

> **What:** the WinUI 3 design for the app-wide search entry point (title-bar `AutoSuggestBox`, compact-width button, Search results page), per window width, plus keyboard, Narrator and implementation plan. **Read when:** implementing or changing global search in `windows/` (lane `win-search`). Behavior and test IDs: [spec.md](spec.md). Shell chrome: [design/windows.md](../../design/windows.md).

## Decision

**A search box centred in the title bar (`TitleBar.Content` = `AutoSuggestBox`) with mixed suggestions, and a Search results page on submit.** At compact widths the box collapses to a magnifier button in the title bar that opens the same Search page with its field focused.

| Why | Evidence |
|---|---|
| Windows 11 guidance: "if global search … a searchbox should be added to the title bar, centered", with a 48 px (tall) title bar, which the shell already uses, and a responsive box. `TitleBar.Content` is that centre slot. File Explorer, Teams, Outlook and the WinUI Gallery all do this | [title bar design](https://learn.microsoft.com/windows/apps/design/basics/titlebar-design), [TitleBar control](https://learn.microsoft.com/windows/apps/design/controls/title-bar) (WinAppSDK 1.7+) |
| `AutoSuggestBox` is the WinUI search control: suggestions while typing, `QuerySubmitted` for a full search, built-in query icon and suggestion-list keyboarding | [AutoSuggestBox](https://learn.microsoft.com/windows/apps/design/controls/auto-suggest-box) |
| Suggestions-then-results-page is the WinUI Gallery pattern and keeps grouping, scope tabs, Retry and the band explanation out of the suggestion popup, which is a flat list (guidance: a single-line "No results" item when nothing matches) | [AutoSuggestBox](https://learn.microsoft.com/windows/apps/design/controls/auto-suggest-box) |
| The shell already extends content into a WinUI `TitleBar` with the profile and bell in `RightHeader` (`windows/Festival.App/MainWindow.xaml:18-100`), so the box needs no new chrome | [design/windows.md](../../design/windows.md) |

Rejected:

| Alternative | Why not |
|---|---|
| `NavigationView.AutoSuggestBox` (pane search, like Settings; documented as app-level search) | Below 1008 epx the pane is a rail and the box becomes a button that opens the pane and focuses the box ([NavigationView](https://learn.microsoft.com/windows/apps/design/controls/navigationview)): two steps at the widths where search matters most, and the pane covers content. Settings uses it because it searches the pane's own items |
| Modal `ContentDialog` copying the web modal | A dialog blocks the window and is not how Windows apps search. Keep the web's shape (scopes, sections) on a page instead |
| `Flyout` from a title-bar button at every width | Makes search two steps even on wide windows, where Windows users expect a visible box |
| Suggestions only (no results page) | A flat popup can't show scope tabs, per-scope errors, Retry or the Bands explanation accessibly |
| Search inside each page header | Not global; conflicts with Songs' own filter box (`fst.songs.search`) |

## Layout by window width

Breakpoint is **window** width (the title bar spans the window), measured in `SizeChanged` of the root, not per page.

| Width (epx) | Presets | Title bar | Search |
|---|---|---|---|
| ≥ 1008 (wide, maximized, 1440 `wide`) | `wide`, `maximized`, `full-screen` | Back · pane toggle · icon + title · **box** (centred, `MinWidth` 320, `MaxWidth` 580 as in the WinUI Gallery) · bell · avatar · caption buttons | Box always visible |
| 720–1007 (medium, half of a 1440–2560 desktop) | `medium`, `snap-left/right` on this host (1280) | Title may collapse to the icon; box `MinWidth` 240 | Box visible |
| < 720 (compact, snapped on 1366 laptops, `compact` 500) | `compact`, `portrait-tablet` clamped | Box collapsed; **magnifier `Button`** before the bell (`fst.global-search.open`) | Button navigates to the Search page with the field focused |

TODO(win-search): confirm the 720 epx collapse point by measurement: box `MinWidth` + title + three title-bar buttons + caption buttons must fit without clipping `RightHeader`. Snapped windows on this host are exact halves (`uiwin.py resize snap-left`), so also test a 683-epx half (1366 × 768 laptop).

## Surfaces

### Title-bar box (medium and wide)

- `AutoSuggestBox` `QueryIcon="Find"`, `PlaceholderText="Search songs or players"`, `AutomationProperties.Name="Search songs and players"`, `AutomationId` `fst.global-search.field`. The box itself is `fst.global-search.open` at these widths (one ID per window).
- Title-bar passthrough: `TitleBar.Content` is interactive by design; verify drag regions still work to either side of the box. `TitleBar` switches itself to a Compact visual state (hides the title, left-aligns content) when content fills the bar, but never collapses the box to an icon: the compact button below is ours. [title bar design](https://learn.microsoft.com/windows/apps/design/basics/titlebar-design), [TitleBar control](https://learn.microsoft.com/windows/apps/design/controls/title-bar) (WinAppSDK 1.7+)
- `TextChanged` with `Reason == UserInput` drives `GlobalSearchModel.Query` (250 ms debounce inside the model, not the view).
- Suggestion list (`ItemsSource` = a `List<GlobalSuggestion>` built by the model): up to **5 songs** (instant) then up to **5 players** (appended when the account search returns, so the highlighted index never moves), then a final **"See all results for "{q}""** item. Each item: 32 px art or `PersonPicture`, primary text, secondary text ("Song · Artist" / "Player"). UIA name "Song, {title} by {artist}" / "Player, {name}".
- `SuggestionChosen` only updates the text for keyboard browsing; `QuerySubmitted` with `ChosenSuggestion != null` opens that result; with `null` (Enter on typed text or the query icon) opens the Search page. This is the documented pattern; filter only when the `TextChanged` reason is `UserInput`. [AutoSuggestBox](https://learn.microsoft.com/windows/apps/design/controls/auto-suggest-box)
- Escape clears the popup, then a second Escape returns focus to the previous element.

### Search page (`AppRoute.Search(query, scope)`)

- Pushed on the **current section's** `Frame` (Back returns to where the user was; re-invoking a section pops to its root as usual). Not a `NavigationView` item.
- Header: full-width `AutoSuggestBox` (same model; no suggestion popup on this page), then a `SelectorBar` **All · Songs · Players · Bands** (`fst.global-search.scope.*`; "All" is the web's no-chip state and has no ID suffix beyond `scope.all`).
- Body: `ListView` with grouped sections (`CollectionViewSource` + `GroupStyle` headers as UIA headings level 2) Songs → Players, each row reusing the Songs row visuals (`Controls/SongRowVisuals.cs`) or the profile flyout's player template; per-section `ProgressRing` (`fst.global-search.players-loading`), hint, Retry.
- **Bands** tab: no request; `InfoBar` (Informational, not closable) with the [spec](spec.md#band-scope-blocked) explanation and a "Band Rankings" `HyperlinkButton` (`fst.global-search.bands-unavailable`).
- `ServiceIssue` from the players read maps to `Controls/ServiceStatusView` inline in the Players section.
- Compact: the page is the only surface; the field gets focus on navigation (`FocusState.Programmatic` after `Loaded`).

## Keyboard

| Keys | Action | Why |
|---|---|---|
| **Ctrl+E** | Focus the title-bar box (select all); compact → open the Search page | App-search key in Teams and Outlook; File Explorer maps both Ctrl+E and Ctrl+F to its box. Microsoft's accelerator table lists Ctrl+E only as "begin editing mode", so this is convention, not guidance [keyboard accelerators](https://learn.microsoft.com/windows/apps/design/input/keyboard-accelerators) |
| **Ctrl+F** | Page-local find where the page has one (Songs filter box, Rivals Find Rival); elsewhere falls back to Ctrl+E behaviour | Microsoft's table: Ctrl+F = find (F3 = find next). The WinUI Gallery binds Ctrl+F to its title-bar box because it has no page-local finds; we do (Songs filter), so page find wins and global is the fallback [keyboard accelerators](https://learn.microsoft.com/windows/apps/design/input/keyboard-accelerators) |
| Ctrl+K | Not bound | No Microsoft guidance recommends it for search (Office uses it for Insert Link) |
| ↓ / ↑, Enter, Escape | Built-in `AutoSuggestBox` suggestion navigation, submit, dismiss | Platform default |
| Alt+Left / Back | From the Search page back to the previous page | Existing shell accelerators (`MainWindow.xaml.cs:67-68`) |

Register Ctrl+E / Ctrl+F as `KeyboardAccelerator`s on `RootGrid` (so they work from any page) with `ScopeOwner` unset, and show them in tooltips ("Search (Ctrl+E)"). Page-local Ctrl+F: pages expose an optional `IPageFind.FocusFind()`; the shell calls it if the current page implements it.

## Narrator

- The box is an `Edit` with a name; suggestion list items expose names as above. After the model settles a query, raise `AutomationPeer.RaiseNotificationEvent(ActionCompleted, ImportantMostRecent, "{n} songs, {m} players", "fst.global-search.results")` from the box's peer (Search page: from the list); `AutomationProperties.LiveSetting` alone does not announce, the peer must raise the event. [RaiseNotificationEvent](https://learn.microsoft.com/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.automation.peers.automationpeer.raisenotificationevent)
- Section headers: `AutomationProperties.HeadingLevel=Level2`. Retry, InfoBar and Band Rankings link are in tab order after the list.
- Focus: Ctrl+E focus ring on the box; closing the Search page by Back restores focus to the previous page's last focused element (Frame navigation default); Escape from the box returns focus to the element that had it before Ctrl+E.
- High contrast: the box and `SelectorBar` are system controls; section headers use the existing `FSTSectionHeaderStyle`.

## Implementation plan (lane `win-search`)

| Area | Files (owned) |
|---|---|
| Core | new `Festival.Core/ViewModels/GlobalSearchViewModel.cs` (query, scope, 250 ms debounce, cancellation, per-scope state, suggestion list, announcement text), new `Festival.Core/Domain/GlobalSearchResults.cs` (grouping, limits, selected-profile → Statistics routing); reuse `Domain/SongSearch.cs` and `FestivalApiClient` `SearchPlayersAsync` |
| Routes | `Domain/AppRoute.cs` + `AppRouteParser.cs`: `AppRoute.Search(string Query, SearchScope Scope)` (`/search?q=&scope=` for deep links / `--route`) — coordinate with `win-shell` |
| App | `MainWindow.xaml` `TitleBar.Content` + compact button; `MainWindow.Search.cs` (accelerators, width breakpoint, suggestion handlers); new `Pages/SearchPage.xaml(.cs)` |
| Tests | `Festival.Core.Tests/GlobalSearchViewModelTests.cs` (debounce, cancel, late result dropped, <2 chars, empty → Retry, freeze, bands no request, suggestion ordering stable, announcement text), route parser round-trip; UIA journeys via `uiwin.py drive` at `compact`/`medium`/`wide`/`snap-left` |

Order: model + tests → title-bar box + suggestions → Search page + scopes → compact button + accelerators → Narrator notification → UIA journeys and screenshots at four presets. Coverage per [testing/windows.md](../../testing/windows.md).

## Open

- The profile flyout keeps its own Players/Bands search ([profile-selection/windows.md](../profile-selection/windows.md)); later it can bind to `GlobalSearchViewModel` with the Players scope.
- Tablet posture needs real touch hardware (see [platforms/windows.md](../../platforms/windows.md)); `portrait-tablet` approximates it.
