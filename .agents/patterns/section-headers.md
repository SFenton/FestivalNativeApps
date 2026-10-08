# Section headers

> **What:** section-title hierarchy, card placement, accessibility semantics, and pinned-header handoff. **Read when:** adding a titled group, a grouped list, or a sticky section header.

Status: **current**, 2026-10-07. Provenance: #288, #291, #297, #312, #321, #343, #348.

## Intent

Section titles create stable visual and semantic landmarks. They sit above their content card, remain readable over artwork, and, where pinned, hand off continuously instead of snapping or overlapping.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/components/common/SectionHeader.tsx` (`SectionHeader`) | Renders the shared title and optional description above section content. |
| `FortniteFestivalWeb/src/pages/settings/SettingsPage.tsx` (`SectionHeader`) | Uses ordered headings as page landmarks and Quick Links targets. |
| `FortniteFestivalWeb/src/pages/player/components/PlayerBandsSection.tsx` (`buildPlayerBandsItems`) | A section title with a trailing "View All" action (`common.viewAll`; "See all" before #321) that opens the full list. |
| `FortniteFestivalWeb/src/components/search/SearchModal.tsx` (`renderResults`) | In the All scope, each rendered category (Songs, Players, Bands) is a `<section>` labelled by an `<h3>` title; a single scope has none (R9). |

The web has no sticky section header. Native sticky behavior is an approved addition in R5.

## Rules

1. **R1. Use the canonical heading.** A section title is white, bold/headline, Title Case, leading-aligned, and exposed as a level-two heading; callers supply the already-cased localized title. Global Search's All-scope Songs/Players/Bands titles are consumers too (R9, #348).
2. **R2. Put card headings outside cards.** A titled content card has its title and optional description above, not inside, the row container. HIG Materials: "Don't use Liquid Glass in the content layer." Use the shared material card rather than per-page glass.
3. **R3. Preserve readable hierarchy.** Supporting copy is subordinate to the title and wraps rather than truncating the landmark. HIG Typography: "Adjust weight, size and color as needed to emphasize important information and show hierarchy."
4. **R4. Use native sticky mechanics.** A pinned title stays opaque while rows fade or clip beneath it; an incoming title pushes the pinned title one-for-one and no two titles overlap.
5. **R5. Do not animate the handoff independently.** Geometry follows the scroll gesture in both directions. HIG Accessibility recommends "tracking gestures directly" when Reduce Motion is on.
6. **R6. Keep one accessible title.** The in-list title remains the heading; a visual moving copy is hidden from assistive technology. Apple's `SongsSectionBar` also exposes its pinned current title as one heading before the list (`fst.songs.section-bar`, so rail and Quick Links jumps name the section after the List recycles the in-list row); its pushed-out and incoming copies stay hidden (`SongsSectionBarAccessibilityTests`, #391). A section with no title (one unlabeled section, e.g. a player metric sort or a lone Item Shop bucket) exposes no empty heading or group and takes no focus stop (Windows `SongsPage.ApplyGroupHeaderAccess`, #282: WinUI otherwise makes the group header a focusable, unnamed Group that Up from the first row lands on; guarded by the `"scan": true` Axe + focus-sequence pages in `a11y-songs-bucket-headers.json`).
7. **R7. Keep native implementations, not a shared fake header.** **Approved variants:** Apple `SongsSectionBar`, Android Compose `stickyHeader`, and the Windows clipped header copy are the #288-approved native implementations; all obey R1-R6.
8. **R8. One View All link per platform.** A section title that opens its full list puts "View All" at the trailing end of the title row, using the platform's shared link, with at least a 44 pt (Apple) or 48 dp (Android) target and a spoken label that starts with "View All" and names the list. The link keeps its own test ID: on Apple, an identified container around it (`DualSourcePane`, Duo Song Detail history cards) sets `.accessibilityElement(children: .contain)` before its identifier (#321). Do not add a second header-link style in a feature folder (#312). The copy is "View All", never "See All" (owner, #321). It stays a link rather than the purple [view-all-cta](view-all-cta.md) button (agent decision, #321, 2026-10-06, view-all-cta R7 and the Android record below; owner may override).
9. **R9. Global Search titles its categories only in All.** In the All scope, each category that renders (rows or a failure) has its Songs / Players / Bands title above its rows, in that order, so mixed results stay distinguishable (web `SearchModal` `<h3>`, owner #348). A selected scope has no title because its chip names it (#299). Empty categories and their titles are omitted ([empty-error-states](empty-error-states.md) R3). The title is the platform's ordinary R1 heading (`fst.global-search.section.{songs,players,bands}`), not the web's small uppercase muted label (agent decision, #348, 2026-10-07: R1 is the registered native section-title style and keeps the heading readable at large text sizes; owner may override).
10. **R10. Keep titles on their side of a fold.** When a two-column layout splits at a separating vertical hinge (book posture half-open), a full-width page or section title, subtitle or message stays in the leading pane and wraps there; it never runs across the fold. Unfolding flat reflows it to the full line without reloading. Material 3: "Never place interactive content or critical information across the hinge area." (must). Android: every full-line item in a hinge-splitting staggered grid is a `foldLaneItem`; the grid provides the pane width through `ProvideFoldLane`. A list of hinge-split rows (Leaderboards `CardGridRow`) provides the leading card's width and wraps its full-width header in `FoldLane` (#343). Apple: `FestivalSectionHeader` applies `staysOnHingeSide()`, so every titled card gets it and callers add nothing; it wraps before the fold ([hinge-columns](hinge-columns.md) R3, #343). HIG Designing for iPhone Duo: "use reserved-region APIs to keep important elements clear of the center" (should).

## Agent decision (#321, 2026-10-06): rename title-row links, purple CTA only for in-card bottom rows

Question: the owner asked that Rivals' "See All" match "other 'View All' buttons … a consistent purple button" and that the app say "View All" everywhere. Does that replace title-row links (R8) with the purple CTA, or only rename them?

| Option | What you see | Guidance (strength) | Web / pattern precedent | Trade-offs |
|---|---|---|---|---|
| **A (chosen)** | Title-row links stay the shared trailing link, now "View All ›" (spoken "View All: <section>"). Only in-card bottom "See All" rows (Apple and iPhone Duo Rival Detail) become the purple CTA. Android and web Rival Detail have no bottom row, so they keep the header link. Windows Rival Detail had an in-card bottom text link and no header link, so its Windows check (#321) made that row the purple CTA. | M3 Text Button: "Lowest emphasis. Inline actions … less important options" (should). M3 Filled Button: "Primary action, highest emphasis" (should). M3 button a11y: "Minimum touch target 48x48dp" (must; `SeeAllButton` already meets it). WCAG 2.5.3 Label in Name: the spoken label starts with the visible "View All" (must). | Web `RivalsPage.tsx` and `RivalDetailPage.tsx` (web master `35fb548`): each card header is a clickable title row with `common.viewAll` ("View All") and `IoChevronForward`. The hub adds `viewAllButton` (`rivals.viewAllRivals`) below the rows; Rival Detail has no bottom button. Android `SeeAllButton` is the one shared title-row link (#312); [view-all-cta](view-all-cta.md) R6 already treats title-row links as not the CTA. | Least churn. The hub keeps one purple button per card, not two. |
| B | Every title-row link becomes a full-width purple CTA below the rows, so Rival Detail cards look the same on every platform. | M3 Filled Button "highest emphasis" (should): Rival Detail would show up to six, and each hub card two (the header link and View All Rivals) opening the same list. | No web precedent: the web keeps the header link on both pages. | Diverges from web semantics and from R8. Adds high-emphasis buttons where the web uses a link. |

Chose **A**. Precedence: web behavior beats undocumented native copies, and among tied options prefer the existing pattern. The owner's explicit choice (the purple button for Rivals' in-card "See All") is honoured where that control exists (Apple Rival Detail bottom rows). The copy pass ("View All", never "See All") applies to every platform. Owner may override with `/choose B`.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Ordinary section title | `apple/Sources/FestivalUI/Design/SectionHeader.swift` `FestivalSectionHeader` (Global Search All sections, R9: `Features/Search/GlobalSearchView.swift` `sectionTitle`) | `android/app/src/main/java/com/festivalscoretracker/android/ui/design/DesignPrimitives.kt` `SectionHeader` (Global Search All sections, R9: `ui/search/GlobalSearch.kt` `sectionTitle`) | `windows/Festival.App/Themes/Styles.xaml` `FSTSectionHeaderStyle` |
| Ordinary section title | `apple/Sources/FestivalUI/Design/SectionHeader.swift` `FestivalSectionHeader` | `android/app/src/main/java/com/festivalscoretracker/android/ui/design/DesignPrimitives.kt` `SectionHeader` (Global Search All sections, R9: `ui/search/GlobalSearch.kt` `sectionTitle`) | `windows/Festival.App/Themes/Styles.xaml` `FSTSectionHeaderStyle` (Global Search All sections, R9: `Pages/SearchPage.xaml` `SongsHeading` / `PlayersHeading` / `BandsHeading`) |
| Titled content card | `apple/Sources/FestivalUI/Design/GlassSection.swift` `FestivalGlassSection` | `android/app/src/main/java/com/festivalscoretracker/android/ui/design/DesignPrimitives.kt` `SectionHeader` | `windows/Festival.App/Controls/CardHeader.cs` `CardHeader` |
| Title-row View All (R8) | `apple/Sources/FestivalUI/Design/SectionHeader.swift` `SectionViewAllLink` (Duo pane headers, Duo Song Detail history cards, Profile Bands) | `android/app/src/main/java/com/festivalscoretracker/android/ui/design/SeeAllButton.kt` `SeeAllButton` | `windows/Festival.App/Pages/RivalsPage.xaml` `HyperlinkButton` (also Profile Bands, `Controls/PlayerProfileView.xaml`); copy and label-first name from `windows/Festival.Core/Domain/ViewAllCta.cs` `ListLabel` / `Name` |
| Title in a fold-split grid (R10) | `apple/Sources/FestivalUI/App/Layout/HingeColumns.swift` `staysOnHingeSide()` (applied by `FestivalSectionHeader`) | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/FoldLane.kt` `foldLaneItem` / `FoldLane` (provided by `AdaptiveCardGrid`, Suggestions, Item Shop; Leaderboards `OverviewList` for its Bands header) | — |
| Pinned Songs handoff | `apple/Sources/FestivalUI/Features/Songs/SongsScreen.swift` `SongsSectionBar` | `android/app/src/main/java/com/festivalscoretracker/android/ui/songs/SongsScreen.kt` `SongsScreen` | `windows/Festival.App/Pages/SongsPage.xaml` `StickyHeader` |

## Known debt

| Debt | Breaks | Plan |
|---|---|---|

## Guards (`tools/pattern_guard.py`)

- `section-headers/apple-songs-bar`
- `section-headers/android-sticky-header`
- `section-headers/android-view-all-copy`
- `section-headers/android-fold-lane`
- `section-headers/windows-sticky-copy`
- `section-headers/apple-see-all-copy`
- `section-headers/windows-view-all-copy`
