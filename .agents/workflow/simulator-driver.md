# Simulator driver

> **What:** scripting taps, swipes, scrolling, sheets and screenshots on the iPhone simulator from any lane, when `python3 tools/ios_sim.py shot` (install + launch + screenshot only) can't reach the state you need. **Read when:** you need to verify a drawer, sheet, gesture, scroll position or multi-step navigation flow that a single static screenshot can't show.

## Why this exists

`tools/ios_sim.py shot` installs the built app, launches it on a debug route (`FST_DEBUG_TAB`/`FST_DEBUG_ROUTE`), and screenshots — it cannot tap, scroll, swipe, type or open sheets. `tools/ios_sim.py drive` adds a small XCUITest (`apple/Apps/iOSUITests/DriverTests.swift`) that executes a scripted sequence of steps against the running app, still serialized through the same shared-simulator machinery as `shot`.

## Command

```
python3 tools/ios_sim.py drive [--device iphone|ipad|duo|<UDID>] \
    [--tab <FST_DEBUG_TAB>] [--route <FST_DEBUG_ROUTE>] [--env KEY=VALUE ...] \
    (--steps "verb:arg; verb:arg; ..." | --steps-file /path/to/steps.txt) \
    [--rebuild]
```

- `--tab`/`--route`/`--env` set the same app-launch environment as `shot` (`FST_DEBUG_TAB`, `FST_DEBUG_ROUTE`, and any extra `FST_*` key), applied when `DriverTests` launches the app.
- `--steps` is `;`-separated; `--steps-file` is newline-separated. Both may be given (file first, then inline); blank lines and `#` comments are dropped.
- First run builds the UI-test bundle with `build-for-testing` into `apple/DerivedData/lane-driver` (a few minutes, serialized on the build lock below); later runs skip straight to `test-without-building` (well under 30s) unless `Sources/`, `Apps/iOS/`, `Apps/iOSUITests/` or `project.yml` changed since the last build, or `--rebuild` is passed.
- On success, prints `ok: <path>` / `MISSING: <path>` for every `shot:`/`tree:` step so you know immediately whether an output actually landed.
- On failure, prints the last ~40 lines of the `xcodebuild` log and the `.xcresult` path; `DriverTests` itself also writes `/tmp/fst-driver-failure-<n>.png` and `.tree.txt` for the step that failed.

## Step vocabulary

Defined in `apple/Apps/iOSUITests/DriverTests.swift` (`DriverStep.parse`):

| Step | Effect |
|---|---|
| `tap:<id-or-label>` | Tap the first element whose accessibility identifier matches; falls back to an exact label match |
| `tapText:<label>` | Tap the first element with an exact label match |
| `tapXY:<x>,<y>` | Tap a point; both components `<= 1.0` are a normalized fraction of the window, otherwise device points |
| `swipe:<up\|down\|left\|right>[@id]` | Swipe the whole app, or one element when `@id` is given |
| `scrollTo:<id>` | Swipe up (up to 12 times) until the element exists and is hittable |
| `type:<text>` | Type into the current first responder |
| `wait:<seconds>` | Sleep |
| `waitFor:<id>` | Wait up to 20s for an element to exist |
| `back` | Tap the system `BackButton` (iPhone Duo puts it in the vertical bar), else the leading navigation bar button |
| `shot:<path>` | Write a full-screen PNG to an absolute host path |
| `tree:<path>` | Write `app.debugDescription` (the accessibility hierarchy) to an absolute host path — the fastest way to discover identifiers before scripting taps |
| `rotate:<portrait\|portraitUpsideDown\|landscapeLeft\|landscapeRight\|faceUp\|faceDown>` | Set device orientation (ignored by the iPhone Duo outer display) |

A `tree:` dump early in a script is the standard way to find an unknown identifier: run `drive` with just `wait:1; tree:/tmp/x.txt`, `grep` the file for `identifier:`, then script the real steps.

## Duo poses and panels

Xcode 27.1 has no `simctl`/XCTest fold or rotation for iPhone Duo (`rotate:` leaves the outer window portrait). The only controls are Device Hub's on-screen pose buttons, which `ios_sim.py` drives by **UI scripting** (operator decision, 2026-09-28): `osascript -l JavaScript` + System Events presses the button, then the lit-panel check verifies the result ([platforms/apple/duo.md](../platforms/apple/duo.md#simulator-alias-duo)).

