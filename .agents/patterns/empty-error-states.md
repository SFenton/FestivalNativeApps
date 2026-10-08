# Empty and error states

> **What:** loading, no-result, unavailable and placeholder outcomes, including their copy, centring and retry behavior. **Read when:** a query or page can return no content or fail.

Status: **current**, 2026-10-07. Provenance: #35, #65, #99, #140, #299, #320, #348, #377.

## Intent

Every result region communicates whether it is loading, empty or unavailable without turning a failure into a successful empty result. The web supplies the centered-title/subtitle model; native code supplies platform controls and accessibility.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/components/common/EmptyState.tsx` (`EmptyState`, `Layout.shellChromeHeight`) | Optional icon, bold title and subtitle centre in the available region; `fullPage` centres below shell chrome. |
| `FortniteFestivalWeb/src/components/search/SearchModal.tsx` (`SearchModal`, `renderResults`, `shouldRenderGlobalSection`) | Search owns its results region rather than adding a separate page-level error surface. In All, each category with results or an error gets a `<section>` with an `<h3>` title; empty categories are hidden and "No results found." shows only when none render. A single scope shows "No songs/players/bands found." |

## Rules

- **R1. Keep outcome types distinct.** Loading shows a labelled native progress indicator; no-results shows a centered title and scope-specific subtitle; unavailable/error retains a failure title and reason. Never label a failed read as “No results.”
- **R2. Centre empty states in their actual region.** The shared empty component fills the available viewport/list region, not merely its content height. Search centres below the scope switcher and above lower chrome, with text wrapping or scrolling at large type. When the empty state is an item of a lazy list or grid below page controls (Player Bands' group picker, a board's population line or song header) and above a pager or anchored footer, it takes exactly the visible region those leave, never a fixed-height block, so its text centres on tall phones, tablets and desktop windows too (Android `rememberEmptyRegion` + `fillEmptyRegion`, pure rule `core/shell/EmptyRegion.kt`; #377 review: a 360 dp block sat above centre).
- **R3. Global Search has one result state.** In **All**, each category that has rows or a failure sits under its Songs/Players/Bands section title, in that order (the shared [section-headers](section-headers.md) R1 heading; web `SearchModal` `<h3>`, #348). An empty category is omitted, with no per-category "no results" row; only when every category is empty does All show its one centred empty state. A selected scope has no section title because its chip names it (#299) and shows its own centred empty state. Search shows one centred `Searching` indicator and scope-specific short-query hints. Failed and empty global-search results have no Retry button; submitting the same search or editing it reruns the query (#299).
- **R4. Preserve per-scope copy.** A subtitle says what was searched and what to try next (Bands: "No Bands Found" / "Check the spelling or try a different band member's name.", #320); a failed Bands search says "Bands unavailable", never "No bands found". A platform that has not ported band search yet states why its Bands scope is unavailable. Do not replace these with a generic “Error” message.
- **R5. Use the canonical components.** Apple uses `GlobalSearchEmptyStateView`, `FestivalLoadingView`, `ServiceUnavailableView` or `ComingSoonView`; Android uses `FestivalEmptyState`/`FestivalLoading`; Windows uses `EmptyStateView` (`Festival.App/Controls/EmptyStateView.xaml`, every empty state including Search's `fst.global-search.empty` region; `IsCompact` for in-section empties) and `ServiceStatusView` for failures. Material/Fluent controls remain native rather than imitating web markup.
- **R6. Replace loading completely.** A spinner gives way to rows, an empty state or an error state; it never remains beside stale placeholders (#35, #65).
- **R7. Keep the full-page failure off a separating hinge.** On Android the full-page service status uses the shared hinge side rule of [modal-shell](modal-shell.md) R8 (`HingeSide`, via `serviceStatusHingeSide`): the wider or leading side in book posture, below the hinge in tabletop, so its heading, message and Retry never straddle the fold (#140).
- **R8. Empty states are plain centred text (#377).** Every empty page or region (Songs, Item Shop, Suggestions, Rivals, Player Bands, Bands, Band Rankings, Leaderboards, Notifications, Player History, Statistics, Song Detail, Search) renders through the platform's one shared empty-state component, like web `EmptyState`: optional icon, title and subtitle centred horizontally and vertically in the region, **no background card and no Reset Filters button**. The subtitle names the way out ("Try changing your filters to see more songs."); the filter sheet's or flyout's own Reset is the reset path, as on the web. An `action` is allowed only for gate states that are not query results (Select/Choose Player, Go Back, Retry while a player syncs) and for the corrupt-saved-filter error, which requires explicit Reset (AGENTS.md invariant; an error, not an empty result, R1). Web-faithful in-card section empties (Compete sections, Profile Top Songs/Bands, Song Detail instrument cards) and in-board leaderboard rows ("No scores yet") stay inside their card, as on the web; on Windows these use `EmptyStateView`'s compact variant (`IsCompact`: smaller text, no heading level, no vertical centring). Copy: the web Item Shop has no filters, so "No offers match these filters" has no web counterpart; native filtered Shop copy follows web Songs/Suggestions filtered copy (Android: "No Item Shop songs match your filters." / "Try changing your filters to see more songs."; Windows: "No Matching Songs" / "No Item Shop songs match your filters. Try changing your filters to see more songs."). The unfiltered Shop empty state keeps the web's "No songs in the Item Shop" / "Check back later — the shop updates regularly."

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Centered search empty | `apple/Sources/FestivalUI/Features/Search/GlobalSearchEmptyState.swift` `GlobalSearchEmptyStateView` | `android/app/src/main/java/com/festivalscoretracker/android/ui/search/GlobalSearch.kt` `GlobalSearchEmptyState` | `windows/Festival.App/Pages/SearchPage.xaml` `fst.global-search.empty` |
| Loading indicator | `apple/Sources/FestivalUI/Common/FestivalLoadingView.swift` `FestivalLoadingView` | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/ServiceStatus.kt` `FestivalLoading` | `windows/Festival.App/Pages/SearchPage.xaml` `fst.global-search.loading` |
| Page/region empty (R8) | `apple/Sources/FestivalUI/Features/Search/GlobalSearchEmptyState.swift` `GlobalSearchEmptyStateView` | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/LoadGate.kt` `FestivalEmptyState` (Shop `NoMatchingOffers`/`HiddenView`, Suggestions `Message`, Rivals `RivalsMessage`, Bands `BandEmptyState`, Band Rankings, Notifications, Player History `HistoryMessage`, Player profile `Message`, Songs `festivalEmptyStateItem`; list/grid region sizing `rememberEmptyRegion`/`fillEmptyRegion`, used by Player Bands, Song Band Leaderboard, Band Rankings and Songs) | `windows/Festival.App/Controls/EmptyStateView.xaml` `EmptyStateView` (every page/region empty, including Search's `fst.global-search.empty`; `IsCompact` for in-section empties) |
| Unavailable/placeholder | `apple/Sources/FestivalUI/Common/ServiceStatusViews.swift` `ServiceUnavailableView`; `apple/Sources/FestivalUI/Common/ComingSoonView.swift` `ComingSoonView` | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/LoadGate.kt` `FestivalEmptyState` | `windows/Festival.App/Controls/ServiceStatusView.xaml` `ServiceStatusView` |
| Full-page service status | `apple/Sources/FestivalUI/Common/ServiceStatusViews.swift` `ServiceUnavailableView` | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/ServiceStatus.kt` `ServiceStatusView` (hinge side: `core/nav/HingeSide.kt` `HingeSide`) | `windows/Festival.App/Controls/ServiceStatusView.xaml` `ServiceStatusView` |

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Android Bands "not found" centres its message in the **upper** half in tabletop (`rememberBandTabletopHinge`, [pages/bands/android.md](../pages/bands/android.md), #118), while R7 keeps the full-page status below the hinge. | Two empty/error surfaces pick different tabletop halves; deliberate for Bands (text only, no controls, the lower half holds the bottom bar). | TODO(orchestrator): owner to confirm whether text-only page empty states keep the upper half or follow R7. |

## Guards (tools/pattern_guard.py)

- `empty-error-states/global-search-retry`
- `empty-error-states/windows-empty-reset`
- `empty-error-states/android-empty-reset-filters`
- `empty-error-states/android-empty-fixed-height`
