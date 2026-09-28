# Player profile — Windows notes

> **What:** what the Windows player page (`/player/:accountId`) implements, its layout decisions and open gaps. **Read when:** changing `windows/Festival.App/Controls/PlayerProfileView*`, `Pages/PlayerProfilePage*`, `PlayerProfileViewModel` or the player Core reads. Behavior reference: [ios.md](ios.md) (spec.md is still a stub); Statistics reuses this view: [statistics/windows.md](../statistics/windows.md).

## Reads (all keyless; see [service-safety](../../platforms/service-safety.md))

| Data | Endpoint | Client |
|---|---|---|
| Compact scores (202 = syncing) | `GET /api/player/{accountId}` | `FestivalApiClient.GetPlayerProfileAsync` → `PlayerProfilePayload` (header-verified `PublicationId`, observed generation) |
| Global rank (404 = unranked) | `GET /api/rankings/{instrument}/{accountId}` | `GetPlayerInstrumentRankingAsync` (`PlayerInstrumentRanking : AccountRankingEntry`; blank live `instrument` accepted) |
| Rank history (30 days) | `GET /api/rankings/{instrument}/{accountId}/history?days=30` | `GetPlayerRankHistoryAsync` |

Never player-stats: overview/instrument stats and percentile buckets are computed client-side (`PlayerStatistics`, mirroring the web's `playerStats.ts`). `ReadPinnedResponseAsync` accepts a documented 202 without publication checks and never caches it.

## Layout

- One `ScrollViewer` (max 1280 epx): header card, Overview tiles, one titled card per Settings-visible instrument, then the Bands link. Tiles are an `ItemsRepeater` + `UniformGridLayout` (min 112×84 epx so a long value can wrap to two lines above its label), reflowing from one column (compact) to five (wide).
- Instrument card: stats + Global Rank on the left; Rank History (rank line with #1 on top over Total Score bars, `RankHistoryChart`) and Percentiles (horizontal bars, top 5% gold) on the right once the card is at least 780 epx wide and back below under 740 epx (hysteresis: a vertical scrollbar appearing near one threshold could otherwise oscillate) (`OnInstrumentCardSizeChanged`). Rank/history reads start when the card is realized; unplayed charts read nothing.
- Charts are static XAML shapes (`PlayerLineChart`) redrawn only on data or size change, with no per-frame work. Each chart is one UIA `Image` named with the trend summary.
- Header: `PersonPicture`, name (H1) with no subtitle (the web has none; operator 2026-09-28): selection state shows only through Select/Deselect; the action row sits under the avatar row so it never clips on narrow windows.

## Identity actions (never navigate away)

| Read state | Header |
|---|---|
| Selected account | **Deselect Profile** → `ContentDialog` (Cancel default) |
| Viewed, verified and current, no selection | **Select Profile** (accent), immediate |
| Viewed, another player selected | **Switch to This Profile** → confirmation dialog |
| No `X-FST-Publication-Id` | "Selection is paused" notice (`fst.player.identity-notice`) |
| Publication advanced since the read | "Reload before selecting" notice |

`FestivalSession.SelectPlayer(payload, name)` re-checks `IsSelectable` and seeds the selected scores from the same payload (no second read). The shell diffs its section set in place, so selecting or deselecting keeps the current section (a `Clear()` used to bounce to Songs).

## IDs

`fst.player` (page root), `fst.player.{available,loading,syncing,no-profile,name,subtitle,select,deselect,identity-notice,action-error,overview,bands-link}` (failures use the shared `fst.service-status.*`), `fst.player.instrument.<ServiceId>` (the section heading), `fst.player.instrument-empty.<ServiceId>`, `fst.player.rank-history.<ServiceId>`, `fst.player.percentiles.<ServiceId>`.

UIA gotcha: `Border`, `StackPanel`, `ItemsRepeater` and `UserControl` are not in the control view, so an AutomationId set on them never reaches the tree. IDs live on headings, repeaters, buttons and text; `PlayerProfileView` supplies its own group peer so the page roots `fst.player`/`fst.statistics` are findable.

## Tests

- Core: `PlayerDataTests.cs` (wire decode/validation, client reads, session selection) and `PlayerViewModelTests.cs` (page/instrument/history view models, charts, flyout, launch options).
- UI journeys: `python tools/windows/journeys/profile.py [--exe …] [--shots dir]`: search → view → select → Statistics → deselect, restart persistence, history sort and states, syncing, Bands scope.

## Gaps

- No Quick Links (the Windows idiom is Settings-lane work), no experimental rank metrics, no top-songs section and no tap-to-filter tiles: the same simplifications as iPhone.
- Compact windows rely on the shell's `NavigationView` `PaneDisplayMode="Auto"` (overlay pane below the expanded threshold); the page itself reflows to one tile column and stacks charts under the stats.
