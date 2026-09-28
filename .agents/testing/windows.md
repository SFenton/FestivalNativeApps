# Windows testing

> **What:** Windows coverage, UI-automation, accessibility and performance-test rules. **Read when:** writing or running Windows tests. Architecture, tooling and `uiwin.py`: [platforms/windows.md](../platforms/windows.md).

- Separate logic tests (testable view models) from XAML/UI automation; **95% / 90%** line coverage via Cobertura XML, which `tools/coverage_gate.py` parses and merges.
- Compare app/game impact in Release builds with representative workloads.
- No Windows coverage has been measured yet.

## UI automation

- **Proven on `sfenton-primary`:** from SSH (session 0), UIA queries, pattern invocation, keyboard and mouse input, window resizing and window screenshots all work through the one-shot interactive task hop in `tools/windows/uiwin.py`. They need the operator logged on at the console. Do not configure autologon without separate authorization.
- Drive the app only through `uiwin.py` so lanes serialize on the desktop lock (≤300 s per hold). It shares the operator's real desktop, so keep holds short and always `close` what you launch.
- Locate elements by `AutomationProperties.AutomationId` from the `product.json` test-ID registry (`drive … invoke:id=fst.songs.refresh`), never by pixel coordinates except as a last resort.
- Window-size evidence: capture each surface at `compact`, `medium`, `wide`, `snap-left`/`snap-right`, `maximized`, `full-screen` and `portrait-tablet`. The `.json` sidecar records px/epx size, DPI scale and monitor. Real touch and tablet posture need touch hardware.
- In-process automated UI tests (FlaUI in a test project) are the Windows lane's choice; `FstUia` is a lab driver, not a test framework.
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
