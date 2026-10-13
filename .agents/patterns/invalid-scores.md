# Invalid scores (Filter Invalid Scores)

> **What:** how a selected player's scores are shown while Settings → Filter Invalid Scores is on: which score a chart shows (raw, a valid fallback, or none), its filtered rank and population, the Over CHOpt Threshold exemption, and the per-row invalid-score indicator and its "Filtered Score" alert. **Read when:** changing Songs rows, Songs Score/FC filters or player sorts, Song Detail's player row, Player Profile score tiles, or anything that reads `ml`/`vs`/`validScore*` or the catalogue's `maxScores`/`populationTiers`.

Status: **current**, 2026-10-10. Provenance: #613 ("Filtered Player Score Display should work in native apps as it does in web"); Android and Windows substitution from win-unify/Android Songs lanes, recorded here by the #613 Windows worker (agent entry; the owner may override).

## Intent

With Filter Invalid Scores on, a player sees the score they would have if their invalid runs did not count, exactly as the web shows it, everywhere a selected player's score appears, and is told when a shown score was replaced or dropped. Nothing pauses because of the setting.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/hooks/data/useScoreFilter.ts` (`isScoreValid`, `getFilteredTotal`, `getFilteredRank`, `filterPlayerScores`) | Validity at the leeway (`ml` when present, else the CHOpt maximum × (1 + leeway/100)); filtered population (last `populationTiers` tier with `l` ≤ leeway, else `bc`, else the raw total); the player's best valid variant (`vs` with `ml` ≤ leeway) with its `rankTiers` rank, else the legacy `validScore`/`validRank`/`validTotalEntries`, else dropped. Used by Song Detail and the Player page. |
| `FortniteFestivalWeb/src/pages/songs/SongsPage.tsx` (`effectiveScores`) | Songs' substitution (same rules) plus the Over CHOpt Threshold exemption (the raw invalid score stays on charts whose filter is on) and the per-song `invalidScoreMap` (reason per chart). Filters, sorts, chips and metadata use the effective scores. |
| `FortniteFestivalWeb/src/pages/songs/components/InvalidScoreIcon.tsx` (`InvalidScoreIcon`) | The row indicator: red alert, or gold warning when every described chart is an Over-Threshold raw score; pulses; opens the "Filtered Score" alert (text per reason, footer naming the setting, Settings and OK). |

## Rules

- **R1. Substitute, never pause.** With Filter Invalid Scores on and scores available, every surface that shows the selected player's per-chart score uses the effective score from the web rules above: the raw score when valid at the leeway, else the best `validScores` variant with `minLeeway` ≤ leeway (its filtered rank from `rankTiers` and filtered total from the catalogue `populationTiers`), else the legacy `validScore` fields, else no score. Score/FC filters, Over CHOpt Threshold checks and player sorts (Score, Percentile, Stars) read the same effective scores. The setting never shows a "not available yet" or "paused while Filter Invalid Scores is enabled" state.
- **R2. One policy per platform.** Each platform resolves scores in one pure policy (canonical below) shared by Songs rows, filters, sorts, the wide-row profile panel, Song Detail's player row and the indicator; a page never re-implements validity, fallback or population math.
- **R3. Over CHOpt Threshold keeps the raw score (Songs only).** On a chart whose Over CHOpt Threshold filter is on, Songs keeps the raw invalid score (reason over-threshold) so the filter can match it. Song Detail and the Player page follow web `filterPlayerScores`, which has no exemption.
- **R4. Say when a score was changed.** A Songs row whose described chart score was replaced, dropped or kept over the threshold ends with the invalid-score indicator: red alert glyph, gold warning when every described chart is over-threshold; under a single-chart filter only that chart counts. It is a real button (≥ 40 epx/48 dp/44 pt target) named "Invalid score indicator" whose explanation (the web alert text) is reachable by screen readers, and activating it opens the "Filtered Score" alert with Settings and OK through the platform's modal shell ([modal-shell](modal-shell.md)). Its pulse stops when motion is reduced. Native rows describe only Settings-visible charts (Android precedent; the web counts every chart).
- **R5. Update in place.** Changing the leeway or toggling the setting re-resolves rows, the profile panel and Song Detail's player row without a full reload or a loading state.
- **R6. Malformed data degrades, never fails.** A malformed `populationTiers` curve falls back to the raw total; a malformed variant is ignored; neither fails the catalogue or profile decode.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Policy (R1–R3, R6) | `apple/Sources/FestivalCore/InvalidScoreFilter.swift` `InvalidScoreFilter` (leaderboard leeway only; substitution is debt) | `android/app/src/main/java/com/festivalscoretracker/android/core/songs/SongInvalidScores.kt` `InvalidScorePolicy` | `windows/Festival.Core/Domain/SongInvalidScores.cs` `InvalidScorePolicy`; filtered population `windows/Festival.Core/Data/PopulationTiers.cs` `PopulationTiers` |
| Songs effective scores (R1, R5) | — (debt) | `android/app/src/main/java/com/festivalscoretracker/android/presentation/songs/SongScoreAdapter.kt` | `windows/Festival.Core/ViewModels/SongScoreSource.cs` `ForSongs` |
| Song Detail player row (R1, R3) | — (debt) | — | `SongScoreSource.ForDetail` |
| Indicator and alert (R4) | — (debt) | `android/app/src/main/java/com/festivalscoretracker/android/ui/songs/SongRow.kt` `InvalidScoreIcon` | `windows/Festival.App/Controls/InvalidScoreIndicator.cs` `InvalidScoreIndicator`; text `InvalidScoreWarning` (`SongInvalidScores.cs`) |

Windows tests: `SongInvalidScoresTests`, `InvalidScoreParityTests`; UIA `tools/windows/journeys/a11y-songs-invalid-score.json` and `a11y-modals.json` `modal-invalid-score` (fixture `tools/windows/instrument_status_fixture.py`).

## Known debt

- Apple (#613, iPhone/iPad/Duo/Mac): Songs rows show "Filtered player score display is not available yet" and pause score filters and player sorts (`SongProfileSummary`, `SongsScreen`, `SongRowView`, `SongInstrumentStatusPolicy`, `SongsFilterSheet`); no indicator. Owned by the Apple session.
- Android: Song Detail's player row and Player Profile tiles have not been audited against `filterPlayerScores` under this pattern (Player Profile already counts over-threshold scores with `InvalidScorePolicy.isValid`).
- Windows: Player Profile score tiles/lists do not yet apply `filterPlayerScores` (web Player page does).

## Guards (`tools/pattern_guard.py`)

None.
