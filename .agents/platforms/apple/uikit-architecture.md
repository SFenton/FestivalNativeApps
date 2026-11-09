# UIKit consumer architecture

> **What:** Festival's app-owned page, modal and navigation adapters over the immutable shared foundation. **Read when:** extending common infrastructure in the UIKit iOS/iPadOS port.

## Scope and boundaries

- The current owner request is a **full pass over all active UIKit pages, modals, components and animations**, plus matched simulator performance measurement. The earlier infrastructure slice is not completion of this request.
- iPhone, iPhone Duo and iPad share the UIKit implementation and existing Festival models, routes, tokens and layout policy.
- macOS is sidelined. It needs a separately designed Mac-specific UI/framework; no UIKit page abstraction declares Mac support.
- `FentonPlatform` remains unchanged. The consumer keeps the immutable package revision already used by the shared pilot.
- HASS is a mechanism precedent, not a source of Festival domain models, routes or branding.

## Shared parents

| Owner | Responsibility |
|---|---|
| `UKScreenViewController` | Explicit app-owned appearance/disappearance and first-run lifecycle, without method swizzling |
| `UKPageViewController` | Composes the core content host; native versus contained viewport ownership; state-overlay and reload-gate handoff |
| Scrolling, board, catalogue, profile, rival and form family bases | Existing feature layout, load policy and native-scroll semantics through that adapter |
| `UKSheetNavigationController` / `UKSheet` | Task title, native Close/Escape, feature bar items, sheet style/detents, search-safe dismissal and fade/coverage lifetime |
| `UKPresentationCoordinator` | Window-scoped independent task admission and related native confirmations/pickers |
| `UKMotionVisibility` / canonical motion components | Visible-scene and presentation ownership, cancellation and reduced-motion behavior |
| `UKSectionStack` | Existing on-demand split policy, stable route/controller identity and owned split chrome |
| `UKDetailSelection` / shared accessibility focus chooser | Window-owned detail selection and focus on the actual pane heading after user navigation |
| Existing `DeviceLayout` / `OnDemandSplitPolicy` | Size classes, reserved regions, owner-approved split geometry and navigation semantics |

Do not substitute a generic wrapper that hides page tools, changes route identity or replaces the app's visual policy.
Split geometry may retain an empty detail placeholder, but its divider is hidden until a
detail selection is open; a reserved pane is not an active selected detail.
Only an open detail carries the stable native `fst.split.trailing` container identifier.
An empty placeholder does not expose an active-pane identifier or become a separate
spoken control.
Pane heading focus includes that pane's native navigation chrome, not just the page's
safe-area body. The canonical native title retries a pending move after actual layout;
it does not guess when a loaded heading or bar title becomes available.

`UKFont` starts with UIKit's preferred text-style descriptor and modifies only requested
weight, italic or number/design traits. It retains native Dynamic Type metadata and the
style's own size rather than rebuilding a plain system font with a category-specific
scale correction. HIG Typography: "Consider using the built-in text styles" and "Modify
the built-in text styles if necessary" with symbolic traits.

## Full-pass acceptance

The source-digest-bound [UIKit ownership contract](../../../contracts/uikit-architecture.json) discovers every frontend file, its controller ancestry and native animation sites. Refresh discovery with `python3 tools/uikit_architecture.py --refresh`; a changed source invalidates its prior review. Each record requires its canonical owner, rationale and verification references before `python3 tools/uikit_architecture.py --strict` can pass. Neither a source count nor a populated manifest proves runtime behavior.
Record a completed source review with `--review <exact-path> --owner <canonical-owner>
--disposition <kind> --note <rationale> --verification <repository-file>`; repeat
verification references as needed. The tool refuses stale source and missing evidence files.

Completion requires all of the following:

- Every active file is reviewed and owned; content controllers use the explicit screen lifecycle and appropriate shared page bodies. Window/navigation containers are documented exceptions, not hidden feature-specific page bases.
- Every independent task uses the window presentation lifecycle; related alerts, Photos/Files and search preserve their native behavior, unsaved input and dismissal ownership.
- Every animation has a canonical owner, cancellation/visibility behavior and system/in-app accessibility policy. Preserve approved timing and visual variants; do not remove a product rule just to improve a benchmark.
- Existing page/control state, route, resize/pose, rendering and accessibility evidence is exercised for the full UIKit scope. Debug-only and disabled-policy paths are classified explicitly.
- Optimized, fixture-matched before/after UIKit and SwiftUI-reference measurements cover real content, startup, navigation/modals, scrolling/hitches, CPU and memory. Missing/contaminated measurements remain gaps; a correctness suite is not performance evidence.

The ownership guard runs in contract CI. Runtime, coverage and performance acceptance remain independent; do not mark the pass complete while any active file, required state or benchmark cell is unqualified.

## Navigation decision

Agent decision (2026-11-05, user-directed pass; owner may override): preserve the current owner-approved on-demand split instead of replacing it wholesale with an unqualified native split configuration. Update navigation stacks only when their controller partitions change; geometry-only updates must not clear the detail stack. Restore only split-owned Back/Close state when a controller returns to ordinary navigation. Reduce Motion applies the final frame without a new animation.

HIG Designing for iPhone Duo: "Preserve functionality, element state, hierarchy, and access across displays/poses." HIG Toolbars: "A custom version should retain the standard appearance, expected behavior, fit with the interface, and consistent implementation throughout the app."

## Validation ownership

