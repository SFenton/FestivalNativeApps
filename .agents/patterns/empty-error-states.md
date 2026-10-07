# Empty and error states

> **What:** loading, no-result, unavailable and placeholder outcomes, including their copy, centring and retry behavior. **Read when:** a query or page can return no content or fail.

Status: **current**, 2026-10-07. Provenance: #35, #65, #99, #140, #299, #320, #348.

## Intent

Every result region communicates whether it is loading, empty or unavailable without turning a failure into a successful empty result. The web supplies the centered-title/subtitle model; native code supplies platform controls and accessibility.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/components/common/EmptyState.tsx` (`EmptyState`, `Layout.shellChromeHeight`) | Optional icon, bold title and subtitle centre in the available region; `fullPage` centres below shell chrome. |
| `FortniteFestivalWeb/src/components/search/SearchModal.tsx` (`SearchModal`) | Search owns its results region rather than adding a separate page-level error surface. |

## Rules

- **R1. Keep outcome types distinct.** Loading shows a labelled native progress indicator; no-results shows a centered title and scope-specific subtitle; unavailable/error retains a failure title and reason. Never label a failed read as “No results.”
- **R2. Centre empty states in their actual region.** The shared empty component fills the available viewport/list region, not merely its content height. Search centres below the scope switcher and above lower chrome, with text wrapping or scrolling at large type.
- **R3. Global Search has one result state.** All titles each shown Songs/Players/Bands section with the canonical [section-headers](section-headers.md) title (web `SearchModal` `h3` per rendered target, #348) and omits an empty category; a single scope has no section title because the scope switcher names it (#299) and shows its own centered no-results state (web `search.noResults.{songs,players,bands}`). It shows one centered `Searching` indicator and provides scope-specific short-query hints. Failed and empty global-search results have no Retry button; submitting the same search or editing it reruns the query (#299).
- **R4. Preserve per-scope copy.** A subtitle says what was searched and what to try next (Bands: "No Bands Found" / "Check the spelling or try a different band member's name.", #320); a failed Bands search says "Bands unavailable", never "No bands found". A platform that has not ported band search yet states why its Bands scope is unavailable. Do not replace these with a generic “Error” message.
- **R5. Use the canonical components.** Apple uses `GlobalSearchEmptyStateView`, `FestivalLoadingView`, `ServiceUnavailableView` or `ComingSoonView`; Android uses `FestivalEmptyState`/`FestivalLoading`; Windows uses the centered Search page state and `ServiceStatusView`. Material/Fluent controls remain native rather than imitating web markup.
- **R6. Replace loading completely.** A spinner gives way to rows, an empty state or an error state; it never remains beside stale placeholders (#35, #65).
- **R7. Keep the full-page failure off a separating hinge.** On Android the full-page service status uses the shared hinge side rule of [modal-shell](modal-shell.md) R8 (`HingeSide`, via `serviceStatusHingeSide`): the wider or leading side in book posture, below the hinge in tabletop, so its heading, message and Retry never straddle the fold (#140).

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Centered search empty | `apple/Sources/FestivalUI/Features/Search/GlobalSearchEmptyState.swift` `GlobalSearchEmptyStateView` | `android/app/src/main/java/com/festivalscoretracker/android/ui/search/GlobalSearch.kt` `GlobalSearchEmptyState` | `windows/Festival.App/Pages/SearchPage.xaml` `fst.global-search.empty` |
| Loading indicator | `apple/Sources/FestivalUI/Common/FestivalLoadingView.swift` `FestivalLoadingView` | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/ServiceStatus.kt` `FestivalLoading` | `windows/Festival.App/Pages/SearchPage.xaml` `fst.global-search.loading` |
| Unavailable/placeholder | `apple/Sources/FestivalUI/Common/ServiceStatusViews.swift` `ServiceUnavailableView`; `apple/Sources/FestivalUI/Common/ComingSoonView.swift` `ComingSoonView` | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/LoadGate.kt` `FestivalEmptyState` | `windows/Festival.App/Controls/ServiceStatusView.xaml` `ServiceStatusView` |
| Full-page service status | `apple/Sources/FestivalUI/Common/ServiceStatusViews.swift` `ServiceUnavailableView` | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/ServiceStatus.kt` `ServiceStatusView` (hinge side: `core/nav/HingeSide.kt` `HingeSide`) | `windows/Festival.App/Controls/ServiceStatusView.xaml` `ServiceStatusView` |

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Android Bands "not found" centres its message in the **upper** half in tabletop (`rememberBandTabletopHinge`, [pages/bands/android.md](../pages/bands/android.md), #118), while R7 keeps the full-page status below the hinge. | Two empty/error surfaces pick different tabletop halves; deliberate for Bands (text only, no controls, the lower half holds the bottom bar). | TODO(orchestrator): owner to confirm whether text-only page empty states keep the upper half or follow R7. |

## Guards (tools/pattern_guard.py)

- `empty-error-states/global-search-retry`
