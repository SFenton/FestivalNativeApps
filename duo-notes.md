# iPhone Duo redesign notes
Journey: UIKit Songs -> Song Detail -> Song Leaderboard; shared page and modal infrastructure.
Stack: UIKit, iOS 17 minimum, Xcode 27.1; FentonPlatform immutable pilot pin.
Stage: 4  Next: Execute the app-hosted and fixture-backed phone/Duo/iPad checks.

## Findings
- Songs: native section navigation, custom list chrome and retained filtering/scroll state.
- Song Detail -> leaderboard: app-owned on-demand split, moving existing controllers between native navigation stacks.
- Modal shell: native navigation/sheets; duplicated dismissal and lifecycle ownership.
- Profile/Rivals/forms: independent scrolling bases; common safe-area/state ownership is a candidate, not runtime-verified.
- Layout risks: split reshape clears its trailing stack on geometry updates; custom split Back/Close items can survive role changes.
- Bars: native tab/navigation containers already exist; preserve the owner's floating phone tools and Duo/iPad bar items.
- Prior SwiftUI-only pose evidence is not UIKit evidence. Existing owner choices remain in the canonical Duo and pattern docs.
- Camera, hinge effects and scene accessories: N/A; this pass has no such features.

## Checklist match
- 1 Build/resizability: Ready SDK 27.1; Change centralize asymmetric safe-area ownership without changing native scrolling [HIG, T461].
- 2 Containers/bars: Ready native navigation/tab containers; Decision preserve owner-approved on-demand split [HIG, T462].
- 3 Bar audit: Change restore app-owned split Back/Close when roles change; preserve page tools and system placement [HIG, T462].
- 4 Outer display: Change test asymmetric safe areas and keyboard/sheet dismissal; backgrounds remain edge-to-edge [HIG, T466].
- 5 Inner display: Ready app-owned split policy; Change preserve controller/scroll identity on reshapes [HIG, T466].
- 6 Reserved regions: Ready existing DeviceLayout/OnDemandSplitPolicy; no new width or hinge heuristics [HIG, T463].
- 7 Multitasking/PiP: Change resize continuity tests; PiP media N/A, no video [HIG, T464].
- 8 Table pose: N/A, no pose-specific functionality [HIG, T466].
- 9 Extras: N/A, no camera, hinge effects or scene accessories [T464, T465].
- Continuity: Change verify selection, scroll and hierarchy across compact/regular reshapes [HIG, T466].

## Decisions
- Preserve current routes, tab policy, visual identity and on-demand split geometry.
- macOS is sidelined for its own framework/UI; no macOS implementation in this pass.
- Do not modify the shared core package; flag multiproduct gaps separately.
- Agent choice (2026-11-05, automated decision policy): compose the existing core host in a Festival page adapter rather than duplicate geometry or change the package.
- Page viewport: retain native scrolling by default; opt into explicit containment only where the app owns insets [HIG Layout].
- Modal lifecycle: improve the existing UKSheet path instead of adding a competing presenter or changing task semantics [HIG Sheets/Modality].
- Navigation: preserve the owner's split geometry; update only changed stacks and restore owned chrome instead of replacing all containers [HIG continuity].
- Proceed directly with native implementation; existing visual/product choices are preserved, not re-designed. Owner may override these architecture choices.

## Done / verified
- Published UIKit base and prior shared pilot inspected; active user worktrees preserved.
- Baseline UIKit simulator build passed in the isolated implementation lane.
- No new UIKit pose, accessibility or continuity claims yet.
