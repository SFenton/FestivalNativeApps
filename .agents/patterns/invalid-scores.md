# Invalid scores (Filter Invalid Scores)

> **What:** Settings › Filter Invalid Scores for a selected player's scores: which score each chart shows (raw, a valid fallback or nothing), the Songs row's invalid-score indicator and its **Filtered Score** alert, the Over CHOpt Threshold checks and Song Details' filtered score. **Read when:** you change selected-player scores on Songs rows, chips, metadata, the profile panel, Songs filters or sorts, or Song Details' player score; or you add a page that shows a selected player's per-song scores.

Status: **current**, 2026-10-10. Provenance: #613 (Apple port; the Android port predates the record; Windows gained `populationTiers`, the row indicator and alert, Song Details' R4 rule and the full leaderboard's spotlight in the #613 Windows lane).
Status: **current**, 2026-10-10. Provenance: #613 (Apple port; Android and Windows ports predate the record); #615 (Filter sheet checks stay usable).

## Intent

The owner: "Filtered Player Score Display should work in native apps as it does in web." With the setting on, a player's scores that exceed the CHOpt maximum at the chosen leeway are never shown as if valid. Each chart shows the best valid score instead, or nothing, and the row says so. The web is the source of truth. The native apps substitute, and never pause or hide the rows.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/pages/songs/SongsPage.tsx` (`effectiveScores`) | The Songs substitution: per chart, raw, the first `validScores` variant valid at the leeway, the legacy `validScore`, or dropped; Over CHOpt Threshold keeps the raw score. Reasons drive the row's indicator. |
| `FortniteFestivalWeb/src/hooks/data/useScoreFilter.ts` (`filterPlayerScores`, `getFilteredRank`, `getFilteredTotal`) | Song Details' rule (`ml` present: `validScores` only; absent: CHOpt ceiling plus legacy fallback); filtered rank from `rankTiers`, filtered population from the catalogue's `populationTiers`. |
| `FortniteFestivalWeb/src/pages/songs/components/InvalidScoreIcon.tsx` | The row's indicator: red `IoAlertCircleOutline`, gold `IoWarning` when only over-threshold scores are shown, a 2 s opacity pulse, and the **Filtered Score** confirm alert. |
| `FortniteFestivalWeb/src/pages/songs/modals/FilterModal.tsx` | "Over CHOpt Threshold" global and per-chart toggles, shown only while the setting is on. |

## Rules

1. **R1. Leeway.** The filter applies only while Settings › Filter Invalid Scores is on and a **player** is selected. A band's scores are never filtered. The leeway is the Settings value rounded to 0.1 (`fst.settings.leeway`, default 1.0). Changing it, or turning the setting off, re-resolves rows in place without a reload.
2. **R2. Invalid.** A score is invalid when its `minLeeway` (`ml`) exceeds the leeway or, without `ml`, when it exceeds the chart's CHOpt maximum × (1 + leeway/100), unrounded. A chart without a positive maximum never invalidates a score.
3. **R3. Songs substitution (web `effectiveScores`).** For an invalid score, in order:
   - On a chart with an Over CHOpt Threshold check, keep the raw score (reason *over threshold*).
   - Otherwise, if `validScores` (`vs`) is non-empty, use the first variant with `ml` ≤ leeway. Its rank comes from its `rankTiers` at the leeway and its population from the catalogue's `populationTiers` at the leeway, and its percentile is derived from those. With no such variant, drop the score.
   - Otherwise use the legacy `validScore*` fields.
   - Otherwise drop the score.

   Rows, status chips, metadata pills, the wide profile panel ([songs-profile-panel](songs-profile-panel.md)), Score/FC filters, season buckets and the Score/Percentile/Stars sorts all use the effective scores, and nothing pauses.
