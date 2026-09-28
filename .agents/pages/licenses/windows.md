# licenses — Windows notes

> **What:** how the Windows Licenses page lists the app's own NuGet packages and bundled assets. **Read when:** adding or updating a NuGet package in `windows/`, or changing Licenses on Windows. Behavior: [spec.md](spec.md).

## Implementation

- `tools/windows/licenses.py` reads `windows/Festival.App/obj/project.assets.json` (build first), keeps every runtime package plus the .NET runtime pack and the C#/WinRT Windows SDK projection, drops build-only packages (`Microsoft.Windows.SDK.BuildTools*`), reads each nuspec and license file from the NuGet cache, de-duplicates identical bodies and writes `windows/Festival.App/Assets/licenses.json`. `--check` fails when the committed manifest is stale.
- `Domain/Licenses.cs` parses and validates it (rows without a known text are dropped; malformed → empty); `LicenseManifest.BundledAssets` lists the first-party instrument icons. `ViewModels/LicensesViewModel.cs` sorts rows and validates HTTPS project URLs.
- `Pages/LicensesPage.xaml(.cs)`: card rows (`fst.licenses.row.<package id>`); a row opens a ContentDialog (`fst.licenses.detail`) with the project link and the full, selectable text. ContentDialog returns focus to the row. No network.

## Decisions

- Microsoft Software License Terms (Windows App SDK, Windows ML) and the WebView2 BSD text are shown verbatim; the Windows SDK projection only links its terms (the package ships none).
- **Run `python tools/windows/licenses.py` in the same commit as any package change.**

## Open

- `--check` is not wired into CI or `test.ps1` yet (TODO(orchestrator)).
