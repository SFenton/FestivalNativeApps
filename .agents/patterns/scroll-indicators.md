# Scroll indicators: system bars on every page

> **What:** whether a scroll view shows its scroll indicator (scroll bar): every page and sheet uses the platform's own indicators, and the app has no setting for them. **Read when:** you add or change a scroll view, hide or show an indicator, or someone asks for a "show scroll bars" option.

Status: **current**, 2026-10-07. Provenance: #356 (split from #332; agent decision below), #279 (Windows Paths chart), Apple Paths `.hidden` precedent ([chopt-paths/macos.md](../controls/chopt-paths/macos.md)).

## Intent

People see the scroll position the same way they do in every other app on their device. The indicator appears while a page scrolls and follows the system's own scroll-bar preference; the app never adds its own switch for it or draws its own bar.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/index.css` (`* { scrollbar-width: none; }`, `::-webkit-scrollbar { display: none; }`) | The web hides every browser scroll bar and offers no setting for them. Natives do **not** copy this: scroll indicators are system chrome, and native chrome beats web chrome ([consistency-sweep](../skills/consistency-sweep/SKILL.md#precedence-when-the-rungs-disagree)) |

## Rules

- **R1. Every page uses the system indicators.** Vertical page and sheet scroll views (`ScrollView`, `List`, `Form`, lazy lists, boards) keep the platform default: Apple SwiftUI `.automatic` (shown while scrolling, hidden at rest on iOS/iPadOS; on macOS System Settings › Appearance › Show scroll bars decides). Never hide a page's vertical indicator, never set it to `.never`, and never draw a custom indicator. HIG Scroll views: the indicator "typically appears once scrolling begins"; "Custom scrolling needs elastic scroll indicators" (should).
- **R2. No in-app scroll-bar setting.** Settings has no "Always Show Scroll Bars" (or similar) toggle. HIG Settings: "Honor systemwide settings. Don't duplicate global accessibility, scrolling, or authentication options; duplicates imply system choices may not apply or the custom change affects other apps." (should). iOS/iPadOS has no persistent-indicator API, so such a toggle could only fake the system bar.
- **R3. Allowed exceptions hide with `.hidden`, never `.never`.** Only these scroll views hide their indicator: horizontal paged carousels that show their own page dots (HIG Scroll views, iOS/iPadOS: "don't show the scroll indicator on the same axis as the page control"), including each carousel card's inner scroll; the horizontal feedback attachment strip; and the zoomable Paths chart image ([chopt-paths](../controls/chopt-paths/spec.md)). `.hidden` still yields to macOS "Always" show scroll bars, so a mouse user can always reach a bar. A new exception needs a documented decision and a guard `allow` entry.
- **R4. Make scrollability apparent without the bar.** Because indicators are not always visible, pages show partial content at the edge (the [scroll-edge](scroll-edge.md) ramps and cut-off rows) instead of forcing bars on. HIG Scroll views: "Make scrollable content apparent, since indicators aren't always visible" (should).

**Agent decision (#356, 2026-10-07; the owner may override with `/choose`).** The owner asked whether page scroll bars should become an accessibility toggle. Options weighed: A, the system default with no setting (chosen); B, an in-app "Always Show Scroll Bars" toggle (rejected: duplicates a system scrolling preference against the HIG Settings *should*, is not an accessibility feature on any Apple platform, and on iOS/iPadOS would need a custom-drawn bar on every page because the system indicator always fades); C, hide indicators everywhere like the web (rejected: removes the only position cue on long lists; native chrome beats web chrome). Answer to "is it accessibility?": no, it is a system scrolling preference (macOS Appearance settings; none on iOS/iPadOS).

## Canonical implementation

| Sub-behavior | Apple (`apple/Sources/…`) | Android | Windows |
|---|---|---|---|
| Page indicators (R1) | SwiftUI default; no modifier on page scroll views | Platform default (not audited for #356) | Platform default `ScrollViewer` conscious indicators (not audited for #356) |
| Carousel exception (R3) | `FestivalUI/Common/HorizontalCarousel.swift` `HorizontalCarousel` (`.scrollIndicators(.hidden)` on the strip and each card) | — | — |
| Other exceptions (R3) | `FestivalUI/Features/Settings/Feedback/FeedbackAttachmentStrip.swift`, `FestivalUI/Features/SongDetail/SongPathsSheet.swift` image viewport | — | Paths chart `ImageScroller` ([chopt-paths/windows.md](../controls/chopt-paths/windows.md)) |

`TODO(orchestrator)`: Android and Windows were out of #356's Apple scope; confirm their page lists keep the platform default and have no in-app toggle, then register their exceptions here.

## Known debt

None on Apple.

## Guards (`tools/pattern_guard.py`)

- `scroll-indicators/apple-hidden`: `.scrollIndicators(.hidden|.never)` or `showsIndicators: false` in Apple sources outside the R3 exceptions.
