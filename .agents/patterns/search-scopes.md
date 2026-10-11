# Search scopes

> **What:** how a native search narrows its result kinds: global search (Songs · Players · Bands) and the profile search (All · Players · Bands), which runs the same engine narrowed to players and bands. **Read when:** adding a search surface, changing a scope control or deciding which kinds a picker searches.

Status: **current**, 2026-10-10. Provenance: #299, #320, #348, #573, #600.

## Intent

A search that can find several kinds of thing starts broad and lets people narrow. Picking a profile is the same search as global search without songs, so it behaves the same way: players and bands appear together under All, and a scope shows one kind.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/components/search/SearchModal.tsx` (`SearchModal`) | One modal for global and profile search; the profile search's targets are `players` and `bands`, both searched by default, with a scope per target. Section titles name each kind in the mixed list. |
| `FortniteFestivalWeb/src/App.tsx` (`PROFILE_SEARCH_CONFIG`) | The profile search targets `['players', 'bands']` with the placeholder "Search players or bands…". |
| `FortniteFestivalWeb/src/hooks/data/useUnifiedSearch.ts` (`useUnifiedSearch`) | One debounced engine for every target; only the targeted kinds are fetched. |

## Rules

1. **R1. One engine per platform.** Every search over songs, players or bands runs the platform's global-search engine with the kinds it needs as its targets (Android `GlobalSearchViewModel(targets = …)`, Windows `GlobalSearchViewModel.ForProfiles`, Apple `GlobalSearchModel`). A picker never adds a second debounce, minimum-length, failure or announcement mechanism. Find Rival is the exception: a rival is always a player, so it keeps the players-only picker.
2. **R2. Start broad.** The profile search offers **All · Players · Bands** and starts on All every time it opens, with players and bands searched together (web `SearchModal`, owner #600). Players or Bands narrows to one kind and requests only that kind where the platform fetches per scope; Apple searches every target in parallel whatever the scope (like web `useUnifiedSearch`), so its scopes only filter. Global search keeps its own scopes (Songs · Players · Bands, with no chip selected meaning All on Android, #299).
3. **R3. Same rows, same order, same titles.** Results reuse global search's rows: players before bands, each kind titled only in All ([section-headers](section-headers.md) R9), no titles in a single scope. Empty and failed kinds follow [empty-error-states](empty-error-states.md): an empty kind is omitted, a failed kind shows its inline failure, and only an all-empty search shows "No results found".
4. **R4. Results open what the platform supports.** A player result views the player (the selected player opens Statistics). A band result opens its Band page until a band can be the selected profile; no scope shows a "not available" gate message (owner #600).
5. **R5. A native scope control with an explicit All.** Apple uses the system scope bar, Android a Material 3 `SingleChoiceSegmentedButtonRow`, Windows a `SelectorBar`. Each segment is at least the platform target (44 pt, 48 dp, 40 epx), exposes its selected state, and is read in order (All, Players, Bands) between the picker's title and its field. Material 3 segmented buttons: "Segmented buttons help people select options, switch views, or sort elements" (should). Apple HIG Search fields: use a scope bar for defined categories, starting broad and letting people narrow (should). WinUI SelectorBar: for switching between a small set of views (should).
6. **R6. Copy names the targets.** The prompt and short-query hint name what the current scope searches: profile All "Search players or bands" (web "Search players or bands…"), Players "Search players", Bands "Search bands". HIG Searching: "Show current scope with descriptive placeholder, scope bar, or title" (should).
7. **R7. Service safety.** Band search is the allowlisted read-only `/api/bands/search` ([service-safety](../platforms/service-safety.md#endpoint-allowlist)); no picker sends selected-profile headers, and an unsendable query (under two characters) sends nothing.

## Agent decision (#600, 2026-10-10): an explicit All segment on Android

Question: Android global search has no All chip (no chip selected means All, #299), but #600 asks for "All, Players, Bands, similar to global search".

| Option | What you see | Guidance (strength) | Web / pattern precedent | Trade-offs |
|---|---|---|---|---|
| A. Global search's toggle `FilterChip`s, Players · Bands, none selected = All | Two pills, neither selected at first | M3 filter chips: "Filter chips use tags or descriptive words to filter content" (should) | Android global search (#299) | No visible All, which the owner named; a third chip would be a second chip style |
| **B. `SingleChoiceSegmentedButtonRow` All · Players · Bands (chosen)** | Three connected segments, All selected | M3 segmented buttons: "Segmented buttons help people select options, switch views, or sort elements" (should); HIG scope bar, starting broad (should) | Apple and Windows profile search use an explicit All; the sheet already used a segmented row for Players · Bands | One extra segment; differs from global search's chips |

Chose **B**: the owner named the three scopes, the sheet already used M3 segmented buttons, and Apple and Windows show an explicit All. Owner may override with `/choose A`.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Engine and targets (R1, R2, R6, R7) | `apple/Sources/FestivalUI/Features/Search/GlobalSearchModel.swift` `GlobalSearchModel(targets:)`; targets, scopes, copy and empty/announcement rules in `apple/Sources/FestivalCore/GlobalSearch.swift` `GlobalSearchTargets` (`.global`, `.profiles`) | `android/app/src/main/java/com/festivalscoretracker/android/presentation/search/GlobalSearchViewModel.kt` `GlobalSearchViewModel` (`targets`, `selectScope`); scopes and copy in `core/search/GlobalSearch.kt` `SearchScope.profileTargets` / `profileScopes` | `windows/Festival.Core/ViewModels/GlobalSearchViewModel.cs` `GlobalSearchViewModel` |
| Rows and titles (R3, R4) | `GlobalSearchView.swift` `GlobalSearchResults` | `ui/search/GlobalSearch.kt` `searchResultItems` (with `SearchResultTags`), `SearchAnnouncement` | Search page and profile flyout result lists |
| Profile scope control (R5) | `GlobalSearchView.swift` `GlobalSearchResults` scope bar in `ProfileSelectionSheet` (identifiers per surface via `GlobalSearchIdentifiers`: `fst.profile.scope`) | `ui/profile/ProfileSheet.kt` `ScopeRow` (`fst.profile.scope.{all,players,bands}`) | profile flyout `SelectorBar` (`fst.profile.scope.{all,players,bands}`) |

Consumers: global search on every platform (Apple: Search tab, Mac/iPad search sheet, iPhone Duo field); the profile search on every platform (Apple `ProfileSelectionSheet` with `GlobalSearchModel(targets: .profiles)`, Android `ProfileSheet`, Windows profile flyout; issue #600). Not a consumer: Find Rival (players-only, R1).

## Known debt

None: Apple, Android and Windows profile searches all run their platform engine since #600.

## Guards (`tools/pattern_guard.py`)

None yet: the engine is shared through its constructor, which a regex can't check. `ProfileSelectionSheetStatesUiTest`, `GlobalSearchViewModelTest` (profile-search region) and `ProfileSelectionDeviceTest` pin the Android rules; Apple: Core `GlobalSearchTests` (`profileTargets*`), hosted `ProfileSelectionSheetRenderTests`, XCUITest `ProfileSearchScopeJourneyTests` and `GlobalSearchJourneyTests`.
