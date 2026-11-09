# UIKit page foundation

> **What:** the Festival-owned page adapter around the pinned shared UIKit host. **Read when:** creating a UIKit scrolling page or changing viewport, state-overlay or loading-gate ownership.

Status: **current**. Scope: the UIKit iOS/iPadOS port only.

## Intent

One page adapter owns content installation, state overlays and temporary loading-gate handoff. Feature families keep their route, loading keys, section layout, artwork and visual identity.

## Rules

- **R1. One viewport owner.** `UKPageViewController` composes `FentonContentContainmentView`; never fork the shared implementation or add another feature-local content host.
- **R2. Native scrolling stays native.** The default `.native` viewport fills the controller and leaves UIKit's automatic scroll adjustment intact, including content under managed bars. Preserve each family's existing asymmetric content margins.
- **R3. Explicit containment is opt-in.** `.contained` gives the shared host safe-area/inset ownership and registers the scroll view. Unregister or replace it through the adapter so its original adjustment behavior and insets are restored.
- **R4. States preserve content identity.** Plain state swaps do not rebuild or reparent the primary scrolling view. A full-page state hides the primary host, including its accessibility subtree, until the state clears. A loading gate may temporarily host it; reclaim it before removing that gate, preserving feature-owned constraints, current user offset and inset policy.
- **R5. No domain lifecycle in the adapter.** Account/publication keys, requests, retries, Quick Links and feature sections remain with the existing models and page families. The adapter does not invent a reload on appearance.
- **R6. Keep platform boundaries explicit.** UIKit sources remain `#if os(iOS)`. macOS is sidelined for its own UI/framework and does not inherit these page implementations.
- **R7. Appearance is explicit.** Every app-owned content controller inherits `UKScreenViewController`, directly or through its page family. The base forwards actual native appearance/disappearance to first-run and motion ownership; no global `UIViewController` method exchange. Cache the window's coordinator while attached so disappearance cancels that same owner's pending builder even after `view.window` becomes nil. Window and navigation containers are explicit inventory exceptions.
- **R8. Mixed layouts keep one canvas.** Controls, results and pinned chrome may compose `pageBodyView` through `installPageBody`. A family installs its real scroller/board/gate, not an empty host beside feature-local root content. Register the primary scroller with UIKit's managed bars through `setContentScrollView`, separately from explicit inset registration.
- **R9. Shared form actions keep native targets.** Reset/action buttons produced by the form parent retain at least a 44 pt height and width at default text size; padding around a smaller button is not its native activation target.
- **R10. Split focus and selection stay window-owned.** The shell publishes its selected detail route, and reusable controls bind native selected state through `ukBindDetailSelection`. A user-opened pane requests its actual heading through the existing accessibility focus chooser; appearance/layout can fulfill a pending request once data is visible. Geometry-only reshapes do not move focus.

## Decision

Agent decision (2026-11-05, user-directed architecture pass; owner may override):

| Option | Result | Choice |
|---|---|---|
| Duplicate each family's viewport/state plumbing | Further drift and repeated fixes | No |
| Change the shared package to fit Festival | Expands the consumer pass and changes other products | No |
| Compose the pinned core in a Festival adapter | Shared mechanics with existing native scrolling and app policy | Yes |

HIG Layout: "Respect system safe areas, margins, and guides"; "Choose layout from size classes, not device type/idiom or orientation". HIG Designing for iPhone Duo: "Preserve functionality, element state, hierarchy, and access across displays/poses." These support a single explicit owner, not double application of insets.

## Canonical implementation

| Role | Implementation |
|---|---|
| Viewport and state handoff | `UIKitPort/Common/UKPageFoundation.swift`, `UKPageViewController`, `UKPageViewportPolicy` |
| Explicit screen lifecycle | `UIKitPort/Common/UKScreenFoundation.swift`, `UKScreenViewController` |
| Profile/Statistics/Bands family | `UIKitPort/Features/Profile/UKProfilePage.swift`, `UKProfileScrollViewController` |
| Rivals/Compete/Suggestions family | `UIKitPort/Features/Rivals/UKRivalsPage.swift`, `UKRivalsPageViewController` |
| Native form family | `UIKitPort/Features/Songs/UKSongsForm.swift`, `UKFormViewController` |
| Board/catalogue/search/detail pages | Existing UIKit feature controllers install their real board, gate, scroll content or native mixed canvas through `UKPageViewController` |

Paths are relative to `apple/Sources/FestivalUI/`. The web has no equivalent UIKit-controller layer. Related behavior remains in [back-keeps-place](back-keeps-place.md), [load-transition](load-transition.md), [modal-shell](modal-shell.md) and [scroll-edge](scroll-edge.md).

## Evidence and limits

`UKPageFoundationTests`, `UKRouteArchitectureTests` and `UKMotionFoundationTests` run in the real iOS-hosted target, not an empty macOS conditional suite. The full source-bound ownership contract and its strict guard cover every frontend file; runtime/state and accessibility evidence remain independent. This entry does not certify an unexecuted page state or device pose.
