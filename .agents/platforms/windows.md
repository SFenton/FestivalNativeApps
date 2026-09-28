# Windows architecture and performance

> **What:** WinUI 3 architecture, game-alongside performance rules, host tooling and `tools/windows/uiwin.py`. **Read when:** working on or driving the Windows app (host `sfenton-primary`, reached via [windows-relay](../workflow/windows-relay.md)). Design: [design/windows.md](../design/windows.md); tests: [testing/windows.md](../testing/windows.md).

- C#/.NET + WinUI 3 (Windows App SDK), `NavigationView`, virtualized lists, testable view models, composition-thread animations. [Microsoft recommends WinUI 3](https://learn.microsoft.com/en-us/windows/apps/get-started/) for new native desktop apps.
- **C# vs C++/WinRT is provisional** until the same Release screen is profiled with artwork motion, a large list and a modal beside a representative game: measure app and game CPU/GPU, memory, startup, GC/frame delivery and responsiveness. Don't adopt invented startup/memory limits or assume a notification-state API recognizes every game.
- Don't disable background visuals just because focus moves to a game (the app may stay visible beside it); use data-saving/reduced-motion and measured occlusion policies.
- Debug launches: `uiwin.py launch` passes `FST_DEBUG_TAB`, `FST_DEBUG_ROUTE` and any `--extra FST_*=…` as **environment variables** (same names as Apple/Android). The unpackaged app should read them in Debug builds only.

## Host tooling on `sfenton-primary`

| Tool | Version / location |
|---|---|
| Windows SDK | 10.0.22621, 10.0.26100 |
| Visual Studio | 2022 + 2019 Community (use VS 2022 MSBuild for WinUI packaging tasks) |
| .NET SDK | 8.0.417, 9.0.304 |
| FlaUI (UIA3) | NuGet `FlaUI.UIA3` 5.0.0, used by the lab driver `tools/windows/FstUia` (net8.0-windows) |
| Axe.Windows | `AxeWindowsCLI` 2.4.2 at `~/.fst-tools/axe-windows/2.4.2/AxeWindowsCLI.exe`; NuGet `Axe.Windows` 2.4.2 for in-test scans |
| Accessibility Insights for Windows | 1.1.2924.01 (MSI) at `C:/Program Files (x86)/AccessibilityInsights/1.1/`; interactive tool |
| PresentMon | 2.6.0 console at `~/.fst-tools/presentmon/PresentMon-2.6.0-x64.exe` (ETW; needs admin or Performance Log Users, which `sfent` has) |
| WinAppDriver | Not installed: unmaintained since 1.2.1 and requires Developer Mode; FlaUI covers UIA |

The console session has a 3840×2160 primary monitor at 150% scale (a 2560×1440 effective desktop), plus a second monitor. No GitHub credentials over SSH; history moves via `tools/win_relay.py`.

## Desktop sessions

Lanes run over SSH in non-interactive **session 0**, where no windows, UIA tree or screenshots exist. The operator `sfent` is logged on at the console (session 1). `uiwin.py` runs each driver request in session 1 through a one-shot `schtasks /Create … /IT` task named `FST_UiWin_<token>`, deleting the task immediately afterwards. It configures no autologon and no persistent task. If nobody is logged on at the console, GUI commands fail with "no interactive console session".

## `tools/windows/uiwin.py`

| Command | Effect |
|---|---|
| `launch <exe> [--tab] [--route] [--extra K=V] [--arg=…] [--preset P] [--shot out.png]` | Start the app with the debug environment and wait for its top-level window. Records the pid as this worktree's default target |
| `window` | Describe the window: bounds (px), size in epx, DPI scale, state, monitor and work area |
| `resize <preset\|WxH>` | Apply a window preset (below) |
| `shot <out.png> [--mode print\|screen]` | Window-only PNG plus a `.json` sidecar. `print` uses `PrintWindow(PW_RENDERFULLCONTENT)` and works when occluded; `screen` captures composited pixels after bringing the window to the foreground |
| `tree [out.txt] [--depth]` | UIA control-view tree: type, name, AutomationId, class, rectangle, focus/enabled flags, supported patterns |
| `drive --steps "…" [--steps-file]` | Scripted UIA steps (below) |
| `close` | Close the window; kill it after 5 s |
| `perf-sample [--seconds N] [--presentmon] [--out f.json]` | CPU % of the machine, private working set, GPU engine % and dedicated GPU memory (mean/max/p95 via `Process V2`/`GPU Engine` counters); with `--presentmon`, frame count, FPS and frame-time summary. Works from session 0 and takes no lock |
| `status` | Sessions and desktop-lock state |

Targets: `--pid`, `--process <name>`, or the pid last launched from this worktree.

| Preset | Result (epx sizes scale with window DPI; centred in the work area, clamped to it) |
|---|---|
| `compact` / `medium` / `wide` | 500×800 / 900×700 / 1440×900 |
| `portrait-tablet` | 800×1280. It is clamped on a 1440-epx-tall desktop, and the tool prints a warning with the size achieved |
| `snap-left` / `snap-right` | Exact work-area halves via `SetWindowPos`. This is not a Snap Layouts snap, so the window doesn't know it is snapped |
| `maximized` | `ShowWindow(SW_MAXIMIZE)` |
| `full-screen` | Window covers the whole monitor, including the taskbar. True full screen (`AppWindow` FullScreen presenter) is app-side only |
| `WxH` | Any explicit epx size |

Tablet posture: Windows 11 has no tablet mode. The touch-optimized taskbar only appears on real 2-in-1 hardware when the keyboard detaches, so it can't be emulated here. Approximate a tablet with `portrait-tablet`, `full-screen` or `maximized` plus touch-sized targets; a true tablet pass needs real touch hardware (TODO(orchestrator)).

Drive steps: `click:`/`rightclick:`/`invoke:`/`toggle:`/`select:`/`expand:`/`collapse:`/`focus:`/`waitfor:<sel>[@secs]` with `sel` = `id=<AutomationId>`, `name=`, `class=` (clicks also accept window-relative `x,y`); `type:<text>`; `key:ctrl+shift+tab`; `scroll:[<sel>,]up|down|<clicks>`; `wait:<s>`; `shot:<png>[@screen]`; `tree:<txt>`; `resize:<preset>`.

## Desktop lock

- A single `desktop` host lock (`tools/android/hostlock.py`, shared with the emulator lock design: an OS lock plus a FIFO ticket queue in `~/.fst-locks/`) serializes every GUI command across lanes. A hold lasts at most **300 s**; each driver request also has its own budget (120 s, or the rest of the hold for `drive`).
- The driver is rebuilt automatically when its sources change (cached by hash under `~/.fst-tools/fstuia/`). Request/response files live in `~/.fst-locks/uiwin/`.
- A driver crash is reported immediately (the task ended without a response); details are in the Application event log under `FstUia.exe`.
