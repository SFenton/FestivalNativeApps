# Rivals hub — Windows notes

> **What:** the Windows Rivals feature (hub, All Rivals, Rival Detail, Rivalry, Find Rival, Compete deep link): data, typed scope, layout, tests and gaps. **Read when:** changing `windows/Festival.App/Pages/Rival*`, `AllRivalsPage*`, `Controls/Rival*` or `Festival.Core` Rivals files. Behavior: [spec.md](spec.md); iPhone reference: [ios.md](ios.md).

## Data

| Read | Endpoint | Notes |
|---|---|---|
| Song rivals | `GET /api/player/{id}/rivals/{Solo_*\|hexCombo\|pro_drums}` | 404 "no rivals" → empty. Combo token from `RivalCombo.DeriveToken` (web `deriveRivalScopeFromSettings`) |
| Leaderboard rivals | `GET /api/player/{id}/leaderboard-rivals/{instrument}?rankBy=` | `rankBy` is `RankingMetric` (Leaderboards lane); Total Score unless experimental ranks (sanitized off, as in production web) |
| Rival detail | `GET …/rivals/{scope}/{rivalId}?sort=closest&limit=0&offset=0`, `…/leaderboard-rivals/{instrument}/{rivalId}?rankBy=&sort=` | 404 "not precomputed" → empty. Never `allowLiveFallback`/`includeGaps` (live computation, not allowlisted) |
| All combos | `GET /api/player/{id}/rivals/all` | `GetRivalsAllAsync`, used by Suggestions |
| Find Rival | `GET /api/account/search` | Same read as Find Player; the selected player is excluded |

Rivals reads are unpinned operational GETs through `RequestGate` (see [service-safety](../../platforms/service-safety.md)); `POST …/rivals/recompute` has no builder. `FestivalSession.Rivals` reads through `RivalsReadCache` (in-process, 120 s = the service's `max-age`, 64 entries, failures never cached, cleared by F5 Refresh); concurrent callers share one request, so Common Rivals reuses the per-instrument lists. A 503 with `X-FST-Public-Read-Freeze-Reason: scrape` shows the shared `ServiceStatusView` countdown (page) or the inline status (hub card); observed live on detail reads during scrapes while list reads kept answering.

## Typed scope (no navigation state)

`RivalScope` travels on the routes: `Song(instruments)` (2+ = Common Rivals), `Leaderboard(instrument, rankBy)`, `Combo(token)` (instruments decoded from the hex mask or `pro_drums`), `FromSettings(Common|Combo)` for web links without instruments (resolved against Settings at load). Paths: `/rivals/all?category=…&mode=leaderboard&rankBy=…[&instruments=…]` (web-compatible), `/rivals/{id}?name=&scope=song:Solo_Guitar`, `/rivals/{id}/rivalry?mode=&name=&scope=`. A detail with no scope (Find Rival, bare deep link) merges every visible chart's detail (web `fetchCombinedRivalDetail`); one failing chart still shows the rest.

## Layout

- **Hub** (`RivalsPage`, cached): title + Find Rival `AutoSuggestBox` (Ctrl+F); `SelectorBar` Song Rivals / Leaderboard Rivals; rank-by `ComboBox` only with experimental ranks; Jump To menu (web quick links). Sections: Common Rivals (2+ visible charts), Combined / Pro Drums Family, then one per visible chart; 3 above + 3 below, See All. Cards use `MasonryLayout` (min 360 epx columns: 1 compact, 2 medium, 3–4 wide) so short cards don't stretch. Empty sections are removed; all empty → web empty state.
- **Rows** (`RivalRowView`): win/lose tint bar, `#rank` for leaderboard rivals, name, shared count, "N songs ahead" (rival's `behindCount`) and "N songs behind" (`aheadCount`) pills in a wrap panel.
- **All Rivals**: virtualized `ListView`, centred to 960 epx; subtitle shows leaderboard metric + your rank, or the Common/Combined charts.
- **Rival Detail**: name, scope label, head-to-head summary (web `rivals.detail.summary`), View Profile (`AppRoute.Player`); web categories (`RivalCategorization`, same keys/thresholds/descriptions) as masonry cards with 5 compact songs and "View all N songs".
- **Rivalry**: category title, "vs. name · description", native sort `ComboBox` (Default, Closest Gap, Your/Their Biggest Leads, Title; the web has none), virtualized full rows (You | rank & score gaps | Them). Rows open Song Detail on that chart.
- `RivalSongRowView` collapses to the one-line layout below 380 epx and hides art/icons below 280 epx. Headers stack below 640 epx page width.
- `/compete` and `/rivals` deep links show the Rivals section root (no Compete section on Windows; the Leaderboards section covers the rest).
- Brushes: `Controls/RivalsResources.xaml` (merged in `App.xaml`), lighter red text for contrast, High Contrast maps to system colours.

## Tests and tools

| Layer | Where |
|---|---|
| Core | `RivalsCoreTests` (models, endpoints, client, scope/combos/categories/formatting), `RivalsViewModelTests` (hub, Find Rival, pages, session merge, cache), route round-trips in `RoutingSettingsLaunchTests` |
| UI journeys | `python tools/windows/rivals_journey.py [--shots DIR] [--sizes compact,medium,wide]`: populated hub → both tabs → Jump To → detail → rivalry sort → All Rivals, empty (`fixture-player-empty`), scrape freeze (`fixture-player-503`), no player (`FST_DEBUG_ANONYMOUS`), `/compete` |
| Fixture | `tools/windows/rivals_fixture.py` = `tools/mock_service.py` with anonymized rival names (committable screenshots) |
| Screenshots | `windows/reports/screenshots/rivals-*-{compact,medium,wide}.png` (fixture mode) |

## IDs

`fst.rivals.title`, `.findRival`, `.tab`, `.tab.song`, `.tab.leaderboard`, `.rankBy`, `.jump`, `.jump.[leaderboard.]<sectionId>`, `.section.<common|combo|Solo_*>` / `.section.leaderboard.<Solo_*>` (card title; distinct per tab because ItemsRepeater keeps recycled off-screen cards and the driver takes the first match), `.see-all`, `.row.<accountId>`, `.empty`, `.chooseProfile`, `.selectPlayer`, `.page-empty`; `fst.all-rivals.title`, `.list`, `.row.<accountId>`; `fst.rival-detail.title`, `.scope`, `.summary`, `.view-profile`, `.category.<key>`, `.see-all`; `fst.rivalry.title`, `.sort`, `.view-profile`, `.list`, `.song.<songId>.<instrument>`; inline status `fst.service-status.inline`. IDs sit on TextBlocks or controls: panels/borders have no UIA peer.

## Open

- Compact (500 epx) window: the shell keeps the pane expanded (`PaneDisplayMode="Left"`), leaving ~240 epx of content. Rivals stays usable (wrapping pills, compact rows), but the shell should collapse the pane (TODO(orchestrator): shell lane).
- Find Rival for untracked accounts usually has no precomputed detail (the web passes `allowLiveFallback=true`, not allowlisted) → "No song data for this rival."
- Rivals first-run slides, Narrator pass and Axe scan pending (accessibility phase).
