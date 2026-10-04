# macOS host limits and tooling

> **What:** signing and GUI-automation constraints for the macOS app on this Mac, and `tools/mac_app.py`, the window-only evidence tool. **Read when:** building, launching or capturing the Mac app, or claiming macOS evidence. In-process alternative: [hosted snapshots](../../testing/apple/hosted-snapshots.md). Design: [design/apple/macos.md](../../design/apple/macos.md).

## Limits

- The macOS UI-test scheme uses local **ad-hoc signing for development only**; distribution signing needs separate approval.
- `xcrun automationmodetool status` reports Automation Mode **disabled, requiring user authentication**. The ad-hoc runner timed out enabling automation before running a test. **Do not enable or bypass this setting from an agent.**
- Claim no macOS GUI/accessibility pass until a signed `.xcresult` actually contains test results. SwiftPM does not measure `apple/Apps/macOS` coverage.

## `tools/mac_app.py`

| Command | Does |
|---|---|
| `build [--configuration Debug]` | xcodegen + `xcodebuild -scheme FestivalDesktop` into `apple/DerivedData/mac` under `~/.fst-build.lock` |
| `launch [--tab T] [--route R] [--profile sfentonx\|id:name] [--anonymous] [--size WxH] [--env K=V]` | Quits the previous instance (`~/.fst-mac-app.pid`, one per host), starts the app with `-ApplePersistenceIgnoreState YES` and Debug deep links (`FST_DEBUG_TAB`, `FST_DEBUG_ROUTE`, in-memory `FST_DEBUG_PROFILE`, `FST_DEBUG_WINDOW_SIZE`), waits for its window |
| `resize --size WxH` | Sets the running window's content size |
| `command <c>` | Debug shell driver: `select:<n\|destination>`, `route:<FST_DEBUG_ROUTE syntax>`, `back`, `refresh`, `search`, `profile`, `notifications`, `whatsnew`, `sort`, `filter`, `settings[:<pane>]` (General…About), `song:<leaderboard\|history\|paths>` (the selected song), `menus` (writes the menu bar to `/tmp/fst-mac-menus.txt`; enabled states read disabled while the app is in the background, which the tool never changes), `key:<up\|down\|left\|right\|home\|end\|return\|escape\|j…>[:cmd+opt…]` (a key press through `NSWindow.sendEvent`, menu key equivalents first; the real responder chain, no event tap or permission), `minimize` / `restore` (covers the main window with an opaque window of the app's own and removes it, which changes its occlusion state: AppKit ignores `miniaturize` from an inactive app, an ordered-out last window quits a SwiftUI `Window` app and AppKit keeps a moved window partly on screen), `dismiss` |
| `shot --out PATH [--out …] [--wait S] [--window TITLE]` | `screencapture -x -o -l <CGWindowID>` of the app's largest layer-0 window only (or the one whose title contains `TITLE`: the Settings window is titled for its pane, e.g. `General`, `Paths`; `Songs` also matches the main window) |
| `quit` | Debug quit notification → `NSApp.terminate` (SIGTERM fallback) |

- **Never capture the full screen** (the operator's private desktop): `shot` refuses without the app's window ID, which `tools/mac_window.swift` finds through `CGWindowListCopyWindowInfo` filtered to the app's PID. Captures need the terminal's Screen Recording permission (granted on this Mac as of 2026-10-02).
- `resize`, `command` and `quit` are Debug-only distributed notifications handled by `MacDebugHooks` (`apple/Sources/FestivalUI/Mac/MacDebugHooks.swift`): no Apple Events, so no Automation or Accessibility prompt. Release builds ignore them.
- A Debug `--size` launch skips the frame autosave so a saved frame cannot override it.
- Operator-facing shots use the live service with `--profile sfentonx` and go to `~/FestivalShowcase/native-mac/` ([strategy](../../testing/strategy.md)); never commit them.
- Menu-bar focused values (Sort/Filter, the Song menu) are nil while the app is not frontmost, so `sort`/`filter` do nothing from a background launch; `song:paths` posts its own Debug notification instead.
- Pure parts are tested in `tools/tests/test_mac_app.py`.
- Key presses reach the focused page even though the window is not key, but SwiftUI then reports no keyboard focus, so live shots show the gray (unfocused) selection.

## Performance

Methodology, rules and the last measured numbers (Debug, Release probe, Release; Mac and iPad): [architecture.md § Performance](architecture.md#performance), tool `tools/apple_perf.py`.

- On macOS `scenePhase` stays `.active` for a visible-or-hidden window of a background app, so every continuous decoration also checks `AnimationActivity.sceneActive` (scene active and `\.festivalWindowVisible`, set from `NSWindow.occlusionState` by `MacWindowConfigurator`). A covered window reads 0% CPU; measure with the window uncovered.
- `FST_DEBUG_STILL_BACKGROUND=1` stills carousel, pulses and marquees; `FST_DEBUG_NO_BACKDROP=1` drops the backdrop, for bisecting.
- **Songs scroll stress** (`apple_perf.py mac --stress`): far jumps teleport ([architecture.md § Performance](architecture.md#performance)); near jumps still animate and build rows inside `NSTableView`'s scroll, so the pass logs ~21 units ≥ 100 ms. Manual trackpad scrolling cannot be driven without Automation Mode.

## Release build (2026-10-02)

- `python3 tools/mac_app.py build --configuration Release` (1 min 50 s clean on this Mac) produces a universal (arm64 + x86_64) `FestivalDesktop.app` of 61 MB, **ad-hoc signed** (`Signature=adhoc`, no team; project `CODE_SIGN_IDENTITY: "-"`). Distribution signing and notarization need separate approval.
- `launch --configuration Release` showed the window in 1.3–1.7 s over three launches (tool-measured, includes its 0.25 s poll). Release ignores the `FST_DEBUG_*` environment and the Debug notifications, so it opens with the persisted profile and its own first-run state (the Song Info carousel on first launch) and `quit` falls back to SIGTERM.
- Release with the first-run sheet over Songs: see the CPU row in [architecture.md § Performance](architecture.md#performance) (the sheet's demo glow is a SwiftUI `repeatForever` shadow).
