# Player profile — Android notes

> **What:** the Android player page (`/player/:accountId`) and the body it shares with Statistics: viewed vs selected, reads, layout and IDs. **Read when:** changing `ui/profile/PlayerProfileScreen.kt`, `presentation/profile/PlayerProfileViewModel.kt` or `core/profile/*` on Android. Behavior reference: [windows.md](windows.md), [ios.md](ios.md) (spec.md is still a stub); Statistics: [statistics/android.md](../statistics/android.md).

## Reads (keyless; [service-safety](../../platforms/service-safety.md))

| Data | Endpoint | Client |
|---|---|---|
| Compact scores (202 = syncing) | `GET /api/player/{accountId}` | `FestivalApi.playerProfile` (`data/profile/FestivalApiProfile.kt`) → `PlayerProfilePayload(profile, state, publicationId?, observedPublicationId)` via `readPinnedResponse` |
| Global rank (404 = unranked) | `GET /api/rankings/{instrument}/{accountId}` | `playerInstrumentRanking` (blank live `instrument` accepted) |
| Rank history (30 days) | `GET /api/rankings/{instrument}/{accountId}/history?days=30` | `playerRankHistory` |

Never player-stats: overview/instrument stats and percentile buckets are computed client-side (`core/profile/PlayerProfile.kt` `PlayerStatistics`, web `playerStats.ts`). Compact `acc` is percent × 10 and is exposed ×1,000 (leaderboard scale); `pct == -1` becomes null.

## Selected vs viewed

- `SelectedProfileStore` (`AppContainer.selectedProfile`, started by `FestivalApp`) owns the selected player's process-only scores: it reloads on a switch or a publication advance, clears on deselect, drops late reads for a previous account and counts down a scrape freeze. Songs and Suggestions read `state.scoreIndex` + `observedPublicationId` instead of reading again.
- The page mirrors the store when the shown account is the selected one, else runs its own read. Select seeds the store from the same read (no second GET) and persists through `ShellViewModel.selectPlayer`; Deselect keeps showing the read as a viewed profile.

| Read state | Header |
|---|---|
| Selected account | **Deselect Profile** → `AlertDialog` |
| Header-verified and current, nothing selected | **Select Profile**, immediate |
| Another player selected | **Switch to This Profile** → confirmation |
| No `X-FST-Publication-Id` | "Selection is paused" notice |
| Publication advanced since the read | "Reload this page before selecting" notice |

None of these navigate. Selecting adds the profile tabs in place; deselecting on the Statistics tab removes that tab, so the shell falls back to Songs (as on Windows).

## Layout

- `LazyVerticalGrid(GridCells.Adaptive(380.dp))`: header, Overview and the Bands link span the full line; one glass card per Settings-visible instrument, so phones get one column and unfolded or tablet windows two or three.
- Instrument card: stat tiles (`FlowRow`), Global Rank, Rank History (Canvas rank line over Total Score bars, #1 on top), Percentiles (horizontal bars, top 5% gold). Rank and history reads start in the card's `LaunchedEffect`, so unrealized cards read nothing; unplayed charts show a footnote and read nothing.
- Charts draw precomputed geometry (`core/profile/PlayerCharts.kt`) with no per-frame work; each chart is one accessibility element carrying the trend summary, and tiles merge into one "Label: value" node.

## IDs

`fst.player`, `fst.player.{loading,syncing,no-profile,retry,available,name,subtitle,select,deselect,identity-notice,action-error,overview,bands-link}`, `fst.player.switch-confirm[.ok|.cancel]`, `fst.player.deselect-confirm[.ok|.cancel]`, `fst.player.instrument.<wire>`, `fst.player.instrument-empty.<wire>`, `fst.player.global-rank.<wire>.{loading,unranked,available,error}`, `fst.player.rank-history.<wire>`, `fst.player.percentiles.<wire>`.

## Tests

`core/profile/PlayerProfileCoreTest`, `data/profile/FestivalApiProfileTest`, `presentation/profile/{SelectedProfileStoreTest,ProfileViewModelsTest}`, Robolectric `ui/profile/ProfileUiTest` (search → view → select → Statistics → deselect, switch confirmation, cold-start persistence, history) and `ProfileExpandedUiTest` (1280 dp).

## Gaps

Same simplifications as Windows and iPhone: no Quick Links, no experimental rank metrics, no top-songs section, no tap-to-filter tiles, no chart scrubbing. Robolectric does not run Canvas draw code; check charts with device screenshots.