- `FestivalMobileUIKitHosted` is a real iOS app-hosted test scheme for page/modal/navigation regressions. Its design-gallery host is offline and separate from user-facing journeys.
- App-hosted tests and fixture-backed UI/accessibility journeys are distinct evidence.
- Set `FST_UITEST_KEEP_RESULTS=1` for qualification journeys. The normal driver deletes
  passing bundles after reading their summaries; durable qualification needs green
  attachments and result bundles as well as source-bound logs.
- The conditional UIKit tests do not run on the macOS SwiftPM host; an empty bundle is not success.
- Lifecycle tests require an actual connected `UIWindowScene`, restore the previous key window, and wait for UIKit completion rather than manually invoking appearance callbacks.
- All UIKit hosted suites live under serialized `UKFoundationTests`: `@MainActor` alone does not isolate an asynchronous window/presentation lifetime from another suite. Modal fixtures await foreground-scene admission before presenting.
- Await the host's real appearance before presenting, then use UIKit presentation completions and search delegate callbacks; a transition-coordinator property's presence is not the test's readiness event.
- Plain UIKit views can report a zero `accessibilityFrame` in an in-process host. Use
  native view/window/screen coordinate conversion for hosted layout geometry, including
  the pane's nonzero origin; a whole-window origin-zero test cannot prove split focus. Actual
  accessibility-frame, hit-region and reading-order proof still belongs to XCUITest.
- The hosted bundle imports the app host's package images without linking another copy; duplicate package classes invalidate shared-state/lifecycle evidence.
- Phone, Duo and iPad runtime/pose results remain separate. A simulated fold/window override does not prove a physical hinge.
- Use the existing capacity and simulator tools; never preempt another lane's product simulator.

`UKPageFoundationTests` covers inset ownership, state cycles, current scroll position and feature constraints through a reload gate. `UKSectionStackFoundationTests` covers controller identity and feature chrome through split reshapes. `UKModalFoundationTests` in the hosted target covers real presentation, Close/Escape, search, dismissal callbacks and coverage.

The separate `Apps/iOSUITests/UKModalFoundationTests.swift` exercises Profiles/search dismissal, compact Sort actions, a scoped AX5 Close audit, and Songs -> Detail -> paged Leaderboard. Run it against an explicitly selected loopback fixture with `TEST_RUNNER_FST_MODAL_FIXTURE_URL=<loopback-origin> python3 tools/ios_sim.py uitest --app uikit --device <owned-device> --only UKModalFoundationTests --fail-on-skip`. A UI screenshot or successful build alone does not pass its assertions.

Native Close's visual frame is not its activation region. Probe inside the standard 44 pt target, aligned to the display's pixel grid rather than its exclusive maximum edge; do not replace native chrome because an edge probe rounds outside its target.

## Last measured qualification

| Date | Scope | Result and limit |
|---|---|---|
| 2026-11-07 | Current full-pass implementation snapshot V17 over `412e0370`, [UIKit proposal](https://github.com/SFenton/FestivalNativeApps/pull/850) | Source ownership passes for all 134 UIKit files. Current phone-hosted suite passes 62 checks; three actual iPad default/AX5 pane focus, selection and native Close journeys and the real folded-Duo Large/AX5 input rendering journey pass with retained result bundles and zero skips. Full app/state/pose/coverage matrix and matched performance acceptance remain pending; these focused results do not certify the whole request or physical hardware. |
| 2026-11-08 | Current repair checkpoint over the same frozen source family | Changed UIKit consumer ownership records remain bound to exact current source bytes. The current v3+repairs hosted SDK build passes 65 tests / 68 invocations with 0 failures and 0 skips; the 54-case inventory completed 108 n=1 trials without timeout, missing-content, event or component errors, with rounds=1<3 as its sole hard gate. Full n=3 simulator/physical, state/AX/pose and coverage qualification remain pending. The shared core pin is unchanged and macOS remains sidelined. |

Bounded batches supply separate valid result bundles where a long batch times out; incomplete/zero-test runs are not acceptance evidence. Shared Swift compilation does not certify macOS UI.

## Shared-core opportunities, not changes in this pass

| Candidate | Why multiple consumers could benefit |
|---|---|
| Explicit native-scroll versus contained viewport policy | Both products need one inset owner without forcing every native scroll view into a cropped safe-area host |
| Modal configuration without forcing page-sheet style | Fitted/custom detents, form/page style and placement are common mechanics; task, route and dismissal decisions remain app-owned |
| Typed modal lifecycle/fitting hooks | Consumers need balanced dismissal, guarded close and fitted content without duplicating delegate/lifetime plumbing |
| Independent indicator-axis restoration | A shared scroll registration should preserve vertical/horizontal indicator ownership rather than rely on a combined deprecated getter |
| Reusable real UIKit hosted-test support | Shared capability checks and layout/lifecycle probes could reduce each consumer's Xcode-host setup |
| Preferred-font descriptor variants | Both consumers can retain native Dynamic Type metadata and window traits without category-specific scale correction; product typography choices stay local |
| Native heading-availability and pane-coordinate hooks | Both consumers need actual layout/completion signals and nonzero window coordinates; route-specific focus targets and labels remain app-owned |

None authorizes modifying the package, changing another product or publishing a dependency.

## Remaining app work

The full pass is in progress. Requalify all migrated page families and task/component/animation states after the explicit lifecycle and presentation changes; the earlier slice's evidence is not transferable by assertion. These remain app-owned changes, not reasons to put Festival routes or onboarding policy into the shared core.

Existing pending page/control parity records are not promoted by this infrastructure pass; the full `verify_product.py --strict` certification gate remains separate.
