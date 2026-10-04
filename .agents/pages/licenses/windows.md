# licenses — Windows notes

> **What:** how the Windows Licenses page lists the app's own third-party NuGet packages. **Read when:** adding or updating a NuGet package in `windows/`, or changing Licenses on Windows. Behavior: [spec.md](spec.md).

## Implementation

- `tools/windows/licenses.py` reads `windows/Festival.App/obj/project.assets.json` (build first), keeps every runtime package plus the .NET runtime pack and the C#/WinRT Windows SDK projection, drops build-only packages (`Microsoft.Windows.SDK.BuildTools*`), reads each nuspec and license file from the NuGet cache, de-duplicates identical bodies and writes `windows/Festival.App/Assets/licenses.json`. `--check` fails when the committed manifest is stale.
- `Domain/Licenses.cs` parses and validates it (rows without a known text are dropped; malformed → empty). No bundled-asset or Iconography entries (operator rule in [spec.md](spec.md), batch 6.17). `ViewModels/LicensesViewModel.cs` sorts rows and validates HTTPS project URLs.
- `Pages/LicensesPage.xaml(.cs)`: one card (web `FrostedCard`) of rows (`fst.licenses.row.<package id>`) with separators, license badge and chevron; transparent rows with a visible hover fill (card-scoped lightweight styling — a card-coloured row background turned see-through on hover). Row hover/press/separator use the shared `FSTRow*Brush` resources (system colours under a contrast theme; issue #215 replaced hard-coded `#14FFFFFF` separators that vanished in HC Desert and a fixed white hover foreground), and the name, subtitle and chevron inherit the button foreground so hover/press keep the theme's Highlight/HighlightText pair. Names wrap rather than truncate; when the row content is narrower than `LicenseRowLayout.StackWidth` (440 epx) × the Windows text size, the badge moves under the name (`OnRowContentSizeChanged`; Fluent "reposition"). Centred 1100-epx column: the column sits in a Grid inside the ScrollViewer, because a `MaxWidth` child placed directly in the ScrollViewer was centred in a wider extent and clipped. A row opens the shared `FestivalDialog` (`fst.licenses.detail`, title `Name · License`) with the project link, the full selectable text and the dialog's standard **Close** spanning the command row, centred (`fst.licenses.detail.close`; issue #23 replaced the in-content button; Esc and an outside click also close). The text scroller (`fst.licenses.detail.text`, Narrator "<name> license text") is a tab stop focused on open, first in Tab order (text → project link → Close), so arrow and Page keys scroll it (issue #215: before, Tab cycled link ↔ Close and keyboard users could not read past the first screen); its height is the window minus 320 epx, clamped 160–420 (`LicenseRowLayout.DetailTextHeight`), and the text is inset 8,4,16,4 so the focus rectangle and scrollbar clear it; the project link is `fst.licenses.detail.link` (Narrator "Project page for <name>"). Focus returns to the row. No network.
- The `.NET Runtime` row shows its servicing band (`9.0.x`): the SDK picks the runtime pack's patch and CI installs the latest `9.0.x`, so an exact patch made `--check` stale on every host with a different SDK (issue #215: 9.0.8 committed vs 9.0.20 on the Windows host).

## Validation (issue #215, 2026-10-03)

UIA journeys: `tools/windows/journeys/licenses.json` with `a11y_matrix.py --pages … --scan` (`licenses-list`, `licenses-keyboard` — arrow keys between rows, Enter opens, focus on the text, Tab to link and Close, Esc and Close return focus to the row — `licenses-detail` and `licenses-last-row`). The detail and last-row journeys move with Down arrows from the first row instead of using `scrollinto`. Keyboard focus brings each row fully into view and realizes rows the `ItemsRepeater` has not created yet. WinUI reports `IsOffscreen=false` for a row clipped at the window's bottom edge, so `scrollinto` returns early, and Axe then flags the row's zero-height bounds. Unit tests: `SettingsPageTests` `Licenses_*` and `LicenseRowLayout_*`; `tools/windows/tests/test_licenses.py`.

| Configuration | Result |
|---|---|
| Compact / medium / wide | Pass, Axe 0; the badge stacks at compact (and at medium only at large text); 21/23/23 tab stops (shell + 17 rows); dialog 3 stops |
| Maximized, snapped left/right | Pass (live service); snapped half-width matches medium/compact layout |
| HC Desert, HC Aquatic | Pass, Axe 0; separators and focus visible (were invisible in Desert before) |
| Text 200% | Pass at all three widths; names wrap, badge stacks (names were truncated before) |
| Display 100% / 150% | Pass, Axe 0 |
| Light theme | App stays dark by design ([design/windows.md](../../design/windows.md)); page legible |
| Keyboard only | Pass (journey above); license text scrolls with Page Down (live run) |

## Decisions

- Microsoft Software License Terms (Windows App SDK, Windows ML) and the WebView2 BSD text are shown verbatim; the Windows SDK projection only links its terms (the package ships none).
- **Run `python tools/windows/licenses.py` in the same commit as any package change.**

## Open

- `--check` is not wired into CI or `test.ps1` yet (TODO(orchestrator)).
