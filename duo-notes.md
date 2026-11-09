# iPhone Duo redesign notes
Journey: all eight UIKit sections -> every route family -> independent sheets and related system controllers.
Stack: UIKit, iOS 17 minimum, Xcode 27.1; FentonPlatform immutable pilot pin.
Stage: 3  Next: Finish full-scope source migration, then qualify bars, continuity and matched performance.

## Findings
- Songs: native section navigation, custom list chrome and retained filtering/scroll state.
- Song Detail -> leaderboard: app-owned on-demand split, moving existing controllers between native navigation stacks.
- Modal shell: one native Close/Escape/search dismissal path with balanced one-shot lifetime.
- All content families adopt the shared app-owned page adapter; full-scope native runtime acceptance remains open.
- Split reshape: unchanged controllers/scroll remain in place; feature Back/Close state is restored after role changes.
- Bars: native tab/navigation containers already exist; preserve the owner's floating phone tools and Duo/iPad bar items.
- Prior scoped or SwiftUI-only evidence does not certify the full pass. Preserve existing Duo and pattern choices.
- Camera, hinge effects and scene accessories: N/A; this pass has no such features.

## Checklist match
- 1 Build/resizability: Explicit native/contained ownership; current full source needs build/runtime qualification [HIG, T461].
- 2 Containers/bars: Ready native navigation/tab containers; Decision preserve owner-approved on-demand split [HIG, T462].
- 3 Bar audit: Requalify all route/modal families, including search, keyboard and AX5 [HIG, T462].
- 4 Outer display: Full-scope small-window sheets/pages need qualification [HIG, T466].
- 5 Inner display: Full-scope default/book/flat continuity and modal adaptation need qualification [HIG, T466].
- 6 Reserved regions: Ready existing DeviceLayout/OnDemandSplitPolicy; no new width or hinge heuristics [HIG, T463].
- 7 Multitasking/PiP: Requalify resize and retained navigation state; PiP N/A, no video [HIG, T464].
- 8 Table pose: N/A, no pose-specific functionality [HIG, T466].
- 9 Extras: N/A, no camera, hinge effects or scene accessories [T464, T465].
- Continuity: Verify route/controller/scroll identity and pending presentation cancellation; no physical-hinge claim [HIG, T466].

## Decisions
- Preserve current routes, tab policy, visual identity and on-demand split geometry.
- macOS is sidelined for its own framework/UI; no macOS implementation in this pass.
- Do not modify the shared core package; flag multiproduct gaps separately.
- Agent choice (2026-11-05, automated decision policy): compose the existing core host in a Festival page adapter rather than duplicate geometry or change the package.
- Page viewport: retain native scrolling by default; opt into explicit containment only where the app owns insets [HIG Layout].
- Modal lifecycle: improve the existing UKSheet path instead of adding a competing presenter or changing task semantics [HIG Sheets/Modality].
- Navigation: preserve the owner's split geometry; update only changed stacks and restore owned chrome instead of replacing all containers [HIG continuity].
- Proceed directly with native implementation; existing visual/product choices are preserved, not re-designed. Owner may override these architecture choices.

## Acceptance boundary
- The full pass includes pages, modals, components and animations, with source-bound ownership records.
- Before-pass baseline is `412e0370`; matched final-source performance and full runtime journeys remain required.
- Scope and qualification: `.agents/platforms/apple/uikit-architecture.md`; no full-app or performance claim yet.
