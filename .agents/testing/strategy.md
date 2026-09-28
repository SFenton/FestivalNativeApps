# Test strategy and phases

> **What:** which tests to write at which maturity, and what certification finally requires. **Read when:** deciding what to test for your change. Platform tooling: [apple/](apple/README.md), [android.md](android.md), [windows.md](windows.md).

## Phases (operator, 2026-09-27)

| Phase | When | What |
|---|---|---|
| Build | Every commit | `swift build --build-tests` + iOS build (via `tools/lane_integrate.sh`) |
| Unit | As you go | Tests for new non-UX logic; run only new/changed tests while iterating |
| Visual smoke | While building UI | `tools/ios_sim.py shot` compared with the web app at the same viewport ([screenshot-compare](../skills/screenshot-compare.md)) |
| UX tests | A **feature** is complete | XCUITest journeys + hosted snapshot per control state (target 90% UX lines) |
| Accessibility | The **app** is complete (per platform) | Audits, focus order, Dynamic Type, contrast, in-app a11y toggles ([apple/accessibility.md](apple/accessibility.md)) |
| VoiceOver | After accessibility | Scripted screen-reader walkthroughs per page ([apple/voiceover.md](apple/voiceover.md)) |

Do not run full device matrices or coverage gates on every slice. Online-only: do not add new offline/warm-cache test journeys.

## Certification (per platform, per language) — two independent gates

1. **Line coverage:** ≥95% non-UX and ≥90% UX source lines from the platform's real coverage reports. A screenshot count or automation count is not a percentage; never exclude handwritten code to pass.
2. **States:** every reachable control state and transition in `contracts/product.json` has visual, navigation and accessibility evidence. `python3 tools/verify_product.py --strict` fails until all four platforms have it.

| Test kind | Covers |
|---|---|
| Logic | Wire decoding (compact fields, numeric transforms), publication pin / 409 retry / 304 ETag, cache invalidation, filters/sorting, navigation guards; negative, stale, missing and retry cases in fixtures |
| UI | Snapshot per declared control state / theme / text size, nested and driving controls; page, guard, modal, back and deep-link journeys; labels, focus, hit targets, contrast, reduced motion |
| Visual reference | Load the real PWA at matching portrait/landscape viewports with deterministic fixtures ([web-reference](web-reference.md)); record intentional Fluent/native deviations. Reading code or guessing viewports does not replace an observed comparison |

## Evidence rules

- Run simulators/emulators **serially**; tag screenshots with OS, device, pose, theme and text size. Unavailable runtimes/postures are gaps, not passes.
- Mocks replace every side-effecting endpoint ([fixtures](fixtures.md), [service safety](../platforms/service-safety.md)).
- Test behavior changes, not only compilation. A passing aggregate gate does not certify each control state.
- Keep raw build logs and screenshots in private session evidence, never in the repo.