```
python3 tools/ios_sim.py pose                               # prints folded | unfolded | unknown (lit panel)
python3 tools/ios_sim.py pose --set unfolded                # folded | unfolded | half | rotate-left | rotate-right
python3 tools/ios_sim.py pose --list-controls               # Device Hub accessibility tree (calibration)
python3 tools/ios_sim.py shot --device duo --pose half --set-pose --display auto --out /tmp/half.png
python3 tools/ios_sim.py shot --device duo --pose folded --set-pose --rotate right --out /tmp/rot.png
python3 tools/ios_sim.py drive --device duo --pose unfolded --steps "wait:3; shot:/tmp/inner.png"
python3 tools/ios_sim.py drive --device duo --pose folded --record /tmp/pop.mov --display outer --steps "…"
python3 tools/ios_sim.py shutdown --device duo              # leave the Duo off when done
```

- `--pose folded|unfolded|half` (`shot`, `drive`): checked right after boot inside the lock. `half` (partially open) runs on the inner panel, so it verifies like `unfolded`. A mismatch exits **3** with instructions; `--set-pose` presses the Device Hub control first (same lock hold, so another lane's shutdown cannot reset the pose in between).
- `--rotate left|right` (`shot`, repeatable): rotates through Device Hub after the pose check; verified by an unchanged pose plus a changed lit-panel image.
- `pose --set …`: same actions standalone. Exit codes: 3 pose not reached, 4 no permission, 5 no matching Device Hub control (run `--list-controls` and adjust `_POSE_KEYWORDS` in `tools/ios_sim.py`; the keywords are uncalibrated guesses until the first run with permission).
- `--display outer|inner|auto` (`shot`; `drive --record`): which panel is captured (`primary` / `primary-1`); `auto` is the lit one.
- `drive --record <file.mov>`: `simctl io recordVideo` for the whole run. `shot:` steps run only after XCUITest sees the app idle, so they never show push/pop or toolbar transitions; a recording does.
- Every command boots through `boot_exclusive`, which shuts down other FST devices first. A pose does not survive the Duo being shut down (it boots closed), so set it in the same command as the capture.

### Accessibility permission (UI scripting)

The scripting needs the macOS **Accessibility** permission for the *responsible* process (the app that started the agent or terminal, not `python3`/`osascript`), plus a one-time **Automation → System Events** approval. Without it every scripting command exits **4** before taking the simulator lock and prints the exact app, found with `responsibility_get_pid_responsible_for_pid`:

```
System Settings > Privacy & Security > Accessibility > "+" > <that .app> > switch on
```

Quit and reopen that app, then re-run and click OK on the "wants to control System Events" prompt. For Claude Code sessions launched by the Claude desktop app the responsible app is `~/Library/Application Support/Claude/claude-code/<version>/claude.app`. **Agents never change privacy settings**: no `tccutil`, no TCC database edits, no clicking the prompt for the operator.

## Examples

```
# Discover what's on screen, then open the drawer and confirm it renders.
python3 tools/ios_sim.py drive --tab settings \
    --steps "wait:1; tree:/tmp/tree.txt"
python3 tools/ios_sim.py drive --tab settings \
    --steps "tap:fst.shell.drawer.open; wait:1; shot:/tmp/drawer.png"

# Scroll a sheet and confirm a lower section appears.
python3 tools/ios_sim.py drive --tab settings \
    --steps "wait:1; swipe:up; wait:1; shot:/tmp/settings-scrolled.png"

# Open the profile sheet and search.
python3 tools/ios_sim.py drive \
    --steps "wait:1; tap:fst.profile.open; wait:1; tap:fst.profile.search; type:Fixture; shot:/tmp/search.png"
```

## How it works

`drive` builds `FestivalMobileUITests` once with `build-for-testing`, then re-runs only `DriverTests/testDrive` with `test-without-building -only-testing:FestivalMobileUITests/DriverTests/testDrive`. The step script is written to a temp file and passed to `xcodebuild` as `TEST_RUNNER_FST_DRIVER_STEPS_FILE`; xcodebuild's `TEST_RUNNER_` convention re-exposes it (prefix stripped) as `FST_DRIVER_STEPS_FILE` in the *test process's* own environment — the same mechanism carries `--tab`/`--route`/`--env` in as `FST_DEBUG_*`, which `DriverTests` then forwards onto `app.launchEnvironment` before `app.launch()`. The simulator shares the host filesystem, so `DriverTests` reads the step file and writes `shot:`/`tree:` outputs with plain absolute paths — no `simctl push`/`pull` needed.

## Locks

Two separate `flock`s, never held at once:

- `~/.fst-build.lock` — held only around the `xcodebuild build-for-testing` compile step (see `build_lock()` in `tools/ios_sim.py`; `build` and `lane_integrate.sh`'s `swift build` use the same lock). Released before touching the simulator.
- `~/.fst-sim.lock` — held for the `test-without-building` run, exactly like `shot`'s install/launch/screenshot sequence. Never call `simctl` or `xcodebuild test` directly against the shared simulator; always go through `tools/ios_sim.py`.

### 5-minute lock-hold rule (added after a real starvation incident)

One lane's `xcodebuild test-without-building` run held `~/.fst-sim.lock` for
10+ minutes covering many `-only-testing:` selectors in one invocation,
starving every other lane's queued `shot`/`drive`/`uitest`. Rules for any
script that takes the simulator lock:

- **Bound every single lock hold to ≤5 minutes.** `drive`'s `--timeout`
  defaults to 180s; `uitest`'s defaults to 300s. Both kill `xcodebuild` (via
  `subprocess.run`'s own timeout) and the app under test (`simctl terminate`)
  on expiry, so a hang can never pin the lock past the timeout.
- **Batch, don't bundle.** A long list of tests must run as several bounded
  `xcodebuild` invocations, each acquiring and then fully releasing the lock,
  rather than one invocation covering the whole list. `uitest` does this
  automatically via `--batch-size` (default 3 selectors per lock hold).
- Never write a one-off runner that calls `xcodebuild test`/`simctl` directly
  against the shared simulator to work around this — extend `tools/ios_sim.py`
  instead so every lane gets the same bounded-hold behavior.

## uitest (real XCUITest classes)

`python3 tools/ios_sim.py uitest --only <Class>[/<testMethod>] [--only ...]`
runs ordinary `XCTestCase` journey files under `apple/Apps/iOSUITests/`
(anything added there builds automatically — no project.yml change needed),
as opposed to `drive`'s single scripted `DriverTests/testDrive` step sequence.
It reuses `drive`'s build-for-testing product/DerivedData and staleness check,
then runs the given selectors in batches per the lock-hold rule above:

```
python3 tools/ios_sim.py uitest \
    --only ShellJourneyTests --only LeaderboardsJourneyTests \
    --only NotificationsJourneyTests --only FirstRunJourneyTests
```

Journey tests that need the loopback mock service start/assert it themselves
(same `FST_API_BASE_URL`/`FST_FIXTURE_SCENARIO` convention as
`FestivalMobileUITests.swift`); `uitest` does not manage
`tools/mock_service.py` for you — start it separately first.

## Limitations

- One step failure stops the whole script (steps are not retried or skippable).
- `type:` sends keys to whatever the OS considers the first responder; tap the target field first.
- `tapXY`/coordinate taps are a last resort — prefer `tap:<identifier>` so scripts survive layout changes.
- The XCUITest process itself only speaks the accessibility tree; anything invisible to accessibility (e.g. raw Metal/Canvas content) can't be asserted this way, only screenshotted.

## Known quirks

| Symptom | Resolution |
|---|---|
| `tap:<identifier>` doesn't reliably toggle a SwiftUI `Form` `Toggle` row (found by the Suggestions lane; `tapXY` worked around it) | Fixed in `DriverTests.swift`: `element(identifierOrLabel:)` now checks `app.switches[id]` first (a generic `.any` descendant match can resolve to a non-hittable container instead of the actual switch), and `.tap` taps a `.switch` element at its trailing-edge coordinate (`dx: 0.9`) instead of dead center, since a Form Toggle row's center can land on the label rather than the knob. No script changes needed going forward — plain `tap:<toggle-id>` now works. |
