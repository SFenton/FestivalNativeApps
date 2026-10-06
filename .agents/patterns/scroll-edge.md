# Scroll edge: content under pinned chrome

> **What:** how scrolling content meets anything pinned above or below it: page headers, sheet headers, pinned section titles and bottom chrome (pagers, footers). **Read when:** you touch a fade, mask, scrim, scroll-edge effect or sticky header on any platform, or a bug says content "shows under", "is faded under" or "is cut off at" a header.

Status: **current**, 2026-10-05. Provenance: #10, #49, #93, #94, #286, #288, #297, #298, #301, #305, #306 (audit 2026-10-05: six parallel mechanisms grew up for this one behavior), #308 (Apple consolidated to one component per edge kind; all three Apple edge fades read the scroll position on every supported system).

## Intent

Chrome never sits on half-visible content. Content scrolling toward a pinned edge is completely gone **at** that edge and fades back in over a short ramp **away from** it. Nothing is drawn behind header text. At rest nothing is dimmed. The web defines the behavior; platforms only choose how to draw it.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/hooks/ui/useScrollMask.ts` (`DEFAULT_SIZE = 40`) | Linear CSS mask: transparent at the viewport/header edge, opaque 40 px inside it. No top mask while at the top (`atTop`), no bottom mask at the bottom. Used by `pages/Page.tsx`, `components/modals/Modal.tsx` (`selfScroll`), `ChangelogModal.tsx`, `search/SearchModal.tsx`, `page/PageQuickLinks.tsx`, `settings/LicensesPage.tsx` |
| `FortniteFestivalWeb/src/hooks/ui/useScrollFade.ts` (`DEFAULT_DISTANCE = 36`) | Rows above bottom chrome fade to clear at the chrome's top edge over 36 px |
| `components/common/PageHeader.tsx` | Header is rendered above the scroll container (portal); content never scrolls *behind* visible header text |

The web has **no sticky section headers**. Native pinned section titles are a native addition and follow R5.

## Rules

- **R1. One mechanism per edge kind per platform.** Every top or bottom edge treatment goes through the platform's canonical component (table below). Feature folders never build their own scroll mask, gradient mask or scroll-edge effect; extend the canonical component instead.
- **R2. Clear at the edge, opaque after the ramp.** Content is fully transparent at the obscuring edge (header bottom, pinned title bottom, chrome top) and fully opaque `ramp` units away from it. Nothing scrolls visibly behind header or title text.
- **R3. Ramp lengths come from the web.** The target is 40 pt/dp/epx linear for top edges (`useScrollMask`) and 36 for bottom chrome (`useScrollFade`). Each constant lives in exactly one place per platform. Existing 28-unit smoothstep ramps are known debt, not precedent.
- **R4. At rest, nothing is dimmed.** At the top of a list there is no top ramp; it grows with the scroll offset (web `atTop`). At the bottom there is no bottom ramp.
- **R5. Pinned section titles behave like native sticky headers.** The title sits opaque on the page background and is never dimmed by a ramp. Rows, not titles, fade under it (R2). An incoming title pushes the pinned one out 1:1 with the scroll. Never swap text or snap. A container-level modal or page mask must not cover a pinned title; the list's own row fade takes over (`ModalTopEdgeFadeRampKey` = 0 on Apple).
- **R6. No decorative bands.** A header gets a glass or material band only when content actually scrolls behind floating chrome. HIG Scroll views: "Only use an edge effect when a scroll view is behind floating interface elements. It isn't decorative." Sheets hide the system edge effect (#94). **Approved variant (Apple pages):** the system soft top scroll-edge effect plus `TopEdgeScrim`, a dark legibility gradient over bright artwork that ends no lower than bar + 32 pt (max 150). It is a scrim, not a content mask, and must never dim a section-jump landing ([section-jump-landing](section-jump-landing.md)).
- **R7. Accessibility gives a hard edge, never a leak.** With Reduce Transparency, Increase Contrast or the in-app Less Transparency on (Android: the app's settings; Windows: high contrast), the ramp becomes a hard cut at the edge. Content still never shows behind the header.
- **R8. Jumps land clear of the ramp.** After a Quick Links or A–Z jump the target's first row is fully opaque and the pinned title names the target ([section-jump-landing](section-jump-landing.md)).

## Canonical implementation

| Edge kind | Apple (`apple/Sources/…`) | Android (`android/app/src/main/java/com/festivalscoretracker/android/…`) | Windows (`windows/…`) |
|---|---|---|---|
| Page header | `FestivalUI/Common/Chrome/PageChrome.swift` `TopEdgeScrim` + system soft edge (R6 variant) | `ui/common/FestivalScreen.kt` pinned `TopAppBar` (opaque bar, content clipped at its edge) | `Festival.App` page header row (content clipped below it) |
| Sheet header | `FestivalUI/Design/ModalTopEdgeFade.swift` `ModalTopEdgeFadeModifier` (40), applied by `FestivalModal` | `ui/common/FestivalModal.kt` (no ramp: hard edge) | `Festival.App/Controls/FestivalDialog.cs` (`ContentDialog`, no ramp) |
| Pinned section title in a list | `FestivalUI/Design/PinnedHeaderEdgeFade.swift` `PinnedHeaderEdgeFade` (40 linear, one mask `PinnedHeaderFadeMask`): Songs' floating bar via `pinnedHeaderEdgeFadeMask(edge:active:depthLimit:)`, native pinned headers in sheet lists (Notifications) via `pinnedHeaderEdgeFadeList` / `…Header` / `…Row`. Scroll position from `onScrollGeometryChange` (iOS 18 / macOS 15+) or `FestivalUI/Common/PlatformScrollObserver.swift` (iOS 17 / macOS 14) | `core/songs/SongHeaderEdgeFade.kt` + `ui/songs/PinnedHeaderEdgeFade.kt` (native `stickyHeader`) | `Festival.Core/Domain/SongHeaderEdgeFade.cs` + `Festival.App/Controls/TopEdgeFade.cs` |
| Bottom chrome (pager, footer) | `FestivalUI/Design/BottomChromeFade.swift` `bottomChromeFade` / `reportsBottomChromeTop` (36, `FestivalCore/ScrollEdgeFade.swift` stops), used by every paginated board with or without a player footer (#305; the full band leaderboard's selected-band footer, #306; Player Bands' card list, #319). Tests: `ScrollEdgeFadeTests`, `BottomChromeFadeTests`, hosted `BottomChromeFadeHostedTests` (Song Band and Band Rankings without a footer: mid-scroll fade, readable last row, each R7 mode) | `core/rankings/BoardFooterEdgeFade.kt` | `Festival.Core/Domain/BoardFooterEdgeFade.cs` + `Festival.App/Controls/BoardFooterFade.cs` |

Apple's edge fades read the scroll position the same way on every supported system: `FestivalUI/Common/ScrollEdgeReader.swift` `onScrollEdgeReading` (sheet header, bottom chrome) uses `onScrollGeometryChange` on iOS 18 / macOS 15+; on iOS 17 / macOS 14 (`ScrollEdgeTracking.usesLegacyPath`) its `EnclosedScrollViewLocator` finds the wrapped content's own `UIScrollView` / `NSScrollView` (the one covering most of the content, searched no higher than the hosting view controller's view, so never the page behind a sheet) and hands it to `PlatformScrollObserver`, which reports the same top inset, offset and remaining overflow. Pinned-title sheet lists reach the same observer through their rows' `ListScrollViewLocator`. `onScrollGeometryChange` can record a changed value without calling its action (a scroll view that outlives a reload gate's content swap kept a 0 pt bottom fade over its taller rows, #317), so the reader re-delivers a value its action missed on the next main-actor turn (`ScrollEdgeReadingRelay.reconcile`); never rely on the action alone. Never fall back to a permanent hard cut or a permanent full ramp (#308 review). Tests: `PinnedHeaderLegacyScrollRenderTests` and `ScrollEdgeLegacyRenderTests` (sheet-header 40 pt ramp while scrolling, zero bottom ramp at the end of a `List` and a `ScrollView`, reader parity) run both paths; `FST_DEBUG_LEGACY_SCROLL_GEOMETRY=1` (Debug) forces the legacy path on a newer simulator.

**Approved variant (Apple Songs before iOS 26 / macOS 26):** Songs keeps native pinned List headers on an opaque backing with a hairline and no row ramp. The owner chose "sticky section titles … pinned at the top on a fully opaque backing, so no row shows through beneath them" ([songs spec](../pages/songs/spec.md), 2026-09-28); the floating section bar and its ramp need iOS 26's scroll-edge chrome.

Apple ramp constants live only in `FestivalCore/ScrollEdgeFade.swift` (`topDistance` 40, `distance` 36, applied through `ScrollEdgeFade.ramp`), and `Design/ScrollEdgeFadeModifiers.swift` `ScrollEdgeHardEdge` is the one R7 switch (system Reduce Transparency or Increase Contrast, or the in-app Less Transparency or Increase Contrast) read by every Apple edge component, `bottomChromeFade` included. Apple Search shows no section titles (#299), so it has no pinned-title fade.

`TODO(orchestrator)`: confirm whether Android/Windows page and sheet headers need a web-style 40 ramp (R2/R3) or keep the platform's opaque bar with a hard edge as an approved variant (M3 top app bar and Fluent header both separate content from chrome).

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Android `SongHeaderEdgeFade.DEPTH_DP = 28`, Windows `SongHeaderEdgeFade.Depth = 28` (smoothstep pinned-title fades) | R3 | Move to 40 linear and sweep Songs and the sheet lists. Android and Windows lanes (#308: the Apple worker may not edit `android/` or `windows/`; Apple landed) |
| Android `BoardFooterEdgeFade.DEPTH_DP = 40`, Windows `BoardFooterEdgeFade.Depth = 40` (bottom chrome) | R3 | Move to 36 (web `useScrollFade`) and sweep the rankings footers. Android and Windows lanes (#308) |

## Guards (`tools/pattern_guard.py`)

- `scroll-edge/apple-mask`: `.mask` in Apple sources outside `Design/`, the shell drawer and first-run demos needs an approved entry.
- `scroll-edge/apple-edge-effect`: `scrollEdgeEffectStyle` / `scrollEdgeEffectHidden` only in `PageChrome.swift` and `ModalTopEdgeFade.swift`.
- `scroll-edge/android-dstin`: `BlendMode.DstIn` only in the edge-fade components.
- `scroll-edge/windows-mask`: `CompositionMaskBrush` only in `TopEdgeFade.cs` / `BoardFooterFade.cs`.
