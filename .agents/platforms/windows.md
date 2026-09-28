# Windows architecture and performance

> **What:** WinUI 3 stack, the C#-vs-C++/WinRT decision and its evidence, build/perf tooling, host tooling and `tools/windows/uiwin.py`. **Read when:** working on or driving the Windows app (host `sfenton-primary`, reached via [windows-relay](../workflow/windows-relay.md)). Design: [design/windows.md](../design/windows.md); tests: [testing/windows.md](../testing/windows.md).

## Stack

- **C# / .NET 9 + WinUI 3, Windows App SDK 2.5.1**, unpackaged, self-contained, x64, min Windows 10 19041. C#/WinRT projection pinned to `10.0.26100.87` (trim/AOT-annotated).
- MVVM with CommunityToolkit.Mvvm. `Festival.Core` (UI-free, `net9.0`) holds `Data/` (request gate, client, wire models, caches, settings store), `Domain/` (instruments, songs pipeline, routes, settings, launch options, artwork policy) and `ViewModels/`. `Festival.App` holds XAML, controls and thin code-behind.
- System.Text.Json source generation everywhere (no reflection), so Release can be trimmed or NativeAOT-published.
- Service access: [service-safety.md](service-safety.md). The single gate is `RequestGate` (GET-only, rejects `X-API-Key`/`x-fst-selected-*`, 30 s deadline, maps 202/304/404/503 + `Retry-After` + freeze reason to `ServiceIssue`). `FestivalApiClient` bootstraps `/api/publication`, pins only when `readyForPinning && pinningEnabled`, reuses ETags within one publication, retries one `publication_changed` 409. `SocketsHttpHandler` has no disk cache; art never goes through `BitmapImage.UriSource` (which would use the WinINet cache).
- Routes: `AppRoute` records for every web route except the deprecated Manual; `AppRouteParser` parses web paths (deep links, `--route`). Routes carry IDs, not objects.
- Settings: `settings.json` in the app data folder (atomic temp-file replace, re-validated on load; corrupt → defaults). The selected player survives restarts. Online-only: no offline UX.
- App data folder (`Data/AppDataPaths.cs`): Release always `%LOCALAPPDATA%\FestivalScoreTracker`. **Debug** uses `FST_DEBUG_DATA_DIR` when set, else `%LOCALAPPDATA%\FestivalScoreTracker.Debug\<worktree>-<hash8>` derived from the build's git worktree, so parallel lanes never share settings, the selected profile, seen-state or `diagnostics.log`. `App.OnLaunched` configures it before any store resolves a path. `FST_SETTINGS_PATH` still overrides just the settings file.
- State-file registry (`Data/AppStateFiles.cs`): every persisted file (settings, first-run, notifications-seen, suggestions-filter, diagnostics log) is listed with its Settings-Reset behaviour; a feature that persists anything adds its file there and reads `AppStateFile.DefaultPath`. Reset rewrites `settings.json` in place (profile and song filters stay) and deletes `Delete`-scoped files (today `suggestions-filter.json`); the shell then drops the owning section's cached frame (`AppStateFile.Owner`) so it reloads from defaults.
- Don't disable background visuals just because focus moves to a game (the app may stay visible beside it); use data-saving/reduced-motion and measured occlusion policies. Don't adopt invented startup/memory limits or assume a notification-state API recognizes every game.

## Language decision: stay on C# (decided 2026-09-28)

Guidance: Microsoft recommends WinUI 3 for new desktop apps and supports both C# and C++/WinRT ([WinUI 3](https://learn.microsoft.com/en-us/windows/apps/winui/winui3/), [FAQ](https://learn.microsoft.com/en-us/windows/apps/get-started/windows-developer-faq)); the WinUI team's position is that C# with NativeAOT approaches C++ ([discussion #10328](https://github.com/microsoft/microsoft-ui-xaml/discussions/10328)). Rendering (XAML, DirectComposition, DWM) is native in both, so language only changes the managed-runtime floor.

Twin benchmark (`tools/windows/bench.ps1`: same window, label and full-window image with the same stepped composition zoom; medians of 5 runs, Release, Ryzen 7 9800X3D (16 threads), RTX 5090, 3840×2160 at 240 Hz):

| Variant | First frame | Private MB | Working set MB | CPU animated / static (one core) |
|---|---|---|---|---|
| C++/WinRT | 173 ms | 146.9 | 87.5 | ≤1% / 0.1% |
| C# NativeAOT | 182 ms | 150.9 | 92.4 | ≤1% / 0% |
| C# ReadyToRun | 214 ms | 153.7 | 104.4 | ≤1% / 0% |

