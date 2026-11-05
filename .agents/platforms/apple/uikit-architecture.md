# UIKit consumer architecture

> **What:** Festival's app-owned page, modal and navigation adapters over the immutable shared foundation. **Read when:** extending common infrastructure in the UIKit iOS/iPadOS port.

## Scope and boundaries

- iPhone, iPhone Duo and iPad share the UIKit implementation and existing Festival models, routes, tokens and layout policy.
- macOS is sidelined. It needs a separately designed Mac-specific UI/framework; no UIKit page abstraction declares Mac support.
- `FentonPlatform` remains unchanged. The consumer keeps the immutable package revision already used by the shared pilot.
- HASS is a mechanism precedent, not a source of Festival domain models, routes or branding.

## Shared parents

| Owner | Responsibility |
|---|---|
| `UKPageViewController` | Composes the core content host; native versus contained viewport ownership; state-overlay and reload-gate handoff |
| Profile/Rivals/Form family bases | Existing feature layout, load policy and native-scroll semantics through that adapter |
| `UKSheetNavigationController` / `UKSheet` | Task title, native Close/Escape, feature bar items, sheet style/detents, search-safe dismissal and fade/coverage lifetime |
| `UKSectionStack` | Existing on-demand split policy, stable route/controller identity and owned split chrome |
| Existing `DeviceLayout` / `OnDemandSplitPolicy` | Size classes, reserved regions, owner-approved split geometry and navigation semantics |

Do not substitute a generic wrapper that hides page tools, changes route identity or replaces the app's visual policy.

## Navigation decision

Agent decision (2026-11-05, user-directed pass; owner may override): preserve the current owner-approved on-demand split instead of replacing it wholesale with an unqualified native split configuration. Update navigation stacks only when their controller partitions change; geometry-only updates must not clear the detail stack. Restore only split-owned Back/Close state when a controller returns to ordinary navigation. Reduce Motion applies the final frame without a new animation.

HIG Designing for iPhone Duo: "Preserve functionality, element state, hierarchy, and access across displays/poses." HIG Toolbars: "A custom version should retain the standard appearance, expected behavior, fit with the interface, and consistent implementation throughout the app."

## Validation ownership

- `FestivalMobileUIKitHosted` is a real iOS app-hosted test scheme for page/modal/navigation regressions. Its design-gallery host is offline and separate from user-facing journeys.
- App-hosted tests and fixture-backed UI/accessibility journeys are distinct evidence.
- The conditional UIKit tests do not run on the macOS SwiftPM host; an empty bundle is not success.
- Lifecycle tests require an actual connected `UIWindowScene`, restore the previous key window, and wait for UIKit completion rather than manually invoking appearance callbacks.
- The three foundation suites live under serialized `UKFoundationTests`: `@MainActor` alone does not isolate an asynchronous window/presentation lifetime from another suite. Modal fixtures await foreground-scene admission before presenting.
- Await the host's real appearance before presenting, then use UIKit presentation completions and search delegate callbacks; a transition-coordinator property's presence is not the test's readiness event.
- The hosted bundle imports the app host's package images without linking another copy; duplicate package classes invalidate shared-state/lifecycle evidence.
- Phone, Duo and iPad runtime/pose results remain separate. A simulated fold/window override does not prove a physical hinge.
- Use the existing capacity and simulator tools; never preempt another lane's product simulator.

`UKPageFoundationTests` covers inset ownership, state cycles, current scroll position and feature constraints through a reload gate. `UKSectionStackFoundationTests` covers controller identity and feature chrome through split reshapes. `UKModalFoundationTests` in the hosted target covers real presentation, Close/Escape, search, dismissal callbacks and coverage.

The separate `Apps/iOSUITests/UKModalFoundationTests.swift` exercises Profiles/search dismissal, compact Sort actions, a scoped AX5 Close audit, and Songs -> Detail -> paged Leaderboard. Run it against an explicitly selected loopback fixture with `TEST_RUNNER_FST_MODAL_FIXTURE_URL=<loopback-origin> python3 tools/ios_sim.py uitest --app uikit --device <owned-device> --only UKModalFoundationTests --fail-on-skip`. A UI screenshot or successful build alone does not pass its assertions.

## Shared-core opportunities, not changes in this pass

| Candidate | Why multiple consumers could benefit |
|---|---|
| Explicit native-scroll versus contained viewport policy | Both products need one inset owner without forcing every native scroll view into a cropped safe-area host |
| Modal configuration without forcing page-sheet style | Fitted/custom detents, form/page style and placement are common mechanics; task, route and dismissal decisions remain app-owned |
| Typed modal lifecycle/fitting hooks | Consumers need balanced dismissal, guarded close and fitted content without duplicating delegate/lifetime plumbing |
| Independent indicator-axis restoration | A shared scroll registration should preserve vertical/horizontal indicator ownership rather than rely on a combined deprecated getter |
| Reusable real UIKit hosted-test support | Shared capability checks and layout/lifecycle probes could reduce each consumer's Xcode-host setup |

None authorizes modifying the package, changing another product or publishing a dependency.

## Remaining app work

Migrate additional page families only with their own parity evidence. Root Profiles/Notifications share the canonical sheet and refuse overlapping independent root modals; this is not a global presentation queue. Explicit first-run appearance ownership and fully consolidated presentation scheduling remain separate app-level work; they are not reasons to put Festival routes or onboarding policy into the shared core.

Existing pending page/control parity records are not promoted by this infrastructure pass; the full `verify_product.py --strict` certification gate remains separate.
