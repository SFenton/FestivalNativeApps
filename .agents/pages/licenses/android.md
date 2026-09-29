# Licenses — Android notes

> **What:** how the Android Licenses page lists the app's own release dependencies. **Read when:** adding or updating any Android dependency, or changing `ui/settings/LicensesScreen.kt`. Behavior: [spec.md](spec.md); references: [ios.md](ios.md), [windows.md](windows.md).

## Implementation

- `tools/android/licenses.py` runs `:app:dependencies --configuration releaseRuntimeClasspath`, keeps every resolved runtime module (drops `(c)`/`(n)` entries, BOMs, and Kotlin Multiplatform root modules whose `-android`/`-jvm` artifact ships), reads each POM and its parents, maps licenses to SPDX and writes `android/app/src/main/assets/licenses.json` with one verbatim text per SPDX ID from `tools/android/license-texts/`. `--check` fails when the committed manifest is stale; `--deps-file` reads a saved tree.
- Gradle keeps resolved POMs only in its binary metadata store, so the tool falls back to a read-only download from Google Maven / Maven Central, cached under `android/build/license-poms/` (gitignored).
- `core/licenses/Licenses.kt`: `LicenseManifest.parse` (malformed → empty; rows without a known text dropped; non-HTTPS project URLs removed; sorted by name). No Bundled Assets section or iconography entry (operator batch 6.17).
- Layout: a sheet on narrow pages; **list-detail** (list | license text) at ≥ 960 dp page width or across a separating vertical hinge (book posture), so no card straddles the fold.
- `ui/settings/LicensesScreen.kt` (web `LicensesPage`, batch 6.17): the shared load gate (spinner → stagger), then one glass card of rows centred at 840 dp — each row (`fst.licenses.row.<group>:<artifact>`) is a card segment with name, coordinates, an SPDX badge (surface-muted pill) and a chevron, hairlines between rows. A row opens a modal bottom sheet (`fst.licenses.detail`, kept below the status bar) with the project link, the full selectable monospace text (`fst.licenses.text`) and a **centred Close** (`fst.licenses.close`) in a footer. No network.

## Decisions

- Only two license families ship today: Apache-2.0 (111 modules) and BSD-3-Clause (DataStore's shaded protobuf, `datastore-preferences-external-protobuf`). `BSD-3-Clause.txt` is protobuf's own LICENSE; a future BSD-3 dependency with a different copyright holder needs its own text.
- **Run `python tools/android/licenses.py` in the same commit as any dependency change.**

## Open

- `--check` is not wired into CI (TODO(orchestrator)).
