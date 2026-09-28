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

- `ProfileGrid` (`ui/profile/ProfileGrid.kt`): a `LazyVerticalStaggeredGrid` whose columns come from `ProfileColumns` (`core/profile/ProfileLayout.kt`, reusing the Rivals lane's `HingeColumns`): one column per 340 dp (max 3), or one column per panel with the gaps on every separating vertical hinge (book fold half-open; a partly folded tri-fold). When split at a fold, the full-width rows (header, Overview, Top Songs heading, Bands) become single-lane so nothing straddles the hinge; flat folds (unfolded book, FST_TriFold) are not separating and use width rules.
- Rows (`ProfileSections.rows`, web `PlayerContent.tsx` order): header, Overview, one card per Settings-visible chart, "Top Songs Per Instrument", one top-songs card per chart, Bands link.
- Header: avatar and name only — selection state shows only through the Select/Switch/Deselect control (the web header has no "This Is Me"/"Public Profile" line).
- Text is white (`textPrimary`/onSurface) by default; gray (`textSecondary`/`textMuted`) only for de-emphasis: section descriptions, top-song subtitles, history dates, chart axes.
- Stars use the web's images (`res/drawable-nodpi/star_white.png`, `star_gold.png`) through the shared `ui/design/StarRating` (score-history rows; the "Avg Stars" tile shows five gold stars at a perfect 6, else two trimmed decimals, web `formatClamped2`).
- Instrument card: stat tiles (`FlowRow`: Songs Played, Full Combos, Gold Stars, 5 Stars, Avg Accuracy, Avg Stars, Best Rank), Global Rank, Rank History (Canvas rank line over Total Score bars, #1 on top), Percentiles (horizontal bars, top 5% gold). Rank and history reads start in the card's `LaunchedEffect`, so unrealized cards read nothing; unplayed charts show a footnote and read nothing.
- Charts draw `ChartGeometry` output (`core/profile/PlayerCharts.kt`: bar widths/rects, point and label positions) with no logic in the draw lambdas and no per-frame work; each chart is one accessibility element carrying the trend summary.

## Quick Links

Web `PlayerContent` quick links: `global` "Global Statistics" (jumps to Overview), `instrument:<wire>` (instrument label, instrument icon), `top-songs` "Top Songs", `bands` "Bands" (jumps to the Bands section). Shared controller ([quick-links/android.md](../../controls/quick-links/android.md)) over the staggered grid: top-bar action (sheet < 600 dp, menu otherwise); persistent 240 dp pane when the page is ≥ 960 dp **and** no separating hinge exists (with a hinge the two content panels are more useful than a navigation panel).

## Top songs

`PlayerTopSongs.build` (web `buildTopSongsItems`): scores with `rank > 0 && te > 0`, stable-sorted by `rank / te`; top five, and when more than five are ranked the last five reversed ("Bottom Five Songs", which may overlap the top list, as on the web). Titles/art from the in-process catalogue (`FestivalApi.catalog`); a missing song shows the first eight ID characters. Pill: `ScoreFormatting.percentileBucket` ("Top 5%", gold ≤ 5%). No ranked score: "No scores yet" empty state. Rows open Song Detail.

## Bands section

Web `PlayerBandsSection` ("{name}'s Bands", See all, band cards, "View all bands (N)") fills from player-stats (blocked). Android reads one keyless page instead: `GET /api/player/{id}/bands?group=all&page=1&pageSize=4` (`FestivalApi.playerBands`, Bands lane; never band search or `/api/bands/{id}`), started when the row is shown (`ensureBands`) and reset per account/publication. Cards are the Bands lane's `PlayerBandCard` → `BandRoute`; "See all"/"View all bands (N)" → `PlayerBandsRoute`. States: loading, empty ("No bands yet"), inline retry. The web's separate Duos/Trios/Quads previews would need three reads; the full list page has the group picker.

## Tap-to-filter tiles

Tiles carry `PlayerTileAction` (web `StatBox.onClick`); `PlayerProfileViewModel.run` implements `withProfileSwitch`: on a viewed page it selects the player first (Switch asks "Switch to {name}?" with the web's message), then:

| Tile | Action (web source) |
|---|---|
| Overview Songs Played / Full Combos | Reset Songs filters, Title ascending, Has Scores / Has FCs on every visible chart (`songsPlayedUpdater`, `fullCombosUpdater`) |
| Chart Songs Played / Full Combos (FCs > 0) | That chart only, its checks (incl. Over CHOpt Threshold) and difficulty cleared, then Has Scores / Has FCs, Score ascending; other charts' checks and the Shop filter kept (`cleanFilters` + `instSongsPlayedUpdater`/`instFCsUpdater`) |
| Best Rank (overview and chart) | Song Detail (`navigateToSongDetail`) |
| Global Rank (Total Score) | Full Rankings, Total Score (`navigateToLeaderboard`; no page jump yet) |
| Gold/5 Stars, Avg Accuracy, Avg Stars | Flat: the web's star presets need a Songs stars filter (not ported); Avg Accuracy/Avg Stars are flat on the web too |

Presets are written through the Songs lane's stores (`data/profile/ProfileSongsPresets.kt`: `SongsPreferences.setFilters` + `SettingsRepository.setSongSort`), then the shell switches to the Songs tab (a tab-root route now selects the tab instead of pushing a copy). While selection is paused (unverified/changed publication) Songs tiles are flat; song/rankings tiles still navigate without selecting. The web also clears the Songs search text; Android's search text lives in the Songs view model and is kept.

## Experimental metrics (decision)

Not shown. The web adds Adjusted/Weighted/FC Rate/Max Score rank tiles only when the user turns on Settings → Experimental Ranks (`InstrumentStatsSection.tsx`, `DEFAULT_METRICS` + `EXPERIMENTAL_METRICS`; default off). Android's Settings sanitizes that toggle off ("Not available on Android yet"), so the page shows the default Total Score rank only. When Settings enables it, add the four tiles from the same pure-read rankings row (`adjustedSkillRank`, `weightedRank`, `fcRateRank`, `maxScorePercentRank`) gated on `AppSettings.experimentalRanks`.

## IDs

`fst.player`, `fst.player.{loading,syncing,no-profile,retry,available,header,name,select,deselect,identity-notice,action-error,overview,bands,bands-link,bands.loading,bands.empty,bands.view-all,top-songs}`, `fst.player.switch-confirm[.ok|.cancel]`, `fst.player.deselect-confirm[.ok|.cancel]`, `fst.player.action-switch-confirm[.ok|.cancel]`, `fst.player.instrument.<wire>`, `fst.player.instrument-empty.<wire>`, `fst.player.global-rank.<wire>.{loading,unranked,available,error}`, `fst.player.rank-history.<wire>`, `fst.player.percentiles.<wire>`, `fst.player.tile.<overview|wire|rank.wire>.<label-slug>`, `fst.player.top-songs.<wire>`, `fst.player.top-songs-empty.<wire>`, `fst.player.{top,bottom}-song.<wire>.<songId>`.

## Tests

- JVM: `core/profile/{PlayerProfileCoreTest,ProfileParityCoreTest}` (top songs, presets, fold columns, sections, chart geometry), `data/profile/{FestivalApiProfileTest,ProfileSongsPresetsTest}`, `presentation/profile/{SelectedProfileStoreTest,ProfileViewModelsTest,ProfileActionsTest}`.
- Robolectric: `ui/profile/ProfileUiTest` (search → view → select → Statistics → deselect, switch, cold start, history), `ProfileParityUiTest` (Quick Links sheet, top songs, Bands preview/empty, tile → Songs filter, confirmed switch before a tile, paused selection, Global Rank → Full Rankings), `ProfileChartsDrawTest` (`@GraphicsMode(NATIVE)`, draws the window so the Canvas code runs), `ProfileParityExpandedUiTest` (pane at 1280 dp).
- Device: `androidTest/.../profile/ProfileDeviceJourneyTest` (select/deselect and switch stay on the page, tile → Songs filter, top song → Song Detail, history sort; asserts no card crosses a separating hinge). Run `python tools/android/device.py test com.festivalscoretracker.android.profile.ProfileDeviceJourneyTest --avd FST_Phone` and `--avd FST_Book_Fold --posture half`. `androidTest` shares the JVM tests' synthetic `testing/` fixtures.

## Gaps

- Star tiles stay flat until Songs has a stars filter; no Over CHOpt Threshold, 4/3/2/1-star or Percentile tiles yet (web `InstrumentStatsSection`); Global Rank opens rankings page 1 (Full Rankings has no page argument); Song Detail opens without the web's `?instrument=` focus (Songs lane route).
- No family (pad/pro strings/pro drums) Global Statistics cards or embedded player bands: both need player-stats (blocked, [service-safety](../../platforms/service-safety.md)).
- No chart scrubbing; stats ignore the invalid-score leeway filter (as before).
- Web behaviour was taken from source: the production web player page itself calls player-stats and sync-status, so it is not captured from the installed PWA.
