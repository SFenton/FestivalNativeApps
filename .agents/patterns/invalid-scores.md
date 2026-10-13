# Invalid scores

> **What:** the selected player's effective Songs score at the Filter Invalid Scores leeway, including fallback rank, stars and population. **Read when:** changing score substitution, score-derived Songs metadata, checks or player sorts.

Status: **current**. Provenance: #613 (registers the existing shared score-data policy; no layout or chrome change).

## Web source (behavior reference)

| Source | Behavior |
|---|---|
| `FortniteFestivalWeb/src/pages/songs/SongsPage.tsx` `effectiveScores` | Valid raw score, best eligible variant, legacy fallback or no score; Over CHOpt Threshold keeps the raw invalid score. |
| `FortniteFestivalWeb/src/hooks/data/useScoreFilter.ts` `getFilteredTotal`, `getFilteredRank` | Last changepoint at or below the leeway; base population before the first population changepoint. |
| `packages/core/src/api/serverTypes.ts` `expandWireSongsResponse`, `expandWirePlayerResponse` | Catalogue population wire `{bc,t:[{l,t}]}`; player variant `{sc,acc,fc,st,ml,rt:[{l,r}]}` and legacy `validScore`, `validAccuracy`, `validIsFullCombo`, `validRank`, `validStars`, `validTotalEntries`. |
| `FSTService/Api/PlayerEndpoints.cs`, `FSTService/Api/SongsCacheService.cs` | Public player legacy fallback fields and catalogue population publication. No new endpoint is needed. |

Reviewed reference revision: `c56460faeb9c659371634ab891c93df3b986308b`. This pins the score-data comparison, not whole-app visual parity.

## Rules

1. **R1. Resolve once through the platform's canonical policy.** Filtering off uses raw scores. Filtering on keeps a raw score when `ml <= leeway`; without `ml`, compare with the chart's CHOpt maximum times `(1 + leeway / 100)`. Missing maximum means the score cannot be judged, not that it is invalid.
2. **R2. Variant substitution.** For an invalid raw score, use the first eligible `vs` variant (`ml <= leeway`, published in descending score order). Replace score and any supplied accuracy, FC and stars. Rank uses the variant's last `rt` changepoint at or below leeway, otherwise the raw rank. Population uses the catalogue chart's last population changepoint at or below leeway, otherwise `bc`; an absent/null curve retains the raw total. Zero is a real supplied count. No eligible variant means no score, even when legacy fields exist.
3. **R3. Legacy substitution.** When no nonempty variant list exists, use `validScore` and its supplied accuracy, FC, rank, stars and total. Missing legacy rank becomes zero; missing other metrics retain their raw values. With no fallback, omit the effective score.
4. **R4. Explicit reasons and raw override.** Retain fallback/no-fallback reasons even when no score remains. Over CHOpt Threshold on a chart keeps its raw invalid score, rank and population and marks it over-threshold. Valid raw scores likewise retain raw rank and population; filtered population applies to substituted variants only.
5. **R5. Consumers and publication.** Songs chips, metadata, Score/FC/bucket checks and player sorts all read the same effective detail source, after the existing catalogue/score/session publication gate. Changing leeway or the toggle reprojects loaded Songs data without a catalogue or player reload. The policy must not interpret unavailable or mismatched scores as missing scores.

## Canonical implementation

| Sub-behavior | Android | Windows |
|---|---|---|
| Resolution and reasons (R1-R4) | `android/app/src/main/java/com/festivalscoretracker/android/core/songs/SongInvalidScores.kt` `InvalidScorePolicy` | `windows/Festival.Core/Domain/SongInvalidScores.cs` `InvalidScorePolicy` |
| Population curve (R2) | `android/app/src/main/java/com/festivalscoretracker/android/core/model/PopulationTiers.kt` `PopulationTiers`; `Song.filteredPopulation` | `windows/Festival.Core/Data/Models.cs` `SongPopulationTiers`, `Song.FilteredPopulation` |
| Songs integration (R5) | `presentation/songs/SongScoreAdapter` | `windows/Festival.Core/ViewModels/SongScoreSource.cs` `ForSongs`; `SongsViewModel`, `SongListPipeline`, `SongRowProjector` |

Windows validates decoded curves at the catalogue boundary (finite ordered leeways, nonnegative counts); malformed curves report `InvalidResponse` through the existing service-error path rather than silently producing a percentile. Source-generated JSON keeps the wire model trim/NativeAOT-safe. Existing native controls, layout and accessibility are unchanged.

## Known debt

| Surface | Debt |
|---|---|
| Apple | Effective-score substitution is handled by the separate #613 Apple worker; its unsupported-substitution guards are not a Windows mechanism to copy. |
| Windows Songs | The existing invalid-score warning action is not ported; this score-data verification does not certify warning UI. |
| Windows Song Details / Profile | They still use their existing raw profile source; parity of those separate pages is outside the Windows Songs verification slice. |

## Tests and guards

Windows `SongInvalidScoresTests` covers variant population, all legacy metrics, absent/null/zero population, raw overrides and live propagation through metadata, checks and sorts without new reads. `ModelAndSongsTests` covers compact decode, exact and duplicate changepoints and explicit invalid-curve failures. `PlayerModelTests` rejects out-of-range legacy fallback metrics.

No regex guard; the data and view-model tests hold these rules.
