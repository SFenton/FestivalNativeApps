# UIKit page foundation

> **What:** the Festival-owned page adapter around the pinned shared UIKit host. **Read when:** creating a UIKit scrolling page or changing viewport, state-overlay or loading-gate ownership.

Status: **current**. Scope: the UIKit iOS/iPadOS port only.

## Intent

One page adapter owns content installation, state overlays and temporary loading-gate handoff. Feature families keep their route, loading keys, section layout, artwork and visual identity.

## Rules

- **R1. One viewport owner.** `UKPageViewController` composes `FentonContentContainmentView`; never fork the shared implementation or add another feature-local content host.
- **R2. Native scrolling stays native.** The default `.native` viewport fills the controller and leaves UIKit's automatic scroll adjustment intact, including content under managed bars. Preserve each family's existing asymmetric content margins.
- **R3. Explicit containment is opt-in.** `.contained` gives the shared host safe-area/inset ownership and registers the scroll view. Unregister or replace it through the adapter so its original adjustment behavior and insets are restored.
- **R4. States preserve content identity.** Plain state swaps do not rebuild or reparent the primary scrolling view. A loading gate may temporarily host it; reclaim it before removing that gate, preserving feature-owned constraints, offset and inset policy.
- **R5. No domain lifecycle in the adapter.** Account/publication keys, requests, retries, Quick Links and feature sections remain with the existing models and page families. The adapter does not invent a reload on appearance.
- **R6. Keep platform boundaries explicit.** UIKit sources remain `#if os(iOS)`. macOS is sidelined for its own UI/framework and does not inherit these page implementations.

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
| Profile/Statistics/Bands family | `UIKitPort/Features/Profile/UKProfilePage.swift`, `UKProfileScrollViewController` |
| Rivals/Compete/Suggestions family | `UIKitPort/Features/Rivals/UKRivalsPage.swift`, `UKRivalsPageViewController` |
| Native form family | `UIKitPort/Features/Songs/UKSongsForm.swift`, `UKFormViewController` |

Paths are relative to `apple/Sources/FestivalUI/`. The web has no equivalent UIKit-controller layer. Related behavior remains in [back-keeps-place](back-keeps-place.md), [load-transition](load-transition.md), [modal-shell](modal-shell.md) and [scroll-edge](scroll-edge.md).

## Evidence and limits

`UKPageFoundationTests` runs in the real iOS-hosted target, not an empty macOS conditional suite. New families adopt the adapter only with viewport/state and accessibility evidence; this entry does not certify every UIKit page or a device pose.