Animated CPU for all three is at the resolution limit of `TotalProcessorTime` sampling (the C++ twin read 0% while visibly animating). Caveat: another app instance was idling on the host during this run.

Full app (Release, 1280×820 at 150%, live API, 30 s per scenario, `tools/windows/perf.ps1`):

| Scenario | Shell loaded (JIT / AOT) | App CPU, one core (JIT / AOT) | GPU 3D | Private / working set MB (JIT / AOT) |
|---|---|---|---|---|
| Songs, animated background | 717 / 333 ms | 4.2% / 2.7% | 1.0% | 243 / 235 · 223 / 192 |
| Songs, animated + list auto-scroll | 736 / 331 ms | 16.5% / 13.2% | 1.8% | 267 / 270 · 252 / 230 |
| Songs, static (reduced motion) | 357 / 294 ms | 0.0% / 0.0% | 0% | 238 / 238 · 216 / 193 |
| Song Detail (static cover) | 338 / 281 ms | 0.0% / 0.1% | 0% | 224 / 215 · 190 / 163 |
| Minimized | 342 / 287 ms | 0.1% / 0.0% | 0% | 241 / 238 · 215 / 193 |

Scroll frame delivery (UI thread, `--frame-stats`, which itself forces per-frame rendering): 240 fps, p50 4.2 ms, p95 4.6–4.7 ms, p99 5.0 (JIT) / 8.3 (AOT) ms, no frame over 33 ms. The songs list is ready 0.8–2.1 s after launch, dominated by the live catalogue fetch. Managed heap is only ~42 MB committed; the rest of the working set is native XAML, composition and image surfaces, which C++ pays too. Whole-app CPU stays under 0.3% of the 16-thread machine except while scrolling.

**Decision:** keep C#. C++/WinRT's advantage is ~10 MB private memory and a slightly lower working set; NativeAOT closes the startup gap (first frame within ~10 ms of C++), and animation cost is set by the compositor, not the language. Background motion costs were dominated by redrawing at display refresh, fixed by stepped keyframes (see [artwork-background](../controls/artwork-background/windows.md)). Re-open only if a measured scenario beside a game shows managed GC or JIT on the critical path.

**Ship configuration:** NativeAOT Release (`build.ps1 -Configuration Release -Aot`). Constraints: collections bound to XAML must have concrete `List<T>`/`ObservableCollection<T>` static types (CsWinRT generates vtables only for types it sees; an `IReadOnlyList<T>` backed by a collection expression threw `E_INVALIDARG` in `ItemsSource`), use `x:Bind` rather than `{Binding}`, and keep `CsWinRTAotOptimizerEnabled`.

## Tooling (`tools/windows/`, PowerShell 7)

| Script | Purpose |
|---|---|
| `build.ps1 [-Configuration Debug\|Release] [-Aot] [-Clean]` | Debug `dotnet build`; Release trimmed ReadyToRun publish → `windows/.artifacts/app/Release`; `-Aot` → `Release-aot` |
| `test.ps1 [-Coverage] [-Filter …]` | xUnit; `-Coverage` writes Cobertura and runs `tools/coverage_gate.py --language csharp` |
| `launch.ps1 [-Tab songs] [-Route /songs/<id>] [-Fixture] [-Configuration] [-Aot] [-ExtraArgs …]` | Start the app in the signed-in desktop session (works from SSH session 0) |
| `screenshot.ps1 -Out x.png [-Launch …] [-MaxKB 300]` | Capture the window, downscaled under the size budget |
| `perf.ps1 -Scenario animated\|scroll\|static\|noart\|minimized\|occluded\|detail\|idle-settings [-Aot] [-PresentMon]` | Startup markers, CPU (app + DWM via the `Process` counter, which needs no elevation), memory, GPU 3D, optional PresentMon → `windows/.artifacts/perf/*.json`. `occluded` covers the app with an opaque, non-topmost window and samples only after the app logs `occlusion-covered` |
| `bench.ps1 [-Runs 5]` | C++/WinRT vs C# twins (above) |

App launch flags, all builds (environment equivalents in parentheses are read in **Debug builds and automation launches only**): `--tab` (`FST_DEBUG_TAB`), `--route` (`FST_DEBUG_ROUTE`), `--base-url` loopback only (`FST_BASE_URL`), `--perf-log` (`FST_PERF_LOG`), `--width/--height`, `--reduce-motion`, `--no-art`, `--auto-scroll`, `--frame-stats`, `--drift-fps N`. Debug-only environment: `FST_DEBUG_DATA_DIR` (app data folder, above).

