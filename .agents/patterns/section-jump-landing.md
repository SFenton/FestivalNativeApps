# Section-jump landing

> **What:** where a Quick Links or Songs index jump places a section and how that section becomes current. **Read when:** adding a section jump, changing a scroll anchor, or changing the active-section line.

Status: **current**, 2026-10-07. Provenance: #9, #286, #298, #336, #415.
Status: **current**, 2026-10-07. Provenance: #9, #286, #298, #336, #393.

## Intent

A jump names and exposes its destination immediately. A normal section lands below obscuring chrome; a pinned Songs title lands exactly where it pins, with its first row clear of the fade.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/hooks/ui/usePageQuickLinks.ts` (`DEFAULT_QUICK_LINK_SCROLL_OFFSET = 32`, `DEFAULT_SONGS_SCROLL_OFFSET = 16`) | Computes the compact jump target, natural active item, and jump ownership. |
| `FortniteFestivalWeb/src/pages/songs/SongsPage.tsx` (`usePageQuickLinks`) | Supplies the Songs virtualizer's section targets and active item. |

The web has no drag section index. Native indexes reuse its section order and active-section contract.

## Rules

1. **R1. Share the landing policy.** Quick Links, a Songs index, and any programmatic section jump use the platform quick-links/section-header helper, never page-local offset arithmetic.
2. **R2. Land ordinary sections 32 units below chrome.** The target heading and active line use the same 32 pt/dp/epx offset; clamp near either content end and retain the visible target as current. HIG Layout: "Respect [the safe area] so system UI and hardware do not cover controls/content."
3. **R3. Land pinned Songs titles at their pin line.** Apple `landingOffset` is zero; the title coincides with its pinned copy and the first row is unfaded (#298). Do not restore the superseded 30 pt workaround.
4. **R4. Re-settle lazy targets.** Correct an estimated or newly realized target without changing sort, filters, selected profile, or triggering a read. Re-tapping a current index item still jumps.
5. **R5. Make target ownership explicit.** Select the target when the jump begins; hand back to natural tracking only after it leaves the landing/reachable band. Near-end targets remain current while visible.
6. **R6. Keep the target perceivable.** The active link/index value names the landed section, and the heading remains an accessibility heading. Do not use fading to create clearance. Windows evidence: `tools/windows/journeys/a11y-section-index.json` `index-backward-after-scroll` and `-keyboard` (pinned title names B, reads "B, text", stays a Level 2 heading after a backward pick), run by the `windows-ui` CI workflow (`tools/windows/ui_ci.py` `RUNS`) at compact and medium, 100% and 225% text (#415). A Windows jump also moves keyboard focus into the landed section, and it does that only once the section's controls exist: a virtualizing list far below the viewport realizes them only after the scroll, so `QuickLinksBinder` retries after layout passes (#431, `qla-settings-menu` at 225% text).
5. **R5. Make target ownership explicit.** Select the target when the jump begins; hand back to natural tracking only after it leaves the landing/reachable band. Near-end targets remain current while visible. The newest jump owns correction and settling: an earlier jump's pending correction stops without scrolling or settling once another jump begins, so a held Next Section shortcut or a quick rotor flick ends on its last target (#393: the stale pass re-landed its old target and Quick Links named a section off screen).
6. **R6. Keep the target perceivable.** The active link/index value names the landed section, and the heading remains an accessibility heading. Do not use fading to create clearance.
7. **R7. Keep platform-native jump controls.** **Approved variants:** Apple uses `ListScrollNudger` for `List`; Android uses Compose `stickyHeader`; Windows uses `SemanticZoom` and `SongSectionHeader.JumpPinDelta` (#288). These vary presentation, not R1-R6.
8. **R8. Fit the index to its region.** A drag section index is never taller than the height it is offered and never makes the page taller than its window; where every label does not fit, it keeps the first and last labels, evenly spaced ones between them and a bullet for each skipped run (the system table index's condensed form). A label lands on its own section, a drag still passes every section and the adjustable action still steps one at a time (#336: the rigid 27-label Apple strip pushed Duo outer-landscape Songs past the window, under the title and with the Filter field offscreen). HIG Designing for iPhone Duo: "The outer display is wider and shorter than other iPhone displays"; "avoid fixed widths or display-specific dependencies".

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Landing and active line | `apple/Sources/FestivalCore/QuickLinks.swift` `QuickLinks` | `android/app/src/main/java/com/festivalscoretracker/android/core/quicklinks/QuickLinks.kt` `QuickLinks` | `windows/Festival.Core/Domain/QuickLinks.cs` `QuickLinks` |
| Lazy/List correction | `apple/Sources/FestivalUI/Common/ListScrollNudger.swift` `ListScrollNudger` | `android/app/src/main/java/com/festivalscoretracker/android/ui/quicklinks/QuickLinksUi.kt` `QuickLinksController` | `windows/Festival.App/Controls/QuickLinksBinder.cs` `QuickLinksBinder` |
| Songs index fit (R8) | `apple/Sources/FestivalUI/Features/Songs/SongSectionIndexScrubber.swift` `SongSectionIndexScrubber` | Not present (no drag index) | Not present (`SemanticZoom`) |
| Songs pinned landing | `apple/Sources/FestivalUI/Features/Songs/SongsScrollChrome.swift` `SongsScrollChrome` | `android/app/src/main/java/com/festivalscoretracker/android/ui/songs/SongsScreen.kt` `SongsScreen` | `windows/Festival.Core/Domain/SongSectionHeader.cs` `SongSectionHeader` |

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| None confirmed | — | — |

## Guards (`tools/pattern_guard.py`)

- `section-jump-landing/apple-list-nudger`
- `section-jump-landing/android-lazy-offset`
- `section-jump-landing/windows-jump-pin`
