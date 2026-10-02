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
| `command <c>` | Debug shell driver: `select:<n\|destination>`, `route:<FST_DEBUG_ROUTE syntax>`, `back`, `refresh`, `search`, `profile`, `notifications`, `whatsnew`, `sort`, `filter`, `settings`, `dismiss` |
| `shot --out PATH [--out …] [--wait S] [--window TITLE]` | `screencapture -x -o -l <CGWindowID>` of the app's largest layer-0 window only (or the one whose title contains `TITLE`, e.g. `Settings`) |
| `quit` | Debug quit notification → `NSApp.terminate` (SIGTERM fallback) |

- **Never capture the full screen** (the operator's private desktop): `shot` refuses without the app's window ID, which `tools/mac_window.swift` finds through `CGWindowListCopyWindowInfo` filtered to the app's PID. Captures need the terminal's Screen Recording permission (granted on this Mac as of 2026-10-02).
- `resize`, `command` and `quit` are Debug-only distributed notifications handled by `MacDebugHooks` (`apple/Sources/FestivalUI/Mac/MacDebugHooks.swift`): no Apple Events, so no Automation or Accessibility prompt. Release builds ignore them.
- A Debug `--size` launch skips the frame autosave so a saved frame cannot override it.
- Operator-facing shots use the live service with `--profile sfentonx` and go to `~/FestivalShowcase/native-mac/` ([strategy](../../testing/strategy.md)); never commit them.
- Pure parts are tested in `tools/tests/test_mac_app.py`.
