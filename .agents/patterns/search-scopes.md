# Search scopes

> **What:** the scope bar on every unified search surface: global search (All · Songs · Players · Bands) and the profile search (All · Players · Bands). It covers what each surface searches, the default scope, how a scope narrows results and the shared engine behind both. **Read when:** changing global search, the Profiles/Select Profile sheet, or adding a search surface that finds players, bands or songs.

Status: **current**, 2026-10-10. Provenance: #299, #320, #348, #600.

## Intent

Search looks and behaves the same wherever people find something. A surface starts broad, on **All**, and searches everything it can find at once. The scope bar then narrows what shows, and people never have to guess which kind of name they typed.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/components/search/SearchModal.tsx` (`SearchModal`, `resolveSearchTargets`) | One modal, configured by `availableTargets`; with none it targets songs, players and bands (global search). Every available target is on by default. |
| `FortniteFestivalWeb/src/App.tsx` (`PROFILE_SEARCH_CONFIG`, `PROFILE_SEARCH_TARGETS`) | The profile search targets `['players', 'bands']` with the placeholder `search.placeholders.playersBands` ("Search players or bands…"). |
| `FortniteFestivalWeb/src/hooks/data/useUnifiedSearch.ts` (`useUnifiedSearch`) | Searches each enabled target independently after the 250 ms debounce; songs locally, players `/api/account/search`, bands `/api/bands/search`. |

The web's Find Rival search (`pages/rivals/RivalsPage.tsx`, `availableTargets={['players']}`) is players-only.

## Rules

1. **R1. One engine per platform.** Every unified search surface uses the platform's global-search engine and results view, configured with its targets. Never build a second search state machine, scope picker or results list for a surface that finds players, bands or songs. Find Rival is not a unified search surface: it stays players-only, like the web.
2. **R2. Targets.** Global search finds songs, players and bands. Profile search finds players and bands only (web `PROFILE_SEARCH_CONFIG`). A surface never shows a scope for something it cannot search.
3. **R3. Scope bar: All first, starting on All.** The scope bar lists All, then each target in the web's order (Songs, Players, Bands). It opens on All, and switching scope only filters what shows: no new request (the targets were all searched). Apple HIG Search fields (`search-fields.md`): "Use scope bars before or after a search for defined categories, starting broad and letting people narrow" (**should**).
4. **R4. Native control.** Apple: a segmented `Picker` (an `NSSegmentedControl` on macOS) titled in Title Case nouns (HIG Segmented controls: "Label with nouns or noun phrases in title-style capitalization", **should**). Android: Material 3 segmented buttons. Windows: `SelectorBar`. Each exposes its selected segment to assistive technologies.
5. **R5. All lists every target in order.** In All, each section with rows or a failure gets its title ([section-headers](section-headers.md) R9); an empty section hides while another has results. When every section is empty, one centred empty state names the surface's targets ([empty-error-states](empty-error-states.md)). A failed section reports itself; it never reads as empty.
6. **R6. Copy names the targets.** The prompt and the short-query hint name what the current scope searches. Global All: "Search songs, players, or bands"; profile All: "Search players or bands" (web "Search players or bands…"). Narrow scopes share "Search players" and "Search bands". HIG Searching (`searching.md`): "Show current scope with descriptive placeholder, scope bar, or title" (**should**).
7. **R7. Results open the same destinations.** A song opens Song Details, a player their profile (the selected player opens Statistics) and a band its band page, on every surface. Selecting a band as the profile is not built on natives yet, so a band result opens its page.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Targets, scopes, copy, empty/spinner/announcement rules (R2, R3, R5, R6) | `apple/Sources/FestivalCore/GlobalSearch.swift` `GlobalSearchTargets` (`.global`, `.profiles`; `scopes`, `sections`), `GlobalSearch` rules taking `targets:` | `android/app/src/main/java/com/festivalscoretracker/android/core/search/GlobalSearch.kt` `SearchScope`, `GlobalSearchResults` | `windows/Festival.Core/Domain/GlobalSearchResults.cs` `SearchScope`, `SearchScopes` |
| Engine (R1, R3) | `apple/Sources/FestivalUI/Features/Search/GlobalSearchModel.swift` `GlobalSearchModel(targets:)` | `android/app/src/main/java/com/festivalscoretracker/android/presentation/search/GlobalSearchViewModel.kt` `GlobalSearchViewModel` | `windows/Festival.Core/ViewModels/GlobalSearchViewModel.cs` `GlobalSearchViewModel` |
| Scope bar and results (R4, R5, R7) | `apple/Sources/FestivalUI/Features/Search/GlobalSearchView.swift` `GlobalSearchResults` (identifiers per surface via `GlobalSearchIdentifiers`: `fst.global-search.*`, `fst.profile.*`) | per platform check | per platform check |

Apple consumers: the Search tab (`GlobalSearchTab`), the Mac and iPad search sheet (`GlobalSearchSheet`), the iPhone Duo bottom field and the Profiles sheet (`ProfileSelectionSheet`, `GlobalSearchModel(targets: .profiles)`, issue #600). Apple tests: Core `GlobalSearchTests` (`profileTargets*`), hosted `ProfileSelectionSheetRenderTests`, XCUITest `ProfileSearchScopeJourneyTests` and `GlobalSearchJourneyTests`.

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Android and Windows profile sheets had their own Players/Bands picker with Bands gated when this pattern was recorded | R1–R4 | Their #600 checks move them onto the platform engine |

## Guards (`tools/pattern_guard.py`)

None yet.
