# Licenses — Android notes

> **What:** how the Android Licenses page lists the app's own release dependencies. **Read when:** adding or updating any Android dependency, or changing `ui/settings/LicensesScreen.kt`. Behavior: [spec.md](spec.md); references: [ios.md](ios.md), [windows.md](windows.md).

## Implementation

- `tools/android/licenses.py` runs `:app:dependencies --configuration releaseRuntimeClasspath`, keeps every resolved runtime module (drops `(c)`/`(n)` entries, BOMs, and Kotlin Multiplatform root modules whose `-android`/`-jvm` artifact ships), reads each POM and its parents, maps licenses to SPDX and writes `android/app/src/main/assets/licenses.json` with one verbatim text per SPDX ID from `tools/android/license-texts/`. `--check` fails when the committed manifest is stale; `--deps-file` reads a saved tree.
- Gradle keeps resolved POMs only in its binary metadata store, so the tool falls back to a read-only download from Google Maven / Maven Central, cached under `android/build/license-poms/` (gitignored).
- `core/licenses/Licenses.kt`: `LicenseManifest.parse` (malformed → empty; rows without a known text dropped; non-HTTPS project URLs removed; sorted by name). No Bundled Assets section or iconography entry (operator batch 6.17).
- Layout: a sheet on compact and medium windows; **list-detail** (list | license text) on the app's shared list-detail rule, `AdaptiveLayoutPolicy.showsTwoPanes` (as Songs): an expanded window (≥ 840 dp window width, measured in text-scaled dp from 130% text) or a separating vertical hinge (book posture), so no card straddles the fold. The page used its own 960 dp *page*-width threshold until issue #122, which left the flat unfolded book fold (852 dp window, ~760 dp page beside the rail) with a modal sheet across the fold.
- Rows at large text (≥ 130%): the SPDX badge (`fst.licenses.badge`) stacks under the coordinates with no width cap and may wrap; at 100% it stays inline, capped at 140 dp. Inline at 200% it truncated to "Apache-…" and squeezed the name column until coordinates broke mid-token (issue #122).
- `LicensesContent(manifest, wide, hinge)` is the layout-only composable so tests can drive the hinge split without WindowManager fakes.
- The open package (`rememberSaveable`) survives a tablet rotation across the shell's rail ↔ permanent-drawer boundary: `FestivalShell` composes its page tree through one `movableContentOf`, so switching chrome branches moves the NavHost instead of rebuilding it. Before issue #122, rotating FST_Tablet from portrait (rail, sheet open) to landscape (permanent drawer) reset the page to the first package. Test: `ui/ShellLayoutStateUiTest`.
- TalkBack: each row is one merged button that reads its visible texts once ("Activity Compose. Maven · androidx.activity:activity-compose 1.10.1. Apache-2.0. Button"). Rows carry `selected` only in list-detail, where a row stays highlighted; in the single-pane sheet layout they have no selection state. Before issue #122 a custom row `contentDescription` was read *and* the merged child texts after it, and single-pane rows announced "Not selected".
- `ui/settings/LicensesScreen.kt` (web `LicensesPage`, batch 6.17): the shared load gate (spinner → stagger), then one glass card of rows centred at 840 dp — each row (`fst.licenses.row.<group>:<artifact>`) is a card segment with name, coordinates, an SPDX badge (surface-muted pill) and a chevron, hairlines between rows. A row opens the shared `FestivalModalSheet` (`fst.licenses.detail`, kept below the status bar) headed by the package name and the standard Close icon button (`fst.licenses.close`; issue #23 replaced the footer Close), with the project link and the full selectable monospace text (`fst.licenses.text`). No network.

## Decisions

- Only two license families ship today: Apache-2.0 (111 modules) and BSD-3-Clause (DataStore's shaded protobuf, `datastore-preferences-external-protobuf`). `BSD-3-Clause.txt` is protobuf's own LICENSE; a future BSD-3 dependency with a different copyright holder needs its own text.
- **Run `python tools/android/licenses.py` in the same commit as any dependency change.**

## Validation (issue #122, live service)

Debug build, keyless public origin (the page itself makes no network call). Robolectric `settings/LicensesScreenUiTest` covers the compact sheet, large-text stacking, medium, expanded and hinge-split list-detail states, and selection. `ui/ShellLayoutStateUiTest` covers rail ↔ permanent-drawer state.

| Configuration | Result |
|---|---|
| FST_Phone portrait / landscape, font 1.0 / 2.0 | OK after the fix. At 2.0 the inline badge truncated to "Apache-…" and coordinates broke mid-token. Now the badge stacks under the coordinates. Sheet opens below the status bar, Close works. |
| FST_Tablet landscape / portrait, font 1.0 / 2.0 | Landscape is list-detail and portrait (800 dp) uses the sheet. Rotating with a package open used to reset to the first package; it is now kept (shell `movableContentOf`). At 2.0 in landscape the text-scaled width is below 840 dp, so it uses the sheet. |
| FST_Book_Fold folded / half / unfolded, font 2.0 | Unfolded flat (852 dp) used a modal sheet across the fold; it is now list-detail. Half-open splits at the hinge. Folded and unfolded at font 2.0 use the sheet with stacked badges. |
| FST_Passport_Fold folded / half / unfolded, font 2.0 | Unfolded (841 dp) now list-detail; half splits at the hinge; folded and font 2.0 use the sheet. |
| FST_TriFold folded / partial / unfolded, font 2.0 | Unfolded list-detail, selection kept across postures; partial and folded use the sheet. Flat folds are non-separating, so the pane boundary need not align with them. |
| FST_Resizable phone · foldable · tablet · desktop, font 2.0 | Phone sheet; foldable (841 dp), tablet and desktop list-detail; desktop at 2.0 (960 effective dp) two panes with stacked badges. |
| Light theme | No effect: the app is dark-only by design ([design/android.md](../../design/android.md)), a deliberate deviation from M3 dynamic light/dark. |
| TalkBack (FST_Phone) | Back, title, intro, then rows in list order, each read once as a button. List-detail selection is covered by the Robolectric tests; the book-fold walk stalls in shell chrome (tool limitation). |
| Touch targets / contrast | Rows are at least 64 dp tall (168 px on the phone) at full card width; Close and Back are 48 dp icon buttons. Badge text on the pill is 9.8:1; row texts on the frosted or selected surface are ≥ 10:1. |
| Reduced motion (animator 0) / animations on | All captures ran at animator 0: the sheet appears without animation and the content is complete. With animations on, the sheet slides up and rotations keep the open package. |
| Connected `BandsSettingsJourneyTest` | Passes on FST_Phone, including Licenses reading order and `assertAccessible`. |

Material 3 (`material-3` skill, Compose): list-detail is the canonical layout for expanded widths, with panes kept clear of a separating hinge. Compact detail uses a modal bottom sheet with a close affordance and full-width list items with 48 dp targets. Deliberate deviations are the dark-only brand scheme and glass cards in place of tonal surfaces (design/android.md).

## Open

- `--check` is not wired into CI (TODO(orchestrator)).
