# Windows testing

> **What:** Windows unit/coverage, UI-automation, accessibility and performance-test rules and commands. **Read when:** writing or running Windows tests or changing `windows/**`. Architecture, tooling and `uiwin.py`: [platforms/windows.md](../platforms/windows.md).

- Separate logic tests (testable view models) from XAML/UI automation; **95% / 90%** line coverage via Cobertura XML, which `tools/coverage_gate.py` parses and merges.
- Compare app/game impact in Release builds with representative workloads.
- Installed-PWA reference (Edge app, same window presets, video + measured animations): `tools/windows/pwa.py`; findings and gaps in [pwa-reference/](pwa-reference/README.md).

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

- **Proven on `sfenton-music`:** from SSH (session 0), UIA queries, pattern invocation, keyboard and mouse input, window resizing and window screenshots all work through the one-shot interactive task hop in `tools/windows/uiwin.py`. They need the operator logged on at the console. Do not configure autologon without separate authorization.
- Drive the app only through `uiwin.py` so lanes serialize on the desktop lock (≤300 s per hold). It shares the operator's real desktop, so keep holds short and always `close` what you launch.
- Locate elements by `AutomationProperties.AutomationId` from the `product.json` test-ID registry (`drive … invoke:id=fst.nav.settings`), never by pixel coordinates except as a last resort.
- Window-size evidence: capture each surface at `compact`, `medium`, `wide`, `snap-left`/`snap-right`, `maximized`, `full-screen` and `portrait-tablet`. The `.json` sidecar records px/epx size, DPI scale and monitor. Real touch and tablet posture need touch hardware.
- In-process automated UI tests (FlaUI in a test project) are the Windows lane's choice; `FstUia` is a lab driver, not a test framework.
- Feature UI journeys live in `tools/windows/journeys/<feature>.steps` (`uiwin.py drive --steps-file`; every `waitfor` fails the run when its element never appears). `invoke`/`waitfor` need the element on screen: resize, `scroll` or `reveal:<sel>` first (`reveal` scrolls it into view through UIA ScrollItem, so it also works on a locked console where real input is denied). Fixture runs: start `tools/mock_service.py --port <free port>` and pass `--extra FST_BASE_URL=http://127.0.0.1:<port>/`.
- **Journey runner:** `python tools/windows/ui_journey.py tools/windows/journeys/<feature>.json [--only NAME] [--shots DIR] [--retries N]` automates the above for JSON journey lists (route + preset + steps): it starts the fixture service with a larger listen backlog, launches this worktree's Debug build per journey, saves `<name>-failure.png` on failure and reports a pass on retry as `FLAKY`. Deep-link routes lose everything after `&` in the desktop hop, so reach query-string routes by clicking through. Panels are not in the UIA control view: wait on text/controls, not `StackPanel` IDs.
- Rivals keeps its own runner, `python tools/windows/rivals_journey.py [--shots DIR] [--sizes compact,medium,wide]` (anonymized fixture via `tools/windows/rivals_fixture.py`, isolated `FST_SETTINGS_PATH`, screenshot + tree on failure; see [rivals/windows.md](../pages/rivals/windows.md)). Two fixture findings: .NET's pooled client intermittently hits `WSAECONNABORTED` against the stdlib HTTP/1.0 server (the app shows "You're offline") until responses carry `Connection: close`; and ItemsRepeater keeps recycled off-screen elements with their old AutomationIds, which the driver's first-match lookup can hit, so keep IDs unique per state (e.g. per tab).
- Global search keeps its own runner, `python tools/windows/search_journey.py [--axe]`: it wraps `ui_journey.py`, logs fixture request paths (no query strings) and fails on any `/api/bands/search`, isolates settings per journey (`--settings-path`, `--first-run=off`), passes routes as app arguments so `--exe` can target the Release/AOT build, and with `--axe` runs `tools/windows/axe_scan.ps1` (AxeWindowsCLI in the desktop session under the lock) on the Search page. Suggestion popups are separate windows: capture them with `shot:<png>@screen`.
- Tool unit tests: `python -m unittest discover -s tools/windows/tests` (and `tools/android/tests`).
- CI (`.github/workflows/native.yml`, on changes under `windows/`, `android/`, `tools/`, `contracts/`): `windows-latest` runs both tool suites and `tools/windows/test.ps1 -Coverage`; `ubuntu-latest` runs `android/gradlew testDebugUnitTest`. Lint workflow edits with `actionlint` (`~/.fst-tools/actionlint/actionlint.exe` on `sfenton-music`).
- **Release/AOT pass (2026-09-28, win-shell2):** bands, whats-new, search, songs (songs-player, shop, no-player, shop-hidden at compact/wide) and rivals no-player all pass on `--exe aot`. The outside-click journey was flaky on AOT until `DialogChrome.LightDismiss` hooked the backdrop on `Loaded` as well as `Opened`.
- **Release/AOT journeys:** every journey script takes `--exe debug|release|aot|<path>` (`tools/windows/journey_exe.py`); `uiwin.py launch` turns on [automation mode](../platforms/windows.md#tooling-toolswindows-powershell-7) so Release builds honour the same `FST_*` hooks. Run the ship build with e.g. `python tools/windows/ui_journey.py tools/windows/journeys/bands.json --exe aot`.
- Live driver regression (needs the console session; takes the desktop lock): `python tools/windows/tests/live_occluded_drive.py` launches two Debug instances at the same preset with separate `FST_DEBUG_DATA_DIR`s, mouse-clicks the **covered** one and asserts only it navigated, then checks `--isolate` minimizes and restores the covering window.
- Other lanes' app windows are usually on top of yours (all launches are centred). `drive` foregrounds the target before real input and fails with the covering windows' names if it can't; add `--isolate` to minimize other instances for the request. Prefer UIA-pattern steps (`invoke`, `toggle`, `select`), which work while covered.
- Debug launches from each worktree get their own app data folder (settings, selected profile, seen-state, diagnostics log); pass `--extra FST_DEBUG_DATA_DIR=<dir>` for a throwaway one (e.g. first-run journeys) instead of deleting shared files.
- At compact widths (<641 epx) the pane is LeftMinimal: open it with `invoke:id=PART_PaneToggleButton` before `invoke:id=fst.nav.*`.
## Accessibility

Per-page results (page × check × status) and open gaps: [windows-accessibility.md](windows-accessibility.md).

| Tool | Use |
|---|---|
| `python tools/windows/a11y_matrix.py --out DIR --scan --tabs 30 [--sizes …] [--only …]` | Every page in `tools/windows/journeys/a11y.json` (fixture service, isolated settings/app data, `--first-run=off`) at each size: screenshot, in-process Axe.Windows scan, Tab walk; `summary.md` + `results.json`. Exit 1 on any Axe error or load failure |
| `… --mode hc-aquatic\|hc-desert\|hc-dusk\|hc-night-sky\|text-150\|text-200\|text-225\|no-animations\|no-transparency\|app-reduced\|app-contrast` | Applies a system contrast theme / text size / Animation effects / transparency setting (or the in-app Reduce Motion + Disable Animated Artwork + Save Data, or More Contrast + Less Transparency) for each launch and restores the previous value before releasing the desktop lock |
| `… --pages tools/windows/journeys/a11y-keyboard.json` | Keyboard journeys: `assertfocus:` order (Songs toolbar → rows), Esc returns focus to the Sort/Filter/Profile buttons, Ctrl+1…7 / Ctrl+comma sections, Ctrl+E, Alt+Left from a text field |
| `uiwin.py scan` / `focus-order` / `tree` | One-off scan, Tab walk or tree (tree lines show heading/landmark/live/accelerator/access-key annotations) |
| Axe.Windows CLI 2.4.2 | `pwsh tools/windows/axe_scan.ps1 -ProcessId <pid> -OutputDirectory <dir>` (older path; the matrix uses the NuGet in `FstUia`) |
| Accessibility Insights for Windows 1.1.2924.01 | Interactive inspection and contrast checks by an operator |

- Axe scans every top-level window of the process (`_N_of_M.a11ytest` per window); `.a11ytest` files are zips whose `el.snapshot` holds per-element `ScanResults` (Status 3 = fail), readable in Accessibility Insights.
- "Focusable sibling elements must not have the same Name" fires wherever cards repeat rows (the same player atop several charts): wrap each card in `Controls/AccessibleGroup` (a named UIA `Group`), which also makes Narrator announce the card on entry.
- Buttons whose content is a panel (icon + `TextBlock`) get no UIA name: set `AutomationProperties.Name` (Axe "Name must not be null").
- System modes change the operator's real desktop. The runner writes the previous values to `~/.fst-locks/uiwin/a11y-sysset-restore.json` before changing anything and replays a leftover file at the start of its next hold, so a killed run cannot leave a contrast theme on for other lanes. Still prefer letting a mode run finish.
- `--exe debug|release|aot` runs the matrix on a publish in automation mode (same as `uiwin.py launch`).
- Text size is read by apps at launch; `text-*` modes set it before launching, so the running operator desktop only changes for new windows.

### Narrator manual script (operator)

Start Narrator (Ctrl+Win+Enter), launch a fixture build (`python tools/windows/a11y_matrix.py` launch flags, or `uiwin.py launch … --arg=--base-url --arg=http://127.0.0.1:<port>/`), then:

1. **Shell**: Tab from the page into the title bar. Expect "Search songs and players, edit" (search landmark), "Notifications, button", "Select a player profile, button". Caps+F7 → Landmarks lists "Page content" (main) and "Search". Ctrl+1…7 / Ctrl+comma switch sections; pane items read "Songs, Ctrl+1".
2. **Songs**: Ctrl+F → "Search songs, edit". Type "fix": after a pause Narrator says "2 songs". Tab → "Sort Songs, button, collapsed"; Enter opens the flyout, Esc closes it and focus returns to Sort. Down into rows: each row reads title, artist · year, shop state, chart statuses.
3. **Slow load**: with a throttled or stopped fixture, open Leaderboards → "Loading …" after ~1 s, then "<Title>, page 1 of N" on completion; stop the fixture and Retry → the service-status heading and message are announced once.
4. **Leaderboards / Rivals / Rival Detail**: Narrator enters each card as "<Lead>, group"; H / Shift+H move between Level 1/2 headings.
5. **Song Detail**: Paths opens a dialog; Esc closes it and focus returns to Paths. Alt+Left goes back (also from inside a text field).
6. **Profile flyout**: Enter on the profile button → focus in "Find Player"; results list reads each player; Esc returns to the button.
7. **Settings**: every toggle reads its label and state; "Reset" confirmation dialog traps focus until closed.
8. **First run** (`--first-run=force`): the dialog reads its page title; Esc closes it.

Added after win-a11y (win-shell2, win-detail2, win-next; run these too):

9. **Songs Filter** (with a player): Enter on Filter → "Filter Songs" heading. Tab reads "Global Score & FC Toggles, button, collapsed"; Enter expands and each switch reads its label ("Missing Scores, toggle switch, off"). "Individual Score & FC Toggles" is a heading; each chart group reads "Lead, button, collapsed". In "Selected Instrument Filters" the selector reads "Previous instrument", "Lead, toggle button", "Next instrument"; after choosing Lead, "Season / Percentile / Stars / Song Intensity, button, collapsed". Inside Percentile: "Select All Percentile, hyperlink", "Clear All Percentile, hyperlink", then "Top 1%, toggle switch, on". Star rows read "Gold Stars" … "1 Star"; intensity rows "Intensity 1 of 7" …. Each change updates the list behind the flyout (the gold Filter button tint is not announced). Esc returns focus to Filter.
10. **Two columns** (window ≥ 1100 epx page width): on Songs, Full Rankings, Band Rankings and All Rivals, Narrator reads the list, then the detail region ("Song details" / "Player profile" / "Band details" / "Rival details"); arrowing through All Rivals or Songs changes the detail without moving focus out of the list.
11. **Paths** on a song with Karaoke: the "Some Instruments Unavailable" dialog reads first (OK / Don't Show Again), then the Paths dialog; Esc returns focus to Paths.
12. **Song Detail Score History** (with a player): "Score History" heading, "Select a bar to see more score details."; the plot reads its chart summary; each bar is a toggle button reading its date, season, score and accuracy plus its pressed (selected) state, and keeps focus when toggled.

Added after win-unify (2026-09-29; run these too — fixture launch with a selected player, `tools/windows/journeys/boards.json` pages):

13. **Leaderboard rows (one design)**: on Song Detail, a song leaderboard, Leaderboards, Full Rankings and Band Rankings, Tab to a row and arrow Down/Up. Each row is **one** stop that reads the whole row ("Rank #2, Fixture Player 2, 99,800 points, 98% accuracy, full combo, 5 stars, button"); the selected player's row starts "Your rank, 1st." Caps+Right (scan mode) across a row must not read its rank, name, score or pill a second time. Enter opens the player (Full Rankings ≥ 1100 epx: the detail column changes and focus stays in the list).
14. **Pager**: on the song leaderboard (26 entries → 2 pages) Tab to the pager: "First page", "Previous page" (with its Ctrl+Left shortcut), then the badge ("Page 1 of 2"), "Next page" (Ctrl+Right), "Last page". With focus on a pager button, Right/Left/Home/End change page and Narrator announces "Page 2 of 2" (polite); when Next becomes unavailable focus moves to an enabled button instead of being lost. From a row, Ctrl+Right/Ctrl+Left page too. Full Rankings with one page shows no pager (nothing to read).
15. **Pinned "your rank" row**: when the selected player is on another page, the pinned row reads after the list and before the pager; "Jump to your page, button" precedes it.
16. **Over CHOpt Threshold** (Settings → Filter Invalid Scores on): Songs → Filter → expand "Global Score & FC Toggles": the fifth switch reads "Over CHOpt Threshold, toggle switch, off" with its description; each chart group adds "<Lead> Over CHOpt Threshold". Turn Filter Invalid Scores off: the switches are gone. With the switch on, the list count is announced ("0 songs" on the fixture).
17. **Score history rows** (Song Detail, with a player): each row is read once (date, "score …", "accuracy …", "full combo" when set, "season …", then "personal best" on the best row); Caps+Right does not re-read its parts.
18. **Contrast theme** (Settings → Accessibility → Contrast themes → Desert, then Night sky): Songs chips read the same as before; visually FC chips are Highlight-filled, scored chips have a thick ring and missing ones a thin gray ring; pills, Shop borders and Reset buttons use the theme's button/highlight colours. Narrator output must not change between themes.
19. **Settings headings**: H / Shift+H stops at "CHOpt Path Default View" and "CHOpt Text Path Column Order" (heading level 3).

Record anything Narrator skips or misreads in [windows-accessibility.md](windows-accessibility.md) under Open issues.

## Performance

- `uiwin.py perf-sample --pid <app> --seconds N --presentmon` measures CPU (% of all logical CPUs), private working set, GPU engine utilization and dedicated GPU memory (mean/max/p95), plus PresentMon 2.6 frame timing. Sample the app and the game separately with the same window, workload and duration.
- Performance counters and PresentMon work from session 0; only the app itself must run on the console desktop.

## Last measured

| Item | Value |
|---|---|
| Core tests | 913 passing |
| Core coverage (all folders, async bodies and lambdas measured) | 98.92% lines, 94.0% branches (logic 99.41%, UX 98.30%; 913 tests, 2026-09-28) |
| Screenshots | committed only from fixture mode ([strategy](strategy.md) keeps live screenshots out of the repo) |
