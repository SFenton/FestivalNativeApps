# Test strategy and phases

> **What:** which tests to write at which maturity, and what certification finally requires. **Read when:** deciding what to test for your change. Platform tooling: [apple/](apple/README.md), [android.md](android.md), [windows.md](windows.md).

## Phases (operator, 2026-09-27)

| Phase | When | What |
|---|---|---|
| Build | Every commit | `swift build --build-tests` + iOS build (via `tools/lane_integrate.sh`) |
| Unit | As you go | Tests for new non-UX logic; run only new/changed tests while iterating |
| Visual smoke | While building UI | `tools/ios_sim.py shot` compared with the web app at the same viewport ([screenshot-compare](../skills/screenshot-compare/SKILL.md)) |
| UX tests | Every UI fix or feature, in the same PR | A hosted snapshot or journey that fails without the change (target 90% UX lines) |
| Accessibility tests | Every UI fix or feature, in the same PR (operator, 2026-10-08) | See [Accessibility tests with every change](#accessibility-tests-with-every-change) |
| Full audits | The **app** is complete (per platform) | Whole-app audit sweeps, contrast over artwork, in-app a11y toggles ([apple/accessibility.md](apple/accessibility.md)) |
| Screen-reader walkthroughs | After full audits | Scripted VoiceOver/TalkBack/Narrator walkthroughs per page ([apple/voiceover.md](apple/voiceover.md)) |

Do not run full device matrices or coverage gates on every slice. Online-only: do not add new offline/warm-cache test journeys.

## Accessibility tests with every change

Accessibility is tested as each feature is built or bug is fixed, not deferred to app completion (operator, 2026-10-08). A PR that adds or changes a visible control, page, sheet, row, navigation or layout on a platform **adds or updates an accessibility test on that platform** that would fail if the change regressed accessibility. Review treats a missing one as **major**. Pure logic, data or copy-only changes are exempt; say why in the PR.

Cover what the change touches:

| Concern | Assert |
|---|---|
| Name, role, value, state | Every new or changed interactive element has a label (not an icon name or file name), the right trait/role and its current state (selected, expanded, toggled) |
| Reading and focus order | The changed region reads in visual order, headings before their content; nothing focusable is hidden or decorative-only elements are hidden |
| Target size | Interactive elements meet the platform minimum (Apple 44 pt, Android 48 dp, Windows 40 epx touch / keyboard reachable) |
| Text scaling | At the largest size (Apple AX5, Android 200% font, Windows 225% text) text grows, isn't clipped, and actions stay reachable |
| Motion, transparency, contrast | Reduce Motion / Reduce Transparency paths when the change animates or uses materials; rendered contrast for text over artwork |
| Keyboard (macOS, iPad, Windows) | New actions are reachable and operable by keyboard |

Where to write them:

| Platform | Mechanism |
|---|---|
| Apple | Hosted tests in `apple/Tests/FestivalUITests` asserting accessibility label/traits/order/hit size, plus an XCUITest `performAccessibilityAudit` journey for new pages and sheets. A device-only check (Dynamic Type, the device tree, hit testing, the system audit) must be listed in `apple-ci`'s `FST_CI_IOS_A11Y_JOURNEYS` or CI never runs it ([apple/accessibility.md](apple/accessibility.md#ios-journeys-in-ci), [apple/xcuitest.md](apple/xcuitest.md)) |
| Android | ATF journeys in `androidTest/.../journeys/` with `JourneyHarness`: `assertAccessible()` and `readingOrder` ([android.md](android.md), [android-accessibility.md](android-accessibility.md)) |
| Windows | A page/state in `tools/windows/journeys/a11y-*.json` for `a11y_matrix.py`, plus UIA name/order checks in the feature journey ([windows-accessibility.md](windows-accessibility.md)) |
| Web (scraper repo) | Testing Library/Playwright assertions by role and accessible name (`getByRole(..., { name })`), focus order and target size in the changed component's spec |

Tests run in CI: Apple `apple-ci`, Android `android-device`, Windows `windows-ui`. A behavior that existing accessibility tests already pin down only needs those tests updated, not duplicated.

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
- **Operator-facing media** (screenshots/videos sent to the operator) are captured on the **live keyless service** in the native apps, with **SFentonX** (`195e93ef108143b2975ee46662d4d0e1`, the operator's own account) as the selected player when one is needed — e.g. Apple `FST_DEBUG_PROFILE=195e93ef108143b2975ee46662d4d0e1:SFentonX`. Natives never send selected-profile headers or blocked reads, so this is safe; the production **PWA** must still never select a profile or open player pages. Live media stays in local showcase folders; committed repo screenshots remain fixture-only (operator, 2026-09-28).
