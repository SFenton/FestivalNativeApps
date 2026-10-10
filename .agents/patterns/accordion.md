# Accordion

> **What:** every in-place expand/collapse: filter-sheet disclosure groups, a switch that reveals a block under it, a selector that opens a panel of options, Settings choice rows. Owns the open/close motion, its timing, interruption, Reduce Motion and the VoiceOver state. **Read when:** adding or changing anything that expands or collapses content in place.

Status: **current**, 2026-10-09. Provenance: #20, #561 (owner-approved variant of [load-transition](load-transition.md)).

## Intent

An accordion should read as one deliberate motion, never a snap. The owner's ask (#561): "Accordion animated open then content fades in; when closing, content fades out then accordion collapses. This should happen anywhere there's an accordion style element in the app." The space moves first and the content fades into it, so nothing draws over rows that are still moving.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/components/common/Accordion.tsx` (`Accordion`) | Shared by the Songs Filter/Sort, Suggestions Filter and Paths modals; animates `grid-template-rows` over `QUICK_FADE_MS` (150 ms), height only. |
| `FortniteFestivalWeb/src/components/page/CollapseOnExit.tsx` (`CollapseOnExit`) | Fade out, then collapse (300 ms): the closing half of this sequence. |
| `FortniteFestivalWeb/packages/theme/src/animation.ts` (`QUICK_FADE_MS`) | 150 ms. |

**Owner-approved variant (#561).** The web accordion animates height only. The native apps add the sequenced content fade the owner asked for; the timings stay the web's. The base [load-transition](load-transition.md) rules still apply to loads and reloads; this pattern applies only to in-place expand/collapse.

## Rules

1. **R1. Open, then fade in; fade out, then close.** Opening grows the container (150 ms ease-in-out) with its content laid out but transparent, then fades the content in (150 ms). Closing fades the content out (150 ms), then collapses the container (150 ms). Each half uses web `QUICK_FADE_MS`; the close totals the web `CollapseOnExit` 300 ms. Owner, #561.
2. **R2. Interruptible.** A new tap or value change cancels the pending step and plans from where the motion is: reopening during the fade-out only fades back in, closing before the fade-in finished collapses at once. Nobody waits for an animation (HIG Motion: "let people cancel animations rather than wait for completion", **should**). Swapping the value while open (another instrument chosen) swaps the content in place without collapsing.
3. **R3. Reduce Motion keeps only the fade.** Under the system or the app's own Reduce Motion (`fst.accessibility.reduceMotion`), the container opens and closes without animation and the content fade remains (HIG Accessibility: "replacing axis transitions with fades", **should**; HIG Motion: "Make motion optional", **should**).
4. **R4. Accessibility state is immediate; hidden content is hidden.** The disclosure state VoiceOver reports (Expanded/Collapsed, or the header value on Settings choice rows, [settings ios](../pages/settings/ios.md)) follows the request at once, not the animation. Content that is laid out but not yet faded in, or fading out, is hidden from VoiceOver and receives no touches.
5. **R5. Native control, one component.** Apple keeps the system `DisclosureGroup` (HIG Disclosure controls: iOS and iPadOS "provide disclosure controls through SwiftUI `DisclosureGroup`") through `FestivalDisclosureGroup`. A switch-, selector- or value-driven reveal uses `FestivalAccordionState` + `.festivalAccordion(_:follows:)` on a view that is always present (the switch, the selector, the `Form`), never on the revealed content, and shows the content with `FestivalAccordionContent`. No raw `DisclosureGroup`, binding `.animation(…)` or local `.transition` for an expand/collapse.
6. **R6. Not this pattern.** Page, board and modal loads ([load-transition](load-transition.md)), a "View all" that navigates ([view-all-cta](view-all-cta.md) R8), list/detail pane swaps ([split-panes](split-panes.md)) and selector-driven graph swaps (load-transition R7/R8) are not accordions. The Mac Settings window's choice rows are pop-up buttons, not disclosures, so they have no accordion motion.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Sequence and timing (R1–R3) | `apple/Sources/FestivalUI/Design/FestivalAccordion.swift` `AccordionChoreography` (`plan`, `animation`, `run`) | `android/app/src/main/java/com/festivalscoretracker/android/ui/songs/SongsSheets.kt` `Accordion` (debt below) | WinUI `Expander` (debt below) |
| Disclosure group (R4, R5) | `FestivalDisclosureGroup` (system `DisclosureGroup`) | — | — |
| Value- or switch-driven reveal (R5) | `FestivalAccordionState`, `View.festivalAccordion(_:follows:)`, `FestivalAccordionContent` | — | — |

Apple consumers: Songs Filter (`SongsFilterSheet`: Year, Duration, Item Shop, Double Bass, Season, Percentile, Stars, Intensity, the per-instrument Individual charts groups, the Player Scores sections that open with "Player Score and FC Filters", the bucket sections that open with a chart, and the Select All / Clear All header shown while a bucket is open), Suggestions Filter Instrument-Specific (`SuggestionsFilterSheet`, also the First Run demo that shows the real sheet), Settings (`SettingsChoiceRow`; the Song Row Visual Order block under its switch and the Maximum Score Leeway block under Filter Invalid Scores in `SettingsScreen`) and the `InstrumentSelector` panel. Shared code covers iPhone, iPad, iPhone Duo and macOS.

Tests: `FestivalAccordionTests` (plan, phases, interruption, Reduce Motion, hidden-until-faded accessibility, driven sequence order), `SuggestionsJourneyTests.testSuggestionsFilterInstrumentSelectorRevealsPerInstrumentToggles` (reveal, hittable 44 pt switches, collapse on deselect).

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Android `Accordion` (Songs Filter/Sort) and `InstrumentSelector` panel use `expandVertically() + fadeIn()` / `shrinkVertically() + fadeOut()` together, not in sequence | R1 | Android check of #561 |
| Windows `Expander`s (Songs, Suggestions, Settings, Song Paths) use WinUI's built-in expand animation without the sequenced fade | R1 | Windows check of #561 |

## Guards (`tools/pattern_guard.py`)

- `accordion/apple-raw-disclosure-group`
