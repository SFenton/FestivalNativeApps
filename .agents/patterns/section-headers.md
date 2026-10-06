# Section headers

> **What:** section-title hierarchy, card placement, accessibility semantics, and pinned-header handoff. **Read when:** adding a titled group, a grouped list, or a sticky section header.

Status: **current**, 2026-10-06. Provenance: #288, #291, #297, #312, #321.

## Intent

Section titles create stable visual and semantic landmarks. They sit above their content card, remain readable over artwork, and, where pinned, hand off continuously instead of snapping or overlapping.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/components/common/SectionHeader.tsx` (`SectionHeader`) | Renders the shared title and optional description above section content. |
| `FortniteFestivalWeb/src/pages/settings/SettingsPage.tsx` (`SectionHeader`) | Uses ordered headings as page landmarks and Quick Links targets. |
| `FortniteFestivalWeb/src/pages/player/components/PlayerBandsSection.tsx` (`buildPlayerBandsItems`) | A section title with a trailing "See all" action that opens the full list (natives say "View All", #321). |

The web has no sticky section header. Native sticky behavior is an approved addition in R5.

## Rules

1. **R1. Use the canonical heading.** A section title is white, bold/headline, Title Case, leading-aligned, and exposed as a level-two heading; callers supply the already-cased localized title.
2. **R2. Put card headings outside cards.** A titled content card has its title and optional description above, not inside, the row container. HIG Materials: "Don't use Liquid Glass in the content layer." Use the shared material card rather than per-page glass.
3. **R3. Preserve readable hierarchy.** Supporting copy is subordinate to the title and wraps rather than truncating the landmark. HIG Typography: "Adjust weight, size and color as needed to emphasize important information and show hierarchy."
4. **R4. Use native sticky mechanics.** A pinned title stays opaque while rows fade or clip beneath it; an incoming title pushes the pinned title one-for-one and no two titles overlap.
5. **R5. Do not animate the handoff independently.** Geometry follows the scroll gesture in both directions. HIG Accessibility recommends "tracking gestures directly" when Reduce Motion is on.
6. **R6. Keep one accessible title.** The in-list title remains the heading; a visual moving copy is hidden from assistive technology.
7. **R7. Keep native implementations, not a shared fake header.** **Approved variants:** Apple `SongsSectionBar`, Android Compose `stickyHeader`, and the Windows clipped header copy are the #288-approved native implementations; all obey R1-R6.
8. **R8. One View All link per platform.** A section title that opens its full list puts "View All" at the trailing end of the title row, using the platform's shared link, with at least a 44 pt (Apple) or 48 dp (Android) target and a spoken label that starts with "View All" and names the list. The link keeps its own test ID: on Apple, an identified container around it (`DualSourcePane`, Duo Song Detail history cards) sets `.accessibilityElement(children: .contain)` before its identifier (#321). Do not add a second header-link style in a feature folder (#312). The copy is "View All", never "See All" (owner, #321). It stays a link rather than the purple [view-all-cta](view-all-cta.md) button (agent decision, #321, 2026-10-06, view-all-cta R7; owner may override).

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Ordinary section title | `apple/Sources/FestivalUI/Design/SectionHeader.swift` `FestivalSectionHeader` | `android/app/src/main/java/com/festivalscoretracker/android/ui/design/DesignPrimitives.kt` `SectionHeader` | `windows/Festival.App/Themes/Styles.xaml` `FSTSectionHeaderStyle` |
| Titled content card | `apple/Sources/FestivalUI/Design/GlassSection.swift` `FestivalGlassSection` | `android/app/src/main/java/com/festivalscoretracker/android/ui/design/DesignPrimitives.kt` `SectionHeader` | `windows/Festival.App/Controls/CardHeader.cs` `CardHeader` |
| Title-row View All (R8) | `apple/Sources/FestivalUI/Design/SectionHeader.swift` `SectionViewAllLink` (Duo pane headers, Duo Song Detail history cards, Profile Bands) | `android/app/src/main/java/com/festivalscoretracker/android/ui/design/SeeAllButton.kt` `SeeAllButton` | `windows/Festival.App/Pages/RivalsPage.xaml` `HyperlinkButton` |
| Pinned Songs handoff | `apple/Sources/FestivalUI/Features/Songs/SongsScreen.swift` `SongsSectionBar` | `android/app/src/main/java/com/festivalscoretracker/android/ui/songs/SongsScreen.kt` `SongsScreen` | `windows/Festival.App/Pages/SongsPage.xaml` `StickyHeader` |

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Android `SeeAllButton`'s default label (every consumer except Profile Bands, which passes "View All", #312), Windows `RivalsPage`/`RivalDetailPage` links and the web still say "See All" | R8 | Android, Windows and web checks of #321 |

## Guards (`tools/pattern_guard.py`)

- `section-headers/apple-songs-bar`
- `section-headers/android-sticky-header`
- `section-headers/windows-sticky-copy`
- `section-headers/apple-see-all-copy`
