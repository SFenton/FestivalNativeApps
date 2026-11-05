# iPhone Duo redesign notes
Journey: UIKit Songs -> Song Detail -> Song Leaderboard; shared page and modal infrastructure.
Stack: UIKit, iOS 17 minimum, Xcode 27.1; FentonPlatform immutable pilot pin.
Stage: 5  Next: Separate full pose/multitasking and matched performance qualification.

## Findings
- Songs: native section navigation, custom list chrome and retained filtering/scroll state.
- Song Detail -> leaderboard: app-owned on-demand split, moving existing controllers between native navigation stacks.
- Modal shell: one native Close/Escape/search dismissal path with balanced one-shot lifetime.
- Profile/Rivals/forms: shared app-owned page adapter; native inset, state and gate-handoff regressions passed.
- Split reshape: unchanged controllers/scroll remain in place; feature Back/Close state is restored after role changes.
- Bars: native tab/navigation containers already exist; preserve the owner's floating phone tools and Duo/iPad bar items.
- Prior SwiftUI-only pose evidence is not UIKit evidence. Existing owner choices remain in the canonical Duo and pattern docs.
- Camera, hinge effects and scene accessories: N/A; this pass has no such features.

## Checklist match
- 1 Build/resizability: Verified SDK 27.1 build; explicit native/contained inset ownership [HIG, T461].
- 2 Containers/bars: Ready native navigation/tab containers; Decision preserve owner-approved on-demand split [HIG, T462].
- 3 Bar audit: Hosted split-chrome restoration and scoped native Close/AX5 journeys passed [HIG, T462].
- 4 Outer display: Phone search/sheet dismissal passed; separate Duo outer-display pose not qualified [HIG, T466].
- 5 Inner display: Default Duo journeys and hosted controller/scroll continuity passed; pose transitions not qualified [HIG, T466].
- 6 Reserved regions: Ready existing DeviceLayout/OnDemandSplitPolicy; no new width or hinge heuristics [HIG, T463].
- 7 Multitasking/PiP: Hosted reshape passed; native multitasking not certified; PiP N/A, no video [HIG, T464].
- 8 Table pose: N/A, no pose-specific functionality [HIG, T466].
- 9 Extras: N/A, no camera, hinge effects or scene accessories [T464, T465].
- Continuity: Hosted route/controller/scroll checks passed; no physical-hinge claim [HIG, T466].

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
- App/hosted/UI builds and 16 hosted regressions passed; no skipped tests.
- Four fixture UI/accessibility journeys passed per phone, Duo and iPad, including native Close hit-region probes at AX5.
- Scope and remaining qualification: `.agents/platforms/apple/uikit-architecture.md`; no full-app or performance claim.