4. **R4. Song Details (web `filterPlayerScores`).** With `ml` present, only `validScores` can replace a score and the legacy fields are ignored. Without `ml`, the CHOpt ceiling and the legacy fallback apply, and a `validScores` array on that score is ignored (Songs' R3 still prefers it). Branch on `ml` first; never delegate R4 to the R3 resolver. Song Details has no Over CHOpt Threshold. The leaderboard preview's selected-player row shows the filtered score, or no row.
   Rows, status chips, metadata pills, the wide profile panel ([songs-profile-panel](songs-profile-panel.md)), Score/FC filters, season buckets and the Score/Percentile/Stars sorts all use the effective scores, and nothing pauses. The Filter sheet's global and per-chart Missing/Has Scores and Missing/Has FCs checks stay enabled for a selected player while the setting is on, with no paused notice in the sheet or on Songs (#615, like web `useFilteredSongs`). Changing the setting or the leeway re-applies saved checks in place and never clears them, except that Over CHOpt Threshold checks go inert (R8).
4. **R4. Song Details (web `filterPlayerScores`).** With `ml` present, only `validScores` can replace a score and the legacy fields are ignored. Without `ml`, the CHOpt ceiling and the legacy fallback apply. Song Details has no Over CHOpt Threshold. The leaderboard preview's selected-player row shows the filtered score, or no row.
5. **R5. Indicator.** A Songs row (not a Shop row) with a selected player's current scores shows one indicator when any described chart was replaced, dropped or kept over threshold. The described charts are the filtered chart, else the Settings-visible charts.
   - **Tone:** red alert circle; gold warning when every described chart is over threshold.
   - **Pulse:** like the web's opacity pulse, held still by Reduce Motion (system or app) and by an inactive scene.
   - **Placement:** after the primary metric on a one-chart row, after the chips on a chips row, and before the Shop icons on a profile-panel row.
6. **R6. Indicator accessibility.** The drawn glyph is hidden from accessibility. A separate button sits over it, outside the row's link (inside, a tap would open the song). It is at least 44 × 44 pt, has the ID `fst.songs.invalid-score.<songId>`, the label "Invalid score indicator", and is read after the song and before the profile-panel cards.
7. **R7. Alert.** "Filtered Score", with the web's message for the reasons, naming charts by their native labels. Buttons: **OK** (cancel) and **Settings**. Settings opens the setting: the Settings tab on iOS/iPadOS, the Settings window's Paths pane on the Mac. Where no shell can open Settings (hosted tests), only OK shows.
8. **R8. Over CHOpt Threshold filter.** A global and a per-chart "<Chart> Over CHOpt Threshold" check (Apple IDs `fst.songs.filter.score.global.overThreshold`, `fst.songs.filter.score.chart.<raw>.overThreshold`) appear only while the setting is on. A checked chart keeps its raw invalid score, and the song passes only when that score is over the threshold. A saved check is inert and not "active" while the setting is off.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Policy (R2–R4), population tiers | `apple/Sources/FestivalCore/InvalidScorePolicy.swift` `InvalidScorePolicy` (`resolve`, `filtered`), `SongPopulationTierTable` | `android/app/src/main/java/com/festivalscoretracker/android/core/songs/SongInvalidScores.kt` `InvalidScorePolicy` | `windows/Festival.Core/Domain/SongInvalidScores.cs` `InvalidScorePolicy` (`Resolve` R3, `ResolveFiltered` R4); `windows/Festival.Core/Data/Models.cs` `Song.FilteredPopulation` |
| Alert text (R7) | `apple/Sources/FestivalCore/InvalidScorePolicy.swift` `InvalidScoreWarning` | `android/app/src/main/java/com/festivalscoretracker/android/core/songs/SongInvalidScores.kt` `InvalidScoreWarning` | `windows/Festival.Core/Domain/SongInvalidScores.cs` `InvalidScoreWarning` |
| Songs wiring (R1, R3) | `apple/Sources/FestivalUI/Features/Songs/SongsScreen.swift` `playerScoreIndex`; `SongRowView.swift` `playerScores` | `android/app/src/main/java/com/festivalscoretracker/android/presentation/songs/SongScoreAdapter.kt` | `windows/Festival.Core/ViewModels/SongScoreSource.cs` `ForSongs` |
| Song Details wiring (R4) | `apple/Sources/FestivalCore/InvalidScorePolicy.swift` `filtered` | not audited (Android lane) | `windows/Festival.Core/ViewModels/SongScoreSource.cs` `ForDetail` |
| Indicator and alert (R5–R7) | `apple/Sources/FestivalUI/Features/Songs/InvalidScoreIndicator.swift` `InvalidScoreGlyph`, `songInvalidScoreIndicator` | `android/app/src/main/java/com/festivalscoretracker/android/ui/songs/SongRow.kt` `InvalidScoreIcon` | `windows/Festival.App/Controls/InvalidScoreIndicator.cs` `InvalidScoreIndicator`; alert `windows/Festival.App/Pages/SongsPage.xaml.cs` `OnInvalidScoreClick` |
| Over CHOpt Threshold (R8) | `apple/Sources/FestivalCore/SongPlayerScoreFilter.swift` `overThreshold`; `SongsFilterSheet.swift` `overThresholdBinding` | `android/app/src/main/java/com/festivalscoretracker/android/ui/songs/SongsSheets.kt` | `windows/Festival.Core/ViewModels/SongFilterDraft.cs` |

Tests:
- Apple: `InvalidScorePolicyTests` (core), `SongPlayerScoreFilterTests.overThresholdChecksNeedFilterInvalidScoresAndAScoreAboveTheCeiling`, and `SelectedSongRowRenderTests.filteredScoresShowEffectiveScoresAndAnIndicatorAfterTheSong` (hosted Songs tree, iPhone width and wide).
- Apple: `SongsSortSheetRenderTests.songsFilterSheetOffersOverThresholdOnlyWhileFilteringInvalidScores`.
- Apple (#615): `SongPlayerScoreFilterTests.savedScoreFiltersApplyToEffectiveScoresAtEveryLeeway` (Score/FC, Over CHOpt, season, stars and percentile through substituted scores at several leeways and with the setting off), hosted `SongsSortSheetRenderTests.songsFilterSheetScoreChecksStayEnabledWhileFilteringInvalidScores` (role, order, enabled state, value, no paused copy), and the iPhone journey `SongsJourneyTests.testPlayerScoreFilterSettingsPauseAndDeselectScope` (no notice, saved check kept, switches enabled with labels and ≥ 43 pt height; release CI runs it in `apple-ci`'s plain-fixture step, `PLAIN_JOURNEYS`).
- Android: `SongsParityTest`.
- Windows: `SongInvalidScoresTests` (policy, `ResolveFiltered`, population tiers, warning text, rows updating in place), `SongDetailSongsLaneTests.RowEleven_*` (R4), `LeaderboardsViewModelTests.SpotlightUsesTheValidVariantAndItsFilteredRank`, `SongMetadataLayoutTests` (indicator width). UIA: `tools/windows/journeys/instrument-status.json` (`chips-invalid-scores`, `chips-invalid-scores-off`), `a11y-songs-invalid-score.json` and `a11y-modals.json` `modal-invalid-score`.

## Platform differences

- **Apple:** The indicator glyph is an SF Symbol (`exclamationmark.circle` red, `exclamationmark.triangle.fill` gold) with the symbol pulse effect (HIG Motion: "Consider animated SF Symbols"; "Make motion optional"). The alert follows HIG Alerts' informational case ("you can use OK"). The chips row's alert lists only Settings-visible charts; the web lists every invalid chart. The Settings button opens the Settings tab (iOS/iPadOS) or the Paths pane (Mac).

- **Windows:** The indicator is a Fluent icon `Button` (`InvalidScoreIndicator`): Segoe Fluent `E783` red (`FSTStatusMissingFillBrush`) or `E7BA` gold (`FSTEmphasisBrush`), system foreground under contrast themes. Its target is 40 × 40 epx (`DialogChrome.TargetSize`, the Fluent minimum, in place of R6's 44 pt), with the ID and Narrator name from R6 and the tooltip "Filtered Score". It is the last item in the row's trailing strip (after chips, metadata or the score state), which is also its Tab and Narrator position. Windows Songs rows have no profile panel, so R5/R6's panel placement does not apply. The pulse runs on the shared `ShopPulseClock` (2 s, 1 → 0.4 → 1) and holds at full opacity when app or system motion is off. The alert is a `FestivalDialog` with **Settings** (Primary, opens Settings) and **OK** (Close, so Esc dismisses it and focus returns to the icon). The full song leaderboard's pinned player row uses the Songs resolution (`InvalidScorePolicy.Resolve`, no Over CHOpt Threshold). It shows the valid variant with its filtered rank, and no pinned row when no valid score exists. That matches web `LeaderboardPage`, where `hasPlayerFooter` is false unless the score is valid or a fallback resolves.

## Known debt

- Apple Player Profile tiles and Suggestions still read raw scores. The web filters Player Profile via `filterPlayerScores`.
- Windows Player Profile tiles still come from the profile read's unfiltered `stats` summary; the web filters Player Profile via `filterPlayerScores`. Windows lane, outside #613's Songs scope.

## Guards (`tools/pattern_guard.py`)

- `invalid-scores/apple-invalid-score-pause`: no Apple source may bring back the "not available yet" or "paused while Filter Invalid Scores" copy; Filter Invalid Scores substitutes effective scores (R3).
