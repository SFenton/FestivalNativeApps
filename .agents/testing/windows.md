# Windows testing

> **What:** Windows unit/coverage, UI-automation, accessibility and performance-test rules and commands. **Read when:** writing or running Windows tests or changing `windows/**`. Architecture, tooling and `uiwin.py`: [platforms/windows.md](../platforms/windows.md).

- Separate logic tests (testable view models) from XAML/UI automation; **95% / 90%** line coverage via Cobertura XML, which `tools/coverage_gate.py` parses and merges.
- Compare app/game impact in Release builds with representative workloads.

## Layers

| Layer | Where | Command |
|---|---|---|
| Logic + view models | `windows/Festival.Core.Tests` (xUnit, fake `HttpMessageHandler`, `FakeTimeProvider`) | `pwsh tools/windows/test.ps1` |
| Coverage | coverlet Cobertura → `windows/.artifacts/coverage/coverage.cobertura.xml`, gated by `tools/coverage_gate.py --language csharp` | `pwsh tools/windows/test.ps1 -Coverage` |
| Visual smoke | Screenshot of the running app | `pwsh tools/windows/screenshot.ps1 -Launch -Tab songs -Out …` |
| Perf | Release/AOT scenarios | `pwsh tools/windows/perf.ps1`, `bench.ps1` |

- `contracts/coverage-rules.json` classifies C# by folder: `windows/**/Data/*.cs` and `Domain/*.cs` are **logic (95%)**, `Views/*.cs` and `ViewModels/*.cs` are **UX (90%)**. Keep new Core files in those folders (flat) so the gate sees them.
- Fixtures: tests reuse `contracts/fixtures/{songs-demo,publication}.json`; manual fixture runs use `tools/mock_service.py` (`launch.ps1 -Fixture`). No production payloads in tests.
- View-model timing uses `TimeProvider`; tests advance `FakeTimeProvider` (search debounce, profile search, scrape-freeze countdown and backoff).
- XAML code-behind (`windows/Festival.App`) has no unit coverage; it is kept thin. UI automation (FlaUI/UIA) is not set up in this lane yet; the device-lab lane's `uiwin.py` drives the app by the `fst.*` AutomationIds.

## Desktop session

SSH runs in session 0 (no desktop). `_common.ps1` runs GUI work through a one-shot `schtasks /IT` task in the signed-in console session (no stored credentials), and every hop holds the shared FIFO `desktop` lock via `tools/windows/desktop_lock.py`, so it queues with `uiwin.py` and other lanes. From session 0 `Process.MainWindowHandle` is always 0, so window lookups happen inside that task. `PrintWindow(PW_RENDERFULLCONTENT)` captures the DirectComposition content; the capture process must be DPI-aware. From Git Bash, prefix route arguments with `MSYS_NO_PATHCONV=1` or `/songs/…` becomes a Windows path.

## UI automation

- **Proven on `sfenton-primary`:** from SSH (session 0), UIA queries, pattern invocation, keyboard and mouse input, window resizing and window screenshots all work through the one-shot interactive task hop in `tools/windows/uiwin.py`. They need the operator logged on at the console. Do not configure autologon without separate authorization.
- Drive the app only through `uiwin.py` so lanes serialize on the desktop lock (≤300 s per hold). It shares the operator's real desktop, so keep holds short and always `close` what you launch.
- Locate elements by `AutomationProperties.AutomationId` from the `product.json` test-ID registry (`drive … invoke:id=fst.nav.settings`), never by pixel coordinates except as a last resort.
- Window-size evidence: capture each surface at `compact`, `medium`, `wide`, `snap-left`/`snap-right`, `maximized`, `full-screen` and `portrait-tablet`. The `.json` sidecar records px/epx size, DPI scale and monitor. Real touch and tablet posture need touch hardware.
- In-process automated UI tests (FlaUI in a test project) are the Windows lane's choice; `FstUia` is a lab driver, not a test framework.
- Feature UI journeys live in `tools/windows/journeys/<feature>.steps` (`uiwin.py drive --steps-file`; every `waitfor` fails the run when its element never appears). `invoke`/`waitfor` need the element on screen: resize or `scroll` first. Fixture runs: start `tools/mock_service.py --port <free port>` and pass `--extra FST_BASE_URL=http://127.0.0.1:<port>/` (its listen backlog is 5, so bursts of parallel reads can be refused).
- **Journey runner:** `python tools/windows/ui_journey.py tools/windows/journeys/<feature>.json [--only NAME] [--shots DIR] [--retries N]` automates the above for JSON journey lists (route + preset + steps): it starts the fixture service with a larger listen backlog, launches this worktree's Debug build per journey, saves `<name>-failure.png` on failure and reports a pass on retry as `FLAKY`. Deep-link routes lose everything after `&` in the desktop hop, so reach query-string routes by clicking through. Panels are not in the UIA control view: wait on text/controls, not `StackPanel` IDs.
- Tool unit tests: `python -m unittest discover -s tools/windows/tests` (not yet part of CI's `tools/tests` discovery; TODO(orchestrator): wire in).
## Accessibility

| Tool | Use |
|---|---|
| Axe.Windows CLI 2.4.2 | Automated rule scan of a running app: `AxeWindowsCLI.exe --processid <pid> --outputdirectory <dir>`. It must run in the console session, so hop through the desktop lock (TODO(orchestrator): add a `uiwin.py scan` wrapper once the app launches) |
| `Axe.Windows` NuGet 2.4.2 | The same rules inside UI tests |
| Accessibility Insights for Windows 1.1.2924.01 | Interactive inspection and tab-stop/contrast checks by an operator |
| `uiwin.py tree` | Name/AutomationId/pattern/focusability audit and reading order (control-view order) |
| Narrator | No scripted driver; screen-reader flows need an interactive operator pass (TODO(orchestrator)) |
## Performance

- `uiwin.py perf-sample --pid <app> --seconds N --presentmon` measures CPU (% of all logical CPUs), private working set, GPU engine utilization and dedicated GPU memory (mean/max/p95), plus PresentMon 2.6 frame timing. Sample the app and the game separately with the same window, workload and duration.
- Performance counters and PresentMon work from session 0; only the app itself must run on the console desktop.

## Last measured

| Item | Value |
|---|---|
| Core tests | 629 passing |
| Core coverage (all folders) | 99.6% lines, 96.3% branches |
| Screenshots | committed only from fixture mode ([strategy](strategy.md) keeps live screenshots out of the repo) |
