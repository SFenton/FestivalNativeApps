# Empty and error states

> **What:** loading, no-result, unavailable and placeholder outcomes, including their copy, centring and retry behavior. **Read when:** a query or page can return no content or fail.

Status: **current**, 2026-10-08. Provenance: #35, #65, #99, #140, #299, #320, #348, #377.

## Intent

Every result region communicates whether it is loading, empty or unavailable without turning a failure into a successful empty result. The web supplies the centered-title/subtitle model; native code supplies platform controls and accessibility.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/components/common/EmptyState.tsx` (`EmptyState`, `Layout.shellChromeHeight`) | Optional icon, bold title and subtitle centre in the available region; `fullPage` centres below shell chrome. |
| `FortniteFestivalWeb/src/components/search/SearchModal.tsx` (`SearchModal`, `renderResults`, `shouldRenderGlobalSection`) | Search owns its results region rather than adding a separate page-level error surface. In All, each category with results or an error gets a `<section>` with an `<h3>` title; empty categories are hidden and "No results found." shows only when none render. A single scope shows "No songs/players/bands found." |

## Rules

- **R1. Keep outcome types distinct.** Loading shows a labelled native progress indicator; no-results shows a centered title and scope-specific subtitle; unavailable/error retains a failure title and reason. Never label a failed read as “No results.”
- **R2. Centre empty states in their actual region.** The shared empty component fills the available viewport/list region, not merely its content height. Search centres below the scope switcher and above lower chrome, with text wrapping or scrolling at large type. A no-result list row inside an existing scroll view (Full Rankings, Band Rankings, Song Band Scores) uses the inline placement instead: the same text, centred horizontally with generous vertical padding (web `EmptyState` without `fullPage`).
- **R8. An empty state is centred text only: no card, no Reset or Retry (#377).** Every empty page or region (Songs, Item Shop, Suggestions, Rivals, Player Bands, Notifications, Player History, Statistics, Search, leaderboards, dual-source secondaries, Coming Soon) uses the one shared component: an optional decorative icon, a bold title and a subtitle, centred horizontally and vertically, on the page background. It never draws a card or material behind itself and never adds a Reset Filters or Retry button; the subtitle says what to try next, and the page's own control (the Filter sheet's Reset, the search field, pull to refresh) is how the user acts. The only allowed button is a prerequisite action the page can't work without (Choose Profile). Errors and paused states keep their own components with Retry (R1).
- **R3. Global Search has one result state.** In **All**, each category that has rows or a failure sits under its Songs/Players/Bands section title, in that order (the shared [section-headers](section-headers.md) R1 heading; web `SearchModal` `<h3>`, #348). An empty category is omitted, with no per-category "no results" row; only when every category is empty does All show its one centred empty state. A selected scope has no section title because its chip names it (#299) and shows its own centred empty state. Search shows one centred `Searching` indicator and scope-specific short-query hints. Failed and empty global-search results have no Retry button; submitting the same search or editing it reruns the query (#299).
- **R4. Preserve per-scope copy.** A subtitle says what was searched and what to try next (Bands: "No Bands Found" / "Check the spelling or try a different band member's name.", #320); a failed Bands search says "Bands unavailable", never "No bands found". A platform that has not ported band search yet states why its Bands scope is unavailable. Do not replace these with a generic “Error” message.
- **R5. Use the canonical components.** Apple uses `FestivalEmptyState` (Global Search's `GlobalSearchEmptyStateView` and `ComingSoonView` wrap it), `FestivalLoadingView` or `ServiceUnavailableView`, never `ContentUnavailableView` or a feature-local empty card; Android uses `FestivalEmptyState`/`FestivalLoading`; Windows uses the centered Search page state and `ServiceStatusView`. Material/Fluent controls remain native rather than imitating web markup.
- **R6. Replace loading completely.** A spinner gives way to rows, an empty state or an error state; it never remains beside stale placeholders (#35, #65).
- **R7. Keep the full-page failure off a separating hinge.** On Android the full-page service status uses the shared hinge side rule of [modal-shell](modal-shell.md) R8 (`HingeSide`, via `serviceStatusHingeSide`): the wider or leading side in book posture, below the hinge in tabletop, so its heading, message and Retry never straddle the fold (#140).

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Centred empty state (every page/region) | `apple/Sources/FestivalUI/Common/FestivalEmptyState.swift` `FestivalEmptyState` (`.fill` / `.inline` placement; `.combined` reading for Search); `FoldAvoidingPlacement` keeps it off the iPhone Duo fold | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/LoadGate.kt` `FestivalEmptyState` | `windows/Festival.App/Pages/SearchPage.xaml` `fst.global-search.empty` |
| Centered search empty | `apple/Sources/FestivalUI/Features/Search/GlobalSearchEmptyState.swift` `GlobalSearchEmptyStateView` (wraps `FestivalEmptyState`) | `android/app/src/main/java/com/festivalscoretracker/android/ui/search/GlobalSearch.kt` `GlobalSearchEmptyState` | `windows/Festival.App/Pages/SearchPage.xaml` `fst.global-search.empty` |
| Loading indicator | `apple/Sources/FestivalUI/Common/FestivalLoadingView.swift` `FestivalLoadingView` | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/ServiceStatus.kt` `FestivalLoading` | `windows/Festival.App/Pages/SearchPage.xaml` `fst.global-search.loading` |
| Unavailable/placeholder | `apple/Sources/FestivalUI/Common/ServiceStatusViews.swift` `ServiceUnavailableView`; `apple/Sources/FestivalUI/Common/ComingSoonView.swift` `ComingSoonView` (wraps `FestivalEmptyState`) | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/LoadGate.kt` `FestivalEmptyState` | `windows/Festival.App/Controls/ServiceStatusView.xaml` `ServiceStatusView` |
| Full-page service status | `apple/Sources/FestivalUI/Common/ServiceStatusViews.swift` `ServiceUnavailableView` | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/ServiceStatus.kt` `ServiceStatusView` (hinge side: `core/nav/HingeSide.kt` `HingeSide`) | `windows/Festival.App/Controls/ServiceStatusView.xaml` `ServiceStatusView` |

## Decisions

- **No Reset/Retry in empty states; prerequisite actions stay (#377, agent decision, owner may override with `/choose`).** The owner asked for "no background card or reset filters button … vertically/horizontally centered … applied everywhere there's an empty state". HIG Writing (`writing.md`, guidance): "Provide clear next steps on any blank screens, with a button or link if possible." The explicit owner choice wins over this "if possible" guidance for Reset (the subtitle names the next step and the Filter sheet keeps Reset Filters); Choose Profile buttons stay because nothing else on those pages lets the user meet the prerequisite. HIG Layout (`layout.md`): content stays within safe areas and adapts to every size, so the fill placement scrolls at accessibility text sizes.
- **Item Shop copy follows the web (#377).** "No offers match these filters" did **not** match the web: the web Shop has no filters and says "No songs in the Item Shop" / "Check back later — the shop updates regularly." Apple's genuine-empty Shop uses that copy; the native-only filtered state borrows the web's filtered-empty wording ("No songs match your filters" / "Try changing your filters to see more of the Item Shop."), matching Songs and Suggestions.
- **Not `ContentUnavailableView`.** The system view failed iOS 26.5 Dynamic Type audits (see `ServiceStatusView`), so the shared component is scalable text in GeometryReader + ScrollView + `minHeight`. `pattern_guard` blocks new `ContentUnavailableView` uses in Apple sources.
- **Out of scope for R8:** in-card section empties that mirror web `InstrumentEmptyState` (Player Bands preview card, Band Detail rank-history/scored-songs cards, song profile summary, Leaderboards card empties, Compete footnotes) stay inside their section card; player-search sheets (Choose Profile, Find Rival) keep Retry because an empty `/api/account/search` envelope can be a timeout ([service-safety](../platforms/service-safety.md)).

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Android Bands "not found" centres its message in the **upper** half in tabletop (`rememberBandTabletopHinge`, [pages/bands/android.md](../pages/bands/android.md), #118), while R7 keeps the full-page status below the hinge. | Two empty/error surfaces pick different tabletop halves; deliberate for Bands (text only, no controls, the lower half holds the bottom bar). | TODO(orchestrator): owner to confirm whether text-only page empty states keep the upper half or follow R7. |

## Guards (tools/pattern_guard.py)

- `empty-error-states/global-search-retry`
- `empty-error-states/no-content-unavailable-view`
- `empty-error-states/no-empty-card`
