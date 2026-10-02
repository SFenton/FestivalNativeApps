# licenses — Windows notes

> **What:** how the Windows Licenses page lists the app's own third-party NuGet packages. **Read when:** adding or updating a NuGet package in `windows/`, or changing Licenses on Windows. Behavior: [spec.md](spec.md).

## Implementation

- `tools/windows/licenses.py` reads `windows/Festival.App/obj/project.assets.json` (build first), keeps every runtime package plus the .NET runtime pack and the C#/WinRT Windows SDK projection, drops build-only packages (`Microsoft.Windows.SDK.BuildTools*`), reads each nuspec and license file from the NuGet cache, de-duplicates identical bodies and writes `windows/Festival.App/Assets/licenses.json`. `--check` fails when the committed manifest is stale.
- `Domain/Licenses.cs` parses and validates it (rows without a known text are dropped; malformed → empty). No bundled-asset or Iconography entries (operator rule in [spec.md](spec.md), batch 6.17). `ViewModels/LicensesViewModel.cs` sorts rows and validates HTTPS project URLs.
- `Pages/LicensesPage.xaml(.cs)`: one card (web `FrostedCard`) of rows (`fst.licenses.row.<package id>`) with separators, license badge and chevron; transparent rows with a visible hover fill (card-scoped lightweight styling — a card-coloured row background turned see-through on hover). Centred 1100-epx column: the column sits in a Grid inside the ScrollViewer, because a `MaxWidth` child placed directly in the ScrollViewer was centred in a wider extent and clipped. A row opens the shared `FestivalDialog` (`fst.licenses.detail`, title `Name · License`) with the project link, the full selectable text and the dialog's standard **Close** spanning the command row, centred (`fst.licenses.detail.close`; issue #23 replaced the in-content button; Esc and an outside click also close). Focus returns to the row. No network.

## Decisions

- Microsoft Software License Terms (Windows App SDK, Windows ML) and the WebView2 BSD text are shown verbatim; the Windows SDK projection only links its terms (the package ships none).
- **Run `python tools/windows/licenses.py` in the same commit as any package change.**

## Open

- `--check` is not wired into CI or `test.ps1` yet (TODO(orchestrator)).