**Automation mode** (`Domain/AutomationLaunch.cs`): `--automation` or `FST_AUTOMATION=1` makes a launch honour every `FST_*` environment hook (deep links, loopback base URL, `FST_SETTINGS_PATH`, `FST_DEBUG_PROFILE`/`ANONYMOUS`, a per-worktree data folder), defaults first-run carousels to off (an explicit `--first-run` still wins) and presents no other UI unasked. Debug honours the request alone; **Release/NativeAOT honours it only when `fst-automation.marker` sits next to the executable**, which `uiwin.py launch` writes into publishes under `windows/.artifacts` (never elsewhere), so an installed build can't be switched by an environment variable. `build.ps1` republishes into a clean folder, so a fresh publish carries no marker. `uiwin.py launch` sets `FST_AUTOMATION=1` for every launch (`--no-automation` for user-default runs). Diagnostics (unhandled exceptions, binding and resource failures) go to `diagnostics.log` in the app data folder.

## Gotchas

- `TreatWarningsAsErrors` is on for all projects; trim-analysis warnings from framework assemblies are kept non-fatal (`ILLinkTreatWarningsAsErrors=false`).
- `dotnet publish -p:PublishAot=true` needs `vswhere` on `PATH` (`build.ps1` adds it).
- XAML compiler crash `WMC9999` ("Could not find any resources appropriate for the specified culture…") hides the real error. One cause: an `x:Name` inside an `x:DataType` template equal to a bound property of that type (e.g. `x:Name="BadgeText"` + `{x:Bind BadgeText}`). Bisect by stripping templates.
- Each feature's `[JsonSerializable]` types need their **own** `JsonSerializerContext` class (e.g. `SongsJsonContext`); attributed partials of one context collide in the source generator.
- `coverage.runsettings` excludes only `GeneratedCode`/`ExcludeFromCodeCoverage` attributes and `*.g.cs` files. Do **not** exclude `CompilerGeneratedAttribute`: that also drops every `async` state machine and lambda body (until 2026-09-28 ~2,200 lines, e.g. all of `FestivalApiClient`'s async reads, were silently unmeasured and async-only partials failed as "missing coverage").
- WinUI content is presented by DWM through DirectComposition: PresentMon attributes no presents to the app process, only to `dwm.exe`. Use app CPU, DWM CPU and GPU 3D engine counters; treat DWM present intervals as a system-wide signal.
- Handling `ContainerContentChanging` with `args.Handled = true` suppresses x:Bind template updates.
- Native `PackageReference` in a `.vcxproj` needs `ResolveNuGetPackages=false`.

## Host tooling on `sfenton-primary`

| Tool | Version / location |
|---|---|
| Windows SDK | 10.0.22621, 10.0.26100 |
| Visual Studio | 2022 + 2019 Community (use VS 2022 MSBuild for WinUI packaging tasks) |
| .NET SDK | 8.0.417, 9.0.304 |
| FlaUI (UIA3) | NuGet `FlaUI.UIA3` 5.0.0, used by the lab driver `tools/windows/FstUia` (net8.0-windows) |
| Axe.Windows | `AxeWindowsCLI` 2.4.2 at `~/.fst-tools/axe-windows/2.4.2/AxeWindowsCLI.exe`; NuGet `Axe.Windows` 2.4.2 for in-test scans |
| Accessibility Insights for Windows | 1.1.2924.01 (MSI) at `C:/Program Files (x86)/AccessibilityInsights/1.1/`; interactive tool |
| PresentMon | 2.6.0 console at `~/.fst-tools/presentmon/PresentMon-2.6.0-x64.exe`; `perf.ps1` also downloads it to `%LOCALAPPDATA%\FestivalTools` (ETW; needs admin or Performance Log Users, which `sfent` has) |
| Other | MSVC 14.44 (C++/WinRT builds), Python 3.13, WPR/xperf, `dotnet-counters` (global tool); host CPU Ryzen 7 9800X3D, GPU RTX 5090, display 240 Hz |
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
| `front [--isolate]` | Bring the target to the foreground and report `foreground` plus `covered_by` (windows above that still overlap it) |
| `close` | Close the window; kill it after 5 s |
| `perf-sample [--seconds N] [--presentmon] [--out f.json]` | CPU % of the machine, private working set, GPU engine % and dedicated GPU memory (mean/max/p95 via `Process V2`/`GPU Engine` counters); with `--presentmon`, frame count, FPS and frame-time summary. Works from session 0 and takes no lock |
| `scan <dir> [--scan-id ID]` | Axe.Windows rule scan of the target (in-process `Axe.Windows` 2.4.2 in `FstUia`): prints one line per error (rule, element, parent) and writes `<dir>/<ID>.json`; exit 1 on errors |
| `focus-order [--count N] [--reverse] [--out f.json]` | Presses Tab (Shift+Tab) N times and prints the focused element after each; `(repeat)` marks a possible trap, `(outside app)` focus that left the window |
| `status` | Sessions and desktop-lock state |

Targets: `--pid`, `--process <name>`, or the pid last launched from this worktree. Other lanes' app windows often sit exactly on top of yours (every launch is centred), so the driver foregrounds the target before every real-input step (`click`, `rightclick`, `type`, `key`, `scroll`) and `shot --mode screen`: a topmost/not-topmost bounce, then `SetForegroundWindow` with the foreground thread's input attached and a zero-length mouse move to lift the foreground lock, waiting until it is foreground. If it still isn't and something overlaps it, the step fails naming the covering windows instead of clicking into another lane's app. `--isolate` also minimizes overlapping windows of other same-named processes for the request and restores them (without activating) when it ends. UIA-pattern steps (`invoke`, `toggle`, `select`, `waitfor`) and `print` screenshots work while covered. Step paths in MSYS form (`shot:/c/...`) are translated to `C:/...` (Python alone resolved them to `C:\c\...`).

| Preset | Result (epx sizes scale with window DPI; centred in the work area, clamped to it) |
|---|---|
| `compact` / `medium` / `wide` | 500×800 / 900×700 / 1440×900 |
| `portrait-tablet` | 800×1280. It is clamped on a 1440-epx-tall desktop, and the tool prints a warning with the size achieved |
| `snap-left` / `snap-right` | Exact work-area halves via `SetWindowPos`. This is not a Snap Layouts snap, so the window doesn't know it is snapped |
| `maximized` | `ShowWindow(SW_MAXIMIZE)` |
| `full-screen` | Window covers the whole monitor, including the taskbar. True full screen (`AppWindow` FullScreen presenter) is app-side only |
| `WxH` | Any explicit epx size |

Tablet posture: Windows 11 has no tablet mode. The touch-optimized taskbar only appears on real 2-in-1 hardware when the keyboard detaches, so it can't be emulated here. Approximate a tablet with `portrait-tablet`, `full-screen` or `maximized` plus touch-sized targets; a true tablet pass needs real touch hardware (TODO(orchestrator)).

Drive steps: `click:`/`rightclick:`/`invoke:`/`toggle:`/`select:`/`expand:`/`collapse:`/`focus:`/`waitfor:<sel>[@secs]` with `sel` = `id=<AutomationId>`, `name=`, `class=` (clicks also accept window-relative `x,y`); `type:<text>`; `key:ctrl+shift+tab` (also `comma`, `period`, `minus`, `plus`); `scroll:[<sel>,]up|down|<clicks>`; `wait:<s>`; `shot:<png>[@screen]`; `tree:<txt>`; `resize:<preset>`; accessibility: `assertfocus:<sel>[@secs]` (fails unless focus matches), `tabwalk:<n>[,shift]` (records each focused element in the result's `focus`), `scan:<dir>/<id>` (Axe.Windows, result in `scans`). Tree lines also carry `heading=`, `landmark=`, `live=`, `accel=`, `access=`, `status=` and `desc=` when set.

The driver's `sysset` request (used only by `a11y_matrix.py`, inside its lock hold) switches contrast themes (`aquatic`, `desert`, `dusk`, `night-sky` via `SPI_SETHIGHCONTRAST` with the legacy scheme display names; the registry's `@themeui.dll,-85x` names are ignored), Animation effects (`SPI_SETCLIENTAREAANIMATION`), transparency (`EnableTransparency` + `ImmersiveColorSet` broadcast) and text size (`HKCU\Software\Microsoft\Accessibility\TextScaleFactor`, read by apps at launch), and returns the previous values so the runner restores them before releasing the lock. The `SystemParametersInfo` import must be the `W` entry point: the ANSI one silently garbles the scheme name and Windows applies the last-used contrast theme instead.
## Desktop lock

- A single `desktop` host lock (`tools/android/hostlock.py`, shared with the emulator lock design: an OS lock plus a FIFO ticket queue in `~/.fst-locks/`) serializes every GUI command across lanes. A hold lasts at most **300 s**; each driver request also has its own budget (120 s, or the rest of the hold for `drive`).
- The driver is rebuilt automatically when its sources change (cached by hash under `~/.fst-tools/fstuia/`). Request/response files live in `~/.fst-locks/uiwin/`.
- A driver crash is reported immediately (the task ended without a response); details are in the Application event log under `FstUia.exe`.
