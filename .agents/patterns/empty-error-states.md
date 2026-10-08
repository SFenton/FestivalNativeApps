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
- **R2. Centre empty states in their actual region.** The shared empty component fills the available viewport/list region, not merely its content height. Search centres below the scope switcher and above lower chrome, with text wrapping or scrolling at large type.
- **R3. Global Search has one result state.** In **All**, each category that has rows or a failure sits under its Songs/Players/Bands section title, in that order (the shared [section-headers](section-headers.md) R1 heading; web `SearchModal` `<h3>`, #348). An empty category is omitted, with no per-category "no results" row; only when every category is empty does All show its one centred empty state. A selected scope has no section title because its chip names it (#299) and shows its own centred empty state. Search shows one centred `Searching` indicator and scope-specific short-query hints. Failed and empty global-search results have no Retry button; submitting the same search or editing it reruns the query (#299).
- **R4. Preserve per-scope copy.** A subtitle says what was searched and what to try next (Bands: "No Bands Found" / "Check the spelling or try a different band member's name.", #320); a failed Bands search says "Bands unavailable", never "No bands found". A platform that has not ported band search yet states why its Bands scope is unavailable. Do not replace these with a generic “Error” message.
- **R5. Use the canonical components.** Apple uses `GlobalSearchEmptyStateView`, `FestivalLoadingView`, `ServiceUnavailableView` or `ComingSoonView`; Android uses `FestivalEmptyState`/`FestivalLoading`; Windows uses `EmptyStateView` (`Festival.App/Controls/EmptyStateView.xaml`, every empty state including Search's `fst.global-search.empty` region; `IsCompact` for in-section empties) and `ServiceStatusView` for failures. Material/Fluent controls remain native rather than imitating web markup.
- **R6. Replace loading completely.** A spinner gives way to rows, an empty state or an error state; it never remains beside stale placeholders (#35, #65).
- **R7. Keep the full-page failure off a separating hinge.** On Android the full-page service status uses the shared hinge side rule of [modal-shell](modal-shell.md) R8 (`HingeSide`, via `serviceStatusHingeSide`): the wider or leading side in book posture, below the hinge in tabletop, so its heading, message and Retry never straddle the fold (#140).
- **R8. Every empty state is the one shared empty-state component: centred text, no card, no Reset button (#377).** Every empty page or region (Songs, Item Shop, Suggestions, Rivals, Player Bands, Bands, Leaderboards, Notifications, Player History, Song Detail, Search) uses the platform's shared component, modelled on the web `EmptyState`. It has an optional icon, a title and a subtitle, centred horizontally and vertically in its region, with no background card or border. A filtered-empty state never carries Reset/Clear Filters: filters reset from the filter control that set them (sheet or flyout Reset), as on the web. An action appears only when it is the next step for that state (Select Player, Retry while scores sync). The Songs invalid-saved-filter state keeps its explicit Reset, because AGENTS.md requires it; it is a blocked state, not an empty result. An empty state inside a page section (for example, a profile or band section under its own header) uses the compact variant: smaller text, no heading level and no vertical centring. Copy follows the web `EmptyState` model: a short title-case title and a subtitle saying what to try. The web Item Shop has no filters, so the native filtered-empty Shop copy ("No Matching Songs" / "No Item Shop songs match your filters. Try changing your filters to see more songs.") follows the web Songs filtered-empty copy; the unfiltered Shop empty state keeps the web's "No songs in the Item Shop" / "Check back later — the shop updates regularly."

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Centered search empty | `apple/Sources/FestivalUI/Features/Search/GlobalSearchEmptyState.swift` `GlobalSearchEmptyStateView` | `android/app/src/main/java/com/festivalscoretracker/android/ui/search/GlobalSearch.kt` `GlobalSearchEmptyState` | `windows/Festival.App/Pages/SearchPage.xaml` `fst.global-search.empty` |
| Shared page/region empty state (R8) | `apple/Sources/FestivalUI/Features/Search/GlobalSearchEmptyState.swift` `GlobalSearchEmptyStateView` | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/LoadGate.kt` `FestivalEmptyState` | `windows/Festival.App/Controls/EmptyStateView.xaml` `EmptyStateView` |
| Loading indicator | `apple/Sources/FestivalUI/Common/FestivalLoadingView.swift` `FestivalLoadingView` | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/ServiceStatus.kt` `FestivalLoading` | `windows/Festival.App/Pages/SearchPage.xaml` `fst.global-search.loading` |
| Unavailable/placeholder | `apple/Sources/FestivalUI/Common/ServiceStatusViews.swift` `ServiceUnavailableView`; `apple/Sources/FestivalUI/Common/ComingSoonView.swift` `ComingSoonView` | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/LoadGate.kt` `FestivalEmptyState` | `windows/Festival.App/Controls/ServiceStatusView.xaml` `ServiceStatusView` |
| Full-page service status | `apple/Sources/FestivalUI/Common/ServiceStatusViews.swift` `ServiceUnavailableView` | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/ServiceStatus.kt` `ServiceStatusView` (hinge side: `core/nav/HingeSide.kt` `HingeSide`) | `windows/Festival.App/Controls/ServiceStatusView.xaml` `ServiceStatusView` |

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Android Bands "not found" centres its message in the **upper** half in tabletop (`rememberBandTabletopHinge`, [pages/bands/android.md](../pages/bands/android.md), #118), while R7 keeps the full-page status below the hinge. | Two empty/error surfaces pick different tabletop halves; deliberate for Bands (text only, no controls, the lower half holds the bottom bar). | TODO(orchestrator): owner to confirm whether text-only page empty states keep the upper half or follow R7. |

## Guards (tools/pattern_guard.py)

- `empty-error-states/global-search-retry`
- `empty-error-states/windows-empty-reset`
